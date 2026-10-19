class_name BossSoulMissile
extends Node2D

signal resolved
signal expired(position: Vector2)

const LIFE_SECONDS: float = 4.0
const SPEED: float = 192.0
const HIT_RADIUS: float = 12.0

var boss: BaseMonster
var target: PlayerCharacter
var _direction: Vector2 = Vector2.RIGHT
var _remaining: float = LIFE_SECONDS
var _finished: bool = false


func launch(owner: BaseMonster, player: PlayerCharacter, origin: Vector2, direction: Vector2) -> void:
	boss = owner
	target = player
	global_position = origin
	_direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT


func _physics_process(delta: float) -> void:
	if _finished:
		return
	if not is_instance_valid(boss) or boss.is_queued_for_deletion() or int(boss.get("phase")) != 1:
		_finish()
		return
	if not is_instance_valid(target) or target.health <= 0.0:
		_finish()
		return
	var old_position: Vector2 = global_position
	var desired: Vector2 = (target.global_position - global_position).normalized()
	if not desired.is_zero_approx():
		_direction = _direction.lerp(desired, clampf(delta * 5.0, 0.0, 1.0)).normalized()
	global_position += _direction * SPEED * delta
	_remaining -= delta
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(target.global_position, old_position, global_position)
	if closest.distance_to(target.global_position) <= HIT_RADIUS:
		target.take_damage(10.0, boss)
		target.apply_fear(2.0)
		_finish()
		return
	if _remaining <= 0.0:
		expired.emit(global_position)
		_finish()
		return
	queue_redraw()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	resolved.emit()
	queue_free()


func _draw() -> void:
	var pulse: float = 0.7 + 0.3 * sin(_remaining * 12.0)
	draw_circle(Vector2.ZERO, 9.0, Color(0.7, 0.21, 0.53, 0.25 * pulse))
	draw_circle(Vector2.ZERO, 5.0, Color(0.91, 0.65, 0.88, pulse))
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, Color(1.0, 0.88, 0.94, 0.9 * pulse), 1.0)
