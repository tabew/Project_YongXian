extends SceneTree

## 音频系统单元测试：素材与参数表一致性、总线布局、限流、音量静音、音乐切换。
## 运行：godot --headless --path . --script res://tests/test_audio.gd

const SFX_DIR: String = "res://assets/audio/sfx"
const MUSIC_DIR: String = "res://assets/audio/music"
const MUSIC_IDS: Array[StringName] = [&"music_menu", &"music_wilds"]

var _checks: int = 0
var _failures: int = 0
var _audio: Node = null
## 素材要先在编辑器里导入过才 load 得到；没导入时跳过依赖素材的断言。
var _assets_ready: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_audio = _resolve_manager()
	_assets_ready = not _audio.sfx_ids().is_empty()
	if not _assets_ready:
		push_warning("音频素材尚未导入：先在 Godot 编辑器里打开一次工程，再运行本测试。")

	_test_bus_layout()
	_test_spec_table()
	_test_asset_parity()
	_test_streams_loaded()
	_test_import_settings()
	_test_throttling()
	_test_volume_and_mute()
	_test_music()
	_test_unknown_ids()

	# 等淡出补间跑完再退出，避免退出时残留未完成的 Tween。
	for _frame: int in range(5):
		await process_frame

	print("AUDIO: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 正常运行时用自动加载单例；单独跑本脚本时自己建一个，保证测试自洽。
func _resolve_manager() -> Node:
	var existing: Node = root.get_node_or_null("AudioManager")
	if existing != null:
		return existing
	var script: GDScript = load("res://autoloads/audio_manager.gd") as GDScript
	var manager: Node = script.new()
	manager.name = "AudioManager"
	root.add_child(manager)
	return manager


func _test_bus_layout() -> void:
	for bus: StringName in [&"Master", &"Music", &"SFX", &"UI"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "总线存在：%s" % bus)


func _test_spec_table() -> void:
	var defaults: Dictionary = SfxSpec.for_id(&"not_a_sound")
	_check(defaults["bus"] == &"SFX", "未登记的 id 退回默认总线")
	_check(float(defaults["max_voices"]) >= 1.0, "默认同时发声上限有效")
	var overload: Dictionary = SfxSpec.for_id(&"brew_overload")
	_check(float(overload["min_interval"]) >= 0.5, "过载音效设置了较长最小间隔")
	_check(SfxSpec.has(&"ui_click"), "界面音效已登记")
	_check(not SfxSpec.has(&"not_a_sound"), "未登记 id 的 has 为假")
	_check(SfxSpec.for_id(&"ui_click")["bus"] == &"UI", "界面音效走 UI 总线")


func _test_asset_parity() -> void:
	for id: StringName in SfxSpec.ids():
		_check(FileAccess.file_exists(SFX_DIR.path_join("%s.wav" % id)), "参数表登记的音效有素材：%s" % id)
	for file_name: String in DirAccess.get_files_at(SFX_DIR):
		if file_name.get_extension().to_lower() != "wav":
			continue
		_check(SfxSpec.has(StringName(file_name.get_basename())), "素材已在参数表登记：%s" % file_name)
	for music_id: StringName in MUSIC_IDS:
		_check(FileAccess.file_exists(MUSIC_DIR.path_join("%s.wav" % music_id)), "音乐素材存在：%s" % music_id)


func _test_streams_loaded() -> void:
	_check(not _audio.has_sfx(&"not_a_sound"), "未知音效返回 false")
	if not _assets_ready:
		return
	_check(_audio.has_sfx(&"hit_flesh"), "命中音效已加载")
	_check(_audio.has_sfx(&"brew_overload"), "过载音效已加载")
	_check(_audio.sfx_ids().size() >= SfxSpec.ids().size(), "加载的音效数量不少于参数表")
	_check(_audio.has_music(&"music_wilds"), "音乐已加载")


## 导入设置是素材质量的隐形开关：默认会被导成有损 QOA，且音乐不循环。
func _test_import_settings() -> void:
	for id: StringName in SfxSpec.ids():
		var path: String = SFX_DIR.path_join("%s.wav.import" % id)
		if not FileAccess.file_exists(path):
			continue
		var text: String = FileAccess.get_file_as_string(path)
		_check(text.contains("compress/mode=0"), "音效用无压缩 PCM：%s" % id)
	for music_id: StringName in MUSIC_IDS:
		var music_path: String = MUSIC_DIR.path_join("%s.wav.import" % music_id)
		if not FileAccess.file_exists(music_path):
			continue
		var music_text: String = FileAccess.get_file_as_string(music_path)
		_check(music_text.contains("compress/mode=0"), "音乐用无压缩 PCM：%s" % music_id)
		_check(music_text.contains("edit/loop_mode=1"), "音乐导入时标记循环：%s" % music_id)


func _test_throttling() -> void:
	var id: StringName = &"brew_overload"
	_check(_audio.active_voice_count(id) == 0, "初始没有发声实例")
	if not _assets_ready:
		return
	_audio.play_sfx(id)
	_check(_audio.active_voice_count(id) == 1, "首次播放占用一个发声位")
	_audio.play_sfx(id)
	_audio.play_sfx(id)
	_check(_audio.active_voice_count(id) == 1, "最小间隔内不重复播放")
	_audio.play_sfx(&"ui_click")
	_check(_audio.active_voice_count(&"ui_click") == 1, "不同音效各自计数")
	_check(_audio.active_voice_count(id) <= int(SfxSpec.for_id(id)["max_voices"]),
			"同时发声数不超过参数表上限")


func _test_volume_and_mute() -> void:
	var index: int = AudioServer.get_bus_index(&"SFX")
	_audio.set_bus_volume(&"SFX", 0.5)
	_check(is_equal_approx(_audio.bus_volume(&"SFX"), 0.5), "线性音量可以读回")
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.5),
			"线性音量换算成分贝后生效")
	_audio.set_muted(true)
	_check(_audio.muted, "静音状态已记录")
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "静音作用于 Master 总线")
	_audio.set_muted(false)
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "取消静音")
	_audio.set_bus_volume(&"SFX", 1.0)


func _test_music() -> void:
	if _assets_ready:
		_audio.play_music(&"music_menu")
		_check(_audio.current_music() == &"music_menu", "切到主菜单音乐")
		var stream: AudioStream = load(MUSIC_DIR.path_join("music_menu.wav"))
		var wav: AudioStreamWAV = stream as AudioStreamWAV
		_check(wav != null, "音乐素材是 WAV 流")
		if wav != null:
			_check(wav.loop_mode != AudioStreamWAV.LOOP_DISABLED, "播放音乐时会自动打开循环")
		_audio.play_music(&"music_wilds")
		_check(_audio.current_music() == &"music_wilds", "切到探索音乐")
	_audio.stop_music()
	_check(_audio.current_music() == &"", "停止后没有当前音乐")


func _test_unknown_ids() -> void:
	_audio.play_sfx(&"definitely_missing")
	_audio.play_sfx(&"definitely_missing", Vector2(10.0, 10.0))
	_audio.play_music(&"definitely_missing_music")
	_check(_audio.current_music() == &"", "缺少素材的音乐不会改变当前音乐")
	_check(_audio.active_voice_count(&"definitely_missing") == 0, "缺少素材的音效不占用发声位")