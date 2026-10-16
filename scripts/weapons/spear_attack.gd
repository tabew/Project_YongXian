class_name SpearAttack
extends WeaponAttack

const EXTEND_RATIO: float = 0.6
const SWEEP_SAMPLES: int = 16

@onready var shaft: Sprite2D = $Shaft

var _spear: SpearWeaponDefinition
var _previous_origin: Vector2
var _shape: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
var _query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
var _thrust_index: int = -1
var _visual_time: float = 0.0


func accepts_definition(data: WeaponDefinition) -> bool:
	return data is SpearWeaponDefinition


func _on_started() -> void:
	_spear = definition as SpearWeaponDefinition
	_previous_origin = global_position
	_thrust_index = -1
	shaft.texture = _spear.texture
	shaft.centered = false
	shaft.offset = -_spear.texture_grip
	shaft.scale = Vector2.ONE * _spear.shaft_length / (_spear.texture.get_width() - _spear.texture_grip.x)
	shaft.rotation = aim_direction.angle()
	_query.shape = _shape
	_query.collision_mask = definition.hit_mask
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	_set_pose(0.0)


func _advance(previous: float, current: float) -> void:
	var duration: float = definition.active_seconds / float(_spear.thrust_count)
	var frame_time: float = maxf(current - previous, 0.000001)
	# Split every forward stroke, even if a whole sequence fits inside one frame.
	for index: int in _spear.thrust_count:
		var start: float = definition.windup_seconds + duration * index
		var end: float = start + duration * EXTEND_RATIO
		if current < start or previous >= end:
			continue
		if _thrust_index != index:
			_hit_receivers.clear()
			_thrust_index = index
		var from_time: float = maxf(previous, start)
		var to_time: float = minf(current, end)
		var from_origin: Vector2 = _previous_origin.lerp(global_position, (from_time - previous) / frame_time)
		var to_origin: Vector2 = _previous_origin.lerp(global_position, (to_time - previous) / frame_time)
		_sweep(from_time, to_time, from_origin, to_origin)
	_previous_origin = global_position
	_set_pose(minf(current, definition.attack_duration()))


func _hand_distance(time: float) -> float:
	var tucked: float = _spear.hand_distance - _spear.pullback_distance
	if time < definition.windup_seconds:
		return lerpf(_spear.hand_distance, tucked, smoothstep(0.0, definition.windup_seconds, time))
	var active_end: float = definition.windup_seconds + definition.active_seconds
	if time >= active_end:
		return lerpf(tucked, _spear.hand_distance, smoothstep(active_end, active_end + maxf(definition.recovery_seconds, 0.000001), time))
	var duration: float = definition.active_seconds / float(_spear.thrust_count)
	var phase: float = fposmod(time - definition.windup_seconds, duration) / duration
	var extension: float = smoothstep(0.0, EXTEND_RATIO, phase) if phase <= EXTEND_RATIO else 1.0 - smoothstep(EXTEND_RATIO, 1.0, phase)
	return lerpf(tucked, _spear.hand_distance + _spear.thrust_distance, extension)


func _tip(time: float) -> Vector2:
	return aim_direction * (_hand_distance(time) + _spear.shaft_length)


func _set_pose(time: float) -> void:
	_visual_time = time
	shaft.position = aim_direction * _hand_distance(time)
	queue_redraw()


func _contact_corners(time: float, origin: Vector2) -> PackedVector2Array:
	var base: Vector2 = origin + aim_direction * (_hand_distance(time) + _spear.grip_inset)
	var tip: Vector2 = origin + _tip(time)
	var side: Vector2 = aim_direction.orthogonal() * _spear.hit_width * 0.5
	return PackedVector2Array([base - side, tip - side, tip + side, base + side])


func _sweep(from_time: float, to_time: float, from_origin: Vector2, to_origin: Vector2) -> void:
	# Eased extension plus wielder movement can bend the tip's world-space path.
	var duration: float = definition.active_seconds / float(_spear.thrust_count) * EXTEND_RATIO
	var steps: int = maxi(1, ceili((to_time - from_time) / duration * SWEEP_SAMPLES))
	for index: int in steps:
		var t0: float = float(index) / steps
		var t1: float = float(index + 1) / steps
		var points: PackedVector2Array = _contact_corners(lerpf(from_time, to_time, t0), from_origin.lerp(to_origin, t0) - global_position)
		points.append_array(_contact_corners(lerpf(from_time, to_time, t1), from_origin.lerp(to_origin, t1) - global_position))
		_shape.points = Geometry2D.convex_hull(points)
		_query.transform = Transform2D(0.0, global_position)
		_query_hurtboxes(_query)


func _draw() -> void:
	if _spear == null or _visual_time < definition.windup_seconds or _visual_time >= definition.windup_seconds + definition.active_seconds:
		return
	var duration: float = definition.active_seconds / float(_spear.thrust_count)
	var phase: float = fposmod(_visual_time - definition.windup_seconds, duration) / duration
	var extension: float = clampf(phase / EXTEND_RATIO, 0.0, 1.0)
	var color: Color = _spear.trail_color
	color.a *= 1.0 - smoothstep(EXTEND_RATIO, 1.0, phase)
	var start: Vector2 = aim_direction * (_spear.hand_distance - _spear.pullback_distance + _spear.shaft_length)
	var end: Vector2 = start.lerp(aim_direction * (_spear.hand_distance + _spear.thrust_distance + _spear.shaft_length), extension)
	draw_line(start, end, color, 2.0)
	for side: float in [-1.0, 1.0]:
		var offset: Vector2 = aim_direction.orthogonal() * side * (_spear.hit_width * 0.5 + 2.0)
		draw_line(start.lerp(end, 0.3) + offset, end + offset, color, 1.0)
