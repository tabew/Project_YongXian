class_name ShabeiMonster
extends BaseMonster

## 啥杯独有的两跳一停、原地尖叫和胆小逃离，继续复用通用AI和导航。
const HOP_DURATION: float = 0.22
const HOP_REST: float = 1.0
var screaming: bool = false
var fleeing: bool = false
var mouth_open: float = 0.0:
	set(value):
		if is_equal_approx(mouth_open, value):
			return
		mouth_open = value
		var body := get_node_or_null("Visual/Body") as CanvasItem
		if body != null:
			body.queue_redraw()
var body_squash: Vector2 = Vector2.ONE:
	set(value):
		body_squash = value
		var body := get_node_or_null("Visual/Body") as Node2D
		if body != null:
			body.scale = value
var _scream_audio: AudioStreamPlayer2D
static var _scream_stream: AudioStreamWAV
var _hop_active: bool = false
var _hop_elapsed: float = 0.0
var _hop_count: int = 0
var _hop_rest: float = 0.0

func _create_attack() -> EnemyAttack:
	return ShabeiScreamAttack.new()

func _physics_process(delta: float) -> void:
	_hop_rest = maxf(_hop_rest - delta, 0.0)
	super._physics_process(delta)
	if screaming or is_receiving_knockback():
		_hop_active = false
		return
	if _hop_active:
		_hop_elapsed += delta
		if _hop_elapsed >= HOP_DURATION:
			_hop_active = false
			_hop_count += 1
			if _hop_count >= 2:
				_hop_count = 0
				_hop_rest = HOP_REST
				velocity = Vector2.ZERO
				play_monster_animation(&"Rest", true)

func movement_speed() -> float:
	if screaming or _hop_rest > 0.0:
		return 0.0
	return navigation_speed * (1.5 if fleeing else 1.0)

func play_monster_animation(state: StringName, restart: bool = false) -> void:
	if screaming and state in [&"Move", &"Idle"]:
		state = &"Scream"
	elif state == &"Move":
		if _hop_rest > 0.0:
			state = &"Rest"
		else:
			if not _hop_active:
				_hop_active = true
				_hop_elapsed = 0.0
				restart = true
			state = &"Hop"
	elif state == &"Idle" and _hop_rest > 0.0:
		state = &"Rest"
	elif state == &"Idle" and _hop_active and not _death_committed:
		return
	super.play_monster_animation(state, restart)

func stop_navigation() -> void:
	velocity = Vector2.ZERO
	if monster_animation_state() in [&"Idle", &"Hop", &"Rest"] and not _hop_active:
		play_monster_animation(&"Idle")

func begin_scream() -> void:
	screaming = true
	fleeing = false
	_hop_active = false
	_hop_rest = 0.0
	_hop_count = 0
	_visual_height = 0.0
	velocity = Vector2.ZERO
	navigator.clear()
	play_monster_animation(&"Scream", true)
	_start_scream_sound()

func _start_scream_sound() -> void:
	if _scream_stream == null:
		var samples := PackedByteArray()
		var rate: int = 11025
		samples.resize(rate * 4)
		for index: int in samples.size():
			var time: float = float(index) / rate
			var envelope: float = minf(time / 0.06, 1.0) * minf((4.0-time)/0.08,1.0)
			var tone: float = sin(TAU * (700.0*time + 35.0*sin(time*9.0))) * 0.65 + sin(TAU*1400.0*time)*0.2
			samples[index] = clampi(roundi(128.0 + tone * envelope * 75.0), 0, 255)
		_scream_stream = AudioStreamWAV.new()
		_scream_stream.format = AudioStreamWAV.FORMAT_8_BITS
		_scream_stream.mix_rate = rate
		_scream_stream.data = samples
	if _scream_audio == null:
		_scream_audio = AudioStreamPlayer2D.new()
		_scream_audio.volume_db = -12.0
		_scream_audio.max_distance = 480.0
		_scream_audio.stream = _scream_stream
		add_child(_scream_audio)
	_scream_audio.play()

func stop_scream_sound() -> void:
	if is_instance_valid(_scream_audio):
		_scream_audio.stop()

func finish_flee() -> void:
	stop_scream_sound()
	screaming = false
	fleeing = false
	mouth_open = 0.0
	navigator.clear()
	brain.abandon_target()
	play_monster_animation(&"Idle", true)
