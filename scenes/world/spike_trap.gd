class_name SpikeTrap
extends Area2D

## 3x3 地刺：玩家或怪物经过后延迟弹出，持续数秒伤害范围内所有目标，再回收。
## 触发范围、伤害范围和视觉底座都是 48x48 像素。

const AREA_SIZE: Vector2 = Vector2(48.0, 48.0)
const TELEGRAPH_TIME: float = 2.0
const ACTIVE_TIME: float = 3.0
const RETRACT_TIME: float = 0.25
const COOLDOWN_TIME: float = 1.0
const DAMAGE_INTERVAL: float = 0.5
const DAMAGE: float = 4.0

const IDLE: int = 0
const TELEGRAPH: int = 1
const ACTIVE: int = 2
const RETRACT: int = 3
const COOLDOWN: int = 4

var _state: int = IDLE
var _timer: float = 0.0
var _damage_timer: float = 0.0
var _player_notified: bool = false


func _ready() -> void:
	# 地刺要压过草层（草前层 z=1），否则玩家几乎看不到。
	z_index = 2
	add_to_group("world_traps")
	collision_layer = 0
	collision_mask = 3
	monitoring = true
	monitorable = false
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = AREA_SIZE
	shape_node.shape = rectangle
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	set_process(false)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if not _is_target(body):
		return
	if _scene_manager_is_transitioning():
		return
	if _state != IDLE:
		return
	_state = TELEGRAPH
	_timer = TELEGRAPH_TIME
	_player_notified = false
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	match _state:
		TELEGRAPH:
			_timer -= delta
			if _timer <= 0.0:
				_activate()
		ACTIVE:
			_timer -= delta
			_damage_timer -= delta
			if _damage_timer <= 0.0:
				_damage_tick()
				_damage_timer += DAMAGE_INTERVAL
			if _timer <= 0.0:
				_state = RETRACT
				_timer = RETRACT_TIME
				queue_redraw()
		RETRACT:
			_timer -= delta
			if _timer <= 0.0:
				_state = COOLDOWN
				_timer = COOLDOWN_TIME
				queue_redraw()
		COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_state = IDLE
				set_process(false)
				queue_redraw()


func _activate() -> void:
	_state = ACTIVE
	_timer = ACTIVE_TIME
	_damage_timer = 0.0
	_damage_tick()
	_play_sfx(&"hit_stone", global_position)
	queue_redraw()


## 持续伤害：每 0.5 秒扫描一次 3x3 范围，玩家和怪物都结算。
func _damage_tick() -> void:
	for body: Node2D in get_overlapping_bodies():
		if body is PlayerCharacter:
			(body as PlayerCharacter).take_damage(DAMAGE, self)
			if not _player_notified:
				_notify("地刺弹出，持续对范围内目标造成伤害")
				_player_notified = true
		elif body is BaseMonster:
			# 复用怪物的连锁伤害入口，保留受击、击退、死亡和掉落结算。
			(body as BaseMonster).apply_chain_damage(DAMAGE, self)


func _is_target(body: Node2D) -> bool:
	return body is PlayerCharacter or body is BaseMonster


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
	draw_rect(Rect2(-24, -24, 48, 48), Color("1f241d", 0.25))
	draw_rect(Rect2(-22, -22, 44, 44), base)
	draw_rect(Rect2(-19, -19, 38, 38), dark)
	draw_line(Vector2(-18, -20), Vector2(18, -20), Color("b8b49a"), 1.0)
	draw_line(Vector2(-18, 20), Vector2(18, 20), Color("85836f"), 1.0)
	for row: int in 3:
		for column: int in 3:
			var point := Vector2(-16.0 + float(column) * 16.0, -16.0 + float(row) * 16.0)
			draw_circle(point, 4.0, Color("1b1c18"))
			draw_circle(point, 2.0, Color("0e0f0d"))
	if _state == TELEGRAPH:
		var pulse: float = 0.22 + 0.18 * sin(_timer * 18.0)
		draw_rect(Rect2(-25, -25, 50, 50), Color("e8b45e", pulse), false, 2.0)
		for row: int in 3:
			for column: int in 3:
				var point := Vector2(-16.0 + float(column) * 16.0, -16.0 + float(row) * 16.0)
				draw_spike(point, 0.28)
	elif _state == ACTIVE:
		for row: int in 3:
			for column: int in 3:
				var point := Vector2(-16.0 + float(column) * 16.0, -16.0 + float(row) * 16.0)
				draw_spike(point, 1.0)
	elif _state == RETRACT:
		var scale: float = clampf(_timer / RETRACT_TIME, 0.0, 1.0)
		for row: int in 3:
			for column: int in 3:
				var point := Vector2(-16.0 + float(column) * 16.0, -16.0 + float(row) * 16.0)
				draw_spike(point, scale)
	elif _state == COOLDOWN:
		draw_rect(Rect2(-23, -23, 46, 46), Color("6d6a55", 0.35), false, 1.0)


func draw_spike(point: Vector2, scale: float) -> void:
	if scale <= 0.01:
		return
	var height: float = 20.0 * scale
	draw_colored_polygon(PackedVector2Array([
		point + Vector2(-5.0, 5.0),
		point + Vector2(0.0, -height),
		point + Vector2(5.0, 5.0),
	]), Color("d9d3b6"))
	draw_line(point + Vector2(0.0, -height + 2.0), point + Vector2(0.0, 4.0), Color("fff4cf"), 1.0)