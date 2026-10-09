class_name SwingAttack
extends WeaponAttack

const MAX_SWEEP_STEP: float = PI / 36.0

@onready var blade: Sprite2D = $Blade

var _swing: SwingWeaponDefinition
var _direction: float = 1.0
var _start_angle: float = 0.0
var _angle: float = 0.0
var _previous_origin: Vector2
var _trail_span: float = 0.0
var _trail_alpha: float = 0.0
var _shape: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
var _query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()


func accepts_definition(data: WeaponDefinition) -> bool:
	return data is SwingWeaponDefinition


func _on_started() -> void:
	_swing = definition as SwingWeaponDefinition
	_direction = -1.0 if aim_direction.x < 0.0 else 1.0
	_start_angle = aim_direction.angle() + deg_to_rad(_swing.aim_offset_degrees) - _direction * deg_to_rad(_swing.arc_degrees) * 0.5
	_previous_origin = global_position
	blade.texture = _swing.texture
	blade.centered = false
	blade.offset = -_swing.texture_grip
	var visual_scale: float = _swing.blade_length / (_swing.texture.get_width() - _swing.texture_grip.x)
	blade.scale = Vector2.ONE * visual_scale
	_query.shape = _shape
	_query.collision_mask = definition.hit_mask
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	_set_pose(0.0)


func _advance(previous: float, current: float) -> void:
	var active_start: float = definition.windup_seconds
	var active_end: float = active_start + definition.active_seconds
	# Clip the entire elapsed interval, so a short active phase cannot be skipped.
	if current >= active_start and previous < active_end:
		var from_time: float = maxf(previous, active_start)
		var to_time: float = minf(current, active_end)
		var frame_time: float = maxf(current - previous, 0.000001)
		var from_origin: Vector2 = _previous_origin.lerp(global_position, (from_time - previous) / frame_time)
		var to_origin: Vector2 = _previous_origin.lerp(global_position, (to_time - previous) / frame_time)
		_sweep(_active_angle(from_time), _active_angle(to_time), from_origin, to_origin)
	_previous_origin = global_position
	_set_pose(minf(current, definition.attack_duration()))


func _active_angle(time: float) -> float:
	var progress: float = clampf((time - definition.windup_seconds) / definition.active_seconds, 0.0, 1.0)
	return _start_angle + _direction * deg_to_rad(_swing.arc_degrees) * smoothstep(0.0, 1.0, progress)


func _set_pose(time: float) -> void:
	var active_end: float = definition.windup_seconds + definition.active_seconds
	_angle = _active_angle(time)
	_trail_alpha = 0.0
	if time < definition.windup_seconds:
		_angle -= _direction * 0.18 * (1.0 - time / definition.windup_seconds)
	elif time <= active_end:
		_trail_alpha = 1.0
	else:
		var recovery: float = (time - active_end) / maxf(definition.recovery_seconds, 0.000001)
		_angle += _direction * 0.18 * recovery
		_trail_alpha = 1.0 - recovery
	_trail_span = minf(deg_to_rad(_swing.trail_degrees), absf(_active_angle(time) - _start_angle))
	blade.rotation = _angle
	blade.position = Vector2.from_angle(_angle) * _swing.hand_distance
	queue_redraw()


func _sweep(from_angle: float, to_angle: float, from_origin: Vector2, to_origin: Vector2) -> void:
	var steps: int = maxi(1, ceili(absf(to_angle - from_angle) / MAX_SWEEP_STEP))
	for index: int in range(steps):
		var t0: float = float(index) / steps
		var t1: float = float(index + 1) / steps
		var points: PackedVector2Array = _blade_corners(lerpf(from_angle, to_angle, t0), from_origin.lerp(to_origin, t0) - global_position)
		points.append_array(_blade_corners(lerpf(from_angle, to_angle, t1), from_origin.lerp(to_origin, t1) - global_position))
		_shape.points = Geometry2D.convex_hull(points)
		_query.transform = Transform2D(0.0, global_position)
		_query_hurtboxes(_query)


func _blade_corners(angle: float, origin: Vector2) -> PackedVector2Array:
	var axis: Vector2 = Vector2.from_angle(angle)
	var side: Vector2 = axis.orthogonal() * _swing.blade_width * 0.5
	var base: Vector2 = origin + axis * (_swing.hand_distance + _swing.blade_inset)
	var tip: Vector2 = origin + axis * (_swing.hand_distance + _swing.blade_length)
	return PackedVector2Array([base - side, tip - side, tip + side, base + side])


func _draw() -> void:
	if _swing == null or _trail_span <= 0.0 or _trail_alpha <= 0.0:
		return
	var outer: float = _swing.hand_distance + _swing.blade_length
	var inner: float = _swing.hand_distance + _swing.blade_inset
	for index: int in range(12):
		var t0: float = float(index) / 12.0
		var t1: float = float(index + 1) / 12.0
		var a: Vector2 = Vector2.from_angle(_angle - _direction * _trail_span * t0)
		var b: Vector2 = Vector2.from_angle(_angle - _direction * _trail_span * t1)
		var color: Color = _swing.trail_color
		color.a *= (1.0 - t0) * _trail_alpha
		draw_colored_polygon(PackedVector2Array([a * inner, a * outer, b * outer, b * inner]), color)
