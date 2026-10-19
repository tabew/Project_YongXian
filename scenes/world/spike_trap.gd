class_name SpikeTrap
extends Area2D

## 第一版无交互环境危险：踩到后短暂预警，再弹出地刺。
## 只检测玩家层（1），不会误伤怪物；伤害带冷却，避免站在上面连续掉血。

const TRIGGER_RADIUS: float = 10.0
const TELEGRAPH_TIME: float = 0.28
const ACTIVE_TIME: float = 0.24
const COOLDOWN_TIME: float = 1.6
const DAMAGE: float = 6.0

const IDLE: int = 0
const TELEGRAPH: int = 1
const ACTIVE: int = 2
const COOLDOWN: int = 3

var _state: int = IDLE
var _timer: float = 0.0
var _target: PlayerCharacter = null


func _ready() -> void:
	add_to_group("world_traps")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	var shape_node := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = TRIGGER_RADIUS
	shape_node.shape = circle
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	set_process(false)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _state != IDLE or not body is PlayerCharacter:
		return
	if _scene_manager_is_transitioning():
		return
	_target = body as PlayerCharacter
	_state = TELEGRAPH
	_timer = TELEGRAPH_TIME
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	match _state:
		TELEGRAPH:
			_timer -= delta
			if _timer <= 0.0:
				_fire()
		ACTIVE:
			_timer -= delta
			if _timer <= 0.0:
				_state = COOLDOWN
				_timer = COOLDOWN_TIME
				queue_redraw()
		COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_state = IDLE
				_target = null
				set_process(false)
				queue_redraw()


func _fire() -> void:
	_state = ACTIVE
	_timer = ACTIVE_TIME
	if is_instance_valid(_target) and _target.global_position.distance_to(global_position) <= TRIGGER_RADIUS + 9.0:
		_target.take_damage(DAMAGE, self)
		_notify("地刺弹出，受到 %d 点伤害" % int(DAMAGE))
	_play_sfx(&"hit_stone", global_position)
	queue_redraw()


func _scene_manager_is_transitioning() -> bool:
	var manager := get_node_or_null("/root/SceneManager")
	return manager != null and bool(manager.call("is_transitioning"))


func _notify(message: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit_signal("notification", message)


func _play_sfx(id: StringName, position: Vector2) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.call("play_sfx", id, position)


func _draw() -> void:
	var base := Color("5b5b50")
	var dark := Color("2e2e29")
	draw_rect(Rect2(-11, -7, 22, 14), Color("1f241d", 0.22))
	draw_rect(Rect2(-10, -6, 20, 12), base)
	draw_rect(Rect2(-8, -4, 16, 8), dark)
	for x: int in [-6, 0, 6]:
		draw_circle(Vector2(float(x), 0), 2.2, Color("1b1c18"))
	if _state == TELEGRAPH:
		var shake: float = sin(_timer * 70.0) * 1.4
		draw_rect(Rect2(-12 + shake, -8, 24, 16), Color("e8b45e", 0.35))
		for x: int in [-6, 0, 6]:
			draw_colored_polygon(PackedVector2Array([
				Vector2(float(x) - 3.0, 3.0),
				Vector2(float(x), -2.0 + shake),
				Vector2(float(x) + 3.0, 3.0),
			]), Color("c9b37a"))
	elif _state == ACTIVE:
		for x: int in [-7, 0, 7]:
			draw_colored_polygon(PackedVector2Array([
				Vector2(float(x) - 4.0, 5.0),
				Vector2(float(x), -14.0),
				Vector2(float(x) + 4.0, 5.0),
			]), Color("d9d3b6"))
			draw_line(Vector2(float(x), -13.0), Vector2(float(x), 4.0), Color("fff4cf"), 1.0)