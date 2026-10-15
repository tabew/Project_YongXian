extends Node

## 全局音频管理器（自动加载单例 AudioManager）。
##
## 三件事：
## 1. 启动时扫描 assets/audio，文件名即音效 id，新增素材不需要改脚本。
## 2. 用播放器池播放一次性音效，位置有限的调用走 2D 定位并按距离衰减。
## 3. 管理 Music 播放与交叉淡入淡出、各总线音量与静音，并持久化到 user://。
##
## 音量与同时发声数由 SfxSpec 表控制，避免连击时糊成一片。
## 素材目前是程序化生成的占位音频（tools/generate_sfx.py），换成正式素材时直接覆盖同名文件。
## 首次打开工程后 Godot 才会导入 wav，导入前 play_sfx 会安静地什么都不做。

const SFX_DIR: String = "res://assets/audio/sfx"
const MUSIC_DIR: String = "res://assets/audio/music"
const SETTINGS_PATH: String = "user://audio_settings.cfg"
const AUDIO_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_UI: StringName = &"UI"

const SFX_VOICE_COUNT: int = 16
const SPATIAL_VOICE_COUNT: int = 12
const UI_VOICE_COUNT: int = 6
const MUSIC_VOICE_COUNT: int = 2

const DEFAULT_MUSIC_FADE: float = 1.2
const SILENT_DB: float = -60.0
const SPATIAL_MAX_DISTANCE: float = 900.0
const SPATIAL_ATTENUATION: float = 1.6
const MIN_LINEAR_VOLUME: float = 0.0001

signal music_changed(music_id: StringName)
signal mute_changed(is_muted: bool)

var muted: bool = false

var _sfx_streams: Dictionary = {}
var _music_streams: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _spatial_pool: Array[AudioStreamPlayer2D] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _music_pool: Array[AudioStreamPlayer] = []
var _cursors: Dictionary = {}
var _last_played: Dictionary = {}
var _voices: Dictionary = {}
var _volumes: Dictionary = {}
var _music_index: int = 0
var _current_music: StringName = &""
var _music_tween: Tween = null
var _pitch_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	# 音频不受游戏暂停影响，界面音在暂停菜单里也要能响。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pitch_rng.randomize()
	_build_pools()
	_load_streams()
	_load_settings()
	EventBus.world_ready.connect(_on_world_ready)


## 退出时停掉所有声音并释放素材引用，避免关闭阶段残留资源警告。
func _exit_tree() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	for pool: Array in [_sfx_pool, _spatial_pool, _ui_pool, _music_pool]:
		for voice: Variant in pool:
			var node: Node = voice as Node
			if is_instance_valid(node):
				node.call("stop")
				node.set("stream", null)
	_sfx_streams.clear()
	_music_streams.clear()
	_voices.clear()


# --- 查询 -------------------------------------------------------------------

func has_sfx(id: StringName) -> bool:
	return _sfx_streams.has(id)


func has_music(id: StringName) -> bool:
	return _music_streams.has(id)


func current_music() -> StringName:
	return _current_music


func is_music_playing() -> bool:
	for player: AudioStreamPlayer in _music_pool:
		if player.playing:
			return true
	return false


## 已加载的音效 id，供调试与单元测试核对。
func sfx_ids() -> Array:
	return _sfx_streams.keys()


func music_ids() -> Array:
	return _music_streams.keys()


## 当前正在发声的实例数，供调试与单元测试使用。
func active_voice_count(id: StringName) -> int:
	_prune_voices(id)
	return (_voices.get(id, []) as Array).size()


# --- 播放 -------------------------------------------------------------------

## 播放一次性音效。position 有限时按 2D 定位（距离衰减），否则按 SfxSpec 的总线非定位播放。
## 缺少素材、被最小间隔拦下或超过同时发声上限时静默返回。
func play_sfx(id: StringName, position: Vector2 = Vector2.INF) -> void:
	var stream: AudioStream = _sfx_streams.get(id)
	if stream == null:
		return
	var spec: Dictionary = SfxSpec.for_id(id)
	if not _may_play(id, spec):
		return
	if position.is_finite():
		var spatial: AudioStreamPlayer2D = _take_spatial_voice()
		if spatial == null:
			return
		spatial.global_position = position
		_configure_voice(spatial, stream, spec)
		spatial.play()
		_remember_voice(id, spatial)
		return
	var bus: StringName = spec["bus"]
	var voice: AudioStreamPlayer = _take_pool_voice(_ui_pool if bus == BUS_UI else _sfx_pool,
			&"ui" if bus == BUS_UI else &"sfx")
	if voice == null:
		return
	_configure_voice(voice, stream, spec)
	voice.play()
	_remember_voice(id, voice)


## 播放音乐；同一首正在播放时不重复触发。素材缺失只警告一次，不影响游戏。
func play_music(id: StringName, fade: float = DEFAULT_MUSIC_FADE) -> void:
	if id == _current_music and is_music_playing():
		return
	var stream: AudioStream = _music_streams.get(id)
	if stream == null:
		push_warning("缺少音乐素材 %s，把同名文件放进 %s 即可。" % [id, MUSIC_DIR])
		return
	_enable_loop(stream)
	var outgoing: AudioStreamPlayer = _music_pool[_music_index]
	_music_index = (_music_index + 1) % _music_pool.size()
	var incoming: AudioStreamPlayer = _music_pool[_music_index]
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", 0.0, fade)
	if outgoing.playing:
		_music_tween.tween_property(outgoing, "volume_db", SILENT_DB, fade)
		_music_tween.chain().tween_callback(outgoing.stop)
	_current_music = id
	music_changed.emit(id)


func stop_music(fade: float = DEFAULT_MUSIC_FADE) -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	var fading: bool = false
	_music_tween = create_tween().set_parallel(true)
	for player: AudioStreamPlayer in _music_pool:
		if player.playing:
			_music_tween.tween_property(player, "volume_db", SILENT_DB, fade)
			fading = true
	if fading:
		_music_tween.chain().tween_callback(_stop_music_voices)
	_current_music = &""
	music_changed.emit(&"")


# --- 音量与静音 -------------------------------------------------------------

## linear 为 0~1 的线性音量；总线上按分贝生效，写进 user:// 配置供下次启动读取。
func set_bus_volume(bus: StringName, linear: float) -> void:
	var value: float = clampf(linear, 0.0, 1.0)
	_volumes[bus] = value
	_apply_bus_volume(bus, value)
	_save_settings()


func bus_volume(bus: StringName) -> float:
	return float(_volumes.get(bus, 1.0))


func set_muted(value: bool) -> void:
	if muted == value:
		return
	muted = value
	var index: int = AudioServer.get_bus_index(BUS_MASTER)
	if index >= 0:
		AudioServer.set_bus_mute(index, muted)
	mute_changed.emit(muted)
	_save_settings()


func toggle_muted() -> bool:
	set_muted(not muted)
	return muted


# --- 播放器池 ---------------------------------------------------------------

func _build_pools() -> void:
	for index: int in range(SFX_VOICE_COUNT):
		_sfx_pool.append(_make_voice("SfxVoice%d" % index, BUS_SFX))
	for index: int in range(UI_VOICE_COUNT):
		_ui_pool.append(_make_voice("UiVoice%d" % index, BUS_UI))
	for index: int in range(MUSIC_VOICE_COUNT):
		_music_pool.append(_make_voice("MusicVoice%d" % index, BUS_MUSIC))
	for index: int in range(SPATIAL_VOICE_COUNT):
		var spatial: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		spatial.name = "SpatialVoice%d" % index
		spatial.bus = BUS_SFX
		spatial.max_distance = SPATIAL_MAX_DISTANCE
		spatial.attenuation = SPATIAL_ATTENUATION
		add_child(spatial)
		_spatial_pool.append(spatial)


func _make_voice(voice_name: String, bus: StringName) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = voice_name
	player.bus = bus
	add_child(player)
	return player


## 用 set() 写属性，让 AudioStreamPlayer 与 AudioStreamPlayer2D 共用同一段配置。
func _configure_voice(voice: Node, stream: AudioStream, spec: Dictionary) -> void:
	voice.set("stream", stream)
	voice.set("bus", spec["bus"])
	voice.set("volume_db", float(spec["volume_db"]))
	voice.set("pitch_scale", _pitch_for(spec))


func _pitch_for(spec: Dictionary) -> float:
	var variation: float = float(spec["pitch_variation"])
	if variation <= 0.0:
		return 1.0
	return 1.0 + _pitch_rng.randf_range(-variation, variation)


## 空闲优先、全忙则抢最早的那一个，保证突发音效不会互相打断。
func _take_pool_voice(pool: Array[AudioStreamPlayer], key: StringName) -> AudioStreamPlayer:
	var size: int = pool.size()
	if size == 0:
		return null
	var start: int = int(_cursors.get(key, 0)) % size
	for offset: int in range(size):
		var index: int = (start + offset) % size
		if not pool[index].playing:
			_cursors[key] = (index + 1) % size
			return pool[index]
	pool[start].stop()
	_cursors[key] = (start + 1) % size
	return pool[start]


func _take_spatial_voice() -> AudioStreamPlayer2D:
	var size: int = _spatial_pool.size()
	if size == 0:
		return null
	var start: int = int(_cursors.get(&"spatial", 0)) % size
	for offset: int in range(size):
		var index: int = (start + offset) % size
		if not _spatial_pool[index].playing:
			_cursors[&"spatial"] = (index + 1) % size
			return _spatial_pool[index]
	_spatial_pool[start].stop()
	_cursors[&"spatial"] = (start + 1) % size
	return _spatial_pool[start]


func _stop_music_voices() -> void:
	for player: AudioStreamPlayer in _music_pool:
		player.stop()


# --- 限流 -------------------------------------------------------------------

func _may_play(id: StringName, spec: Dictionary) -> bool:
	_prune_voices(id)
	var voices: Array = _voices.get(id, [])
	if voices.size() >= int(spec["max_voices"]):
		return false
	var interval: float = float(spec["min_interval"])
	if interval <= 0.0:
		return true
	var last: int = int(_last_played.get(id, -100000))
	return Time.get_ticks_msec() - last >= int(interval * 1000.0)


func _remember_voice(id: StringName, voice: Node) -> void:
	_last_played[id] = Time.get_ticks_msec()
	var voices: Array = _voices.get(id, [])
	voices.append(voice)
	_voices[id] = voices


func _prune_voices(id: StringName) -> void:
	var voices: Array = _voices.get(id, [])
	if voices.is_empty():
		return
	var alive: Array = []
	for voice: Variant in voices:
		var node: Node = voice as Node
		if is_instance_valid(node) and node.get("playing") == true:
			alive.append(node)
	_voices[id] = alive


# --- 素材加载 ---------------------------------------------------------------

func _load_streams() -> void:
	_sfx_streams = _scan_directory(SFX_DIR)
	_music_streams = _scan_directory(MUSIC_DIR)


## 目录扫描：文件名（去掉扩展名）就是 id。wav 还没被编辑器导入时跳过，不报错。
func _scan_directory(directory: String) -> Dictionary:
	var streams: Dictionary = {}
	if not DirAccess.dir_exists_absolute(directory):
		push_warning("音频目录不存在：%s" % directory)
		return streams
	for file_name: String in DirAccess.get_files_at(directory):
		if not AUDIO_EXTENSIONS.has(file_name.get_extension().to_lower()):
			continue
		var path: String = directory.path_join(file_name)
		if not ResourceLoader.exists(path):
			continue
		var stream: AudioStream = load(path) as AudioStream
		if stream == null:
			continue
		streams[StringName(file_name.get_basename())] = stream
	return streams


## 音乐必须循环；导入设置里没开循环时在这里补上，省得依赖编辑器导入选项。
func _enable_loop(stream: AudioStream) -> void:
	var wav: AudioStreamWAV = stream as AudioStreamWAV
	if wav == null or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return
	var frames: int = _wav_frame_count(wav)
	if frames <= 0:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames


## 时长换算成帧数；对 ADPCM / QOA 这类压缩格式同样成立，不依赖原始字节数。
func _wav_frame_count(wav: AudioStreamWAV) -> int:
	return roundi(wav.get_length() * float(wav.mix_rate))


# --- 设置持久化 -------------------------------------------------------------

func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var loaded: bool = config.load(SETTINGS_PATH) == OK
	for bus: StringName in [BUS_MASTER, BUS_MUSIC, BUS_SFX, BUS_UI]:
		var value: float = float(config.get_value("volumes", String(bus), 1.0)) if loaded else 1.0
		_volumes[bus] = clampf(value, 0.0, 1.0)
		_apply_bus_volume(bus, _volumes[bus])
	muted = bool(config.get_value("audio", "muted", false)) if loaded else false
	var master: int = AudioServer.get_bus_index(BUS_MASTER)
	if master >= 0:
		AudioServer.set_bus_mute(master, muted)


func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "muted", muted)
	for bus: StringName in _volumes:
		config.set_value("volumes", String(bus), _volumes[bus])
	config.save(SETTINGS_PATH)


func _apply_bus_volume(bus: StringName, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, MIN_LINEAR_VOLUME)))


# --- 事件桥 -----------------------------------------------------------------

func _on_world_ready(_seed_value: int) -> void:
	play_sfx(&"world_ready")