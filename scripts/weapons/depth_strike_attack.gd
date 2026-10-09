class_name DepthStrikeAttack
extends WeaponAttack

const SWEEP_SAMPLES: int = 32

@onready var shaft: Polygon2D = $Shaft

var _staff: DepthStrikeWeaponDefinition
var _previous_origin: Vector2
var _shape: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
var _query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
var _texture_scale: float = 1.0
var _visual_time: float = 0.0


func accepts_definition(data: WeaponDefinition) -> bool:
	return data is DepthStrikeWeaponDefinition


func _on_started() -> void:
	_staff = definition as DepthStrikeWeaponDefinition
	_previous_origin = global_position
	_texture_scale = _staff.shaft_length / (_staff.texture.get_width() - _staff.texture_grip.x)
	shaft.texture = _staff.texture
	var size: Vector2 = _staff.texture.get_size()
	shaft.uv = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])
	_query.shape = _shape
	_query.collision_mask = definition.hit_mask
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	_set_pose(0.0)


func _advance(previous: float, current: float) -> void:
	var active_start: float = definition.windup_seconds
	var active_end: float = active_start + definition.active_seconds
	if current >= active_start and previous < active_end:
		var from_time: float = maxf(previous, active_start)
		var to_time: float = minf(current, active_end)
		var frame_time: float = maxf(current - previous, 0.000001)
		var from_origin: Vector2 = _previous_origin.lerp(global_position, (from_time - previous) / frame_time)
		var to_origin: Vector2 = _previous_origin.lerp(global_position, (to_time - previous) / frame_time)
		_sweep(from_time, to_time, from_origin, to_origin)
	_previous_origin = global_position
	_set_pose(minf(current, definition.attack_duration()))


func _progress(time: float) -> float:
	return clampf((time - definition.windup_seconds) / definition.active_seconds, 0.0, 1.0)


func _pitch(time: float) -> float:
	var start: float = _staff.near_pitch_degrees if _staff.reverse_strike else _staff.far_pitch_degrees
	var end: float = _staff.far_pitch_degrees if _staff.reverse_strike else _staff.near_pitch_degrees
	if time < definition.windup_seconds:
		return deg_to_rad(lerpf(20.0, start, smoothstep(0.0, definition.windup_seconds, time)))
	var active_end: float = definition.windup_seconds + definition.active_seconds
	if time > active_end:
		var recovery: float = (time - active_end) / maxf(definition.recovery_seconds, 0.000001)
		return deg_to_rad(lerpf(end, 20.0, smoothstep(0.0, 1.0, recovery)))
	return deg_to_rad(lerpf(start, end, smoothstep(0.0, 1.0, _progress(time))))


func _hand_distance(time: float) -> float:
	return _staff.hand_distance + sin(_progress(time) * PI) * _staff.forward_travel


func _axis(time: float) -> Vector2:
	var direction: float = -1.0 if aim_direction.x < 0.0 else 1.0
	var angle: float = (smoothstep(0.0, 1.0, _progress(time)) - 0.5) * deg_to_rad(_staff.arc_degrees) * direction
	return aim_direction.rotated(angle)


## Project a pitched rod into 2D. Visual geometry and contact reach share this transform.
func _project(distance: float, across: float, time: float) -> Vector2:
	var pitch: float = _pitch(time)
	var perspective: float = 1.0 + distance / _staff.shaft_length * sin(pitch) * _staff.perspective_strength
	var along: float = _hand_distance(time) + distance * cos(pitch) * perspective
	var axis: Vector2 = _axis(time)
	return axis * along + axis.orthogonal() * across * perspective


func _tip(time: float) -> Vector2:
	return _project(_staff.shaft_length, 0.0, time)


func _set_pose(time: float) -> void:
	_visual_time = time
	var points: PackedVector2Array = []
	for uv: Vector2 in shaft.uv:
		var local: Vector2 = (uv - _staff.texture_grip) * _texture_scale
		points.append(_project(local.x, local.y, time))
	shaft.polygon = points
	var near_amount: float = clampf(inverse_lerp(deg_to_rad(_staff.far_pitch_degrees), deg_to_rad(_staff.near_pitch_degrees), _pitch(time)), 0.0, 1.0)
	var brightness: float = lerpf(0.68, 1.0, near_amount)
	shaft.color = Color(brightness, brightness, brightness, 1.0)
	queue_redraw()


func _contact_corners(time: float, origin: Vector2) -> PackedVector2Array:
	var axis: Vector2 = _axis(time)
	var tip: Vector2 = origin + _tip(time)
	var tip_distance: float = _tip(time).dot(axis)
	var base_distance: float = minf(_hand_distance(time) + _staff.grip_inset, tip_distance - 0.01)
	var base: Vector2 = origin + axis * base_distance
	var side: Vector2 = axis.orthogonal() * _staff.hit_width * 0.5
	return PackedVector2Array([base - side, tip - side, tip + side, base + side])


func _sweep(from_time: float, to_time: float, from_origin: Vector2, to_origin: Vector2) -> void:
	# Sample the middle of the depth arc too: its maximum reach is not at either endpoint.
	var steps: int = maxi(1, ceili((to_time - from_time) / definition.active_seconds * SWEEP_SAMPLES))
	for index: int in range(steps):
		var t0: float = float(index) / steps
		var t1: float = float(index + 1) / steps
		var points: PackedVector2Array = _contact_corners(lerpf(from_time, to_time, t0), from_origin.lerp(to_origin, t0) - global_position)
		points.append_array(_contact_corners(lerpf(from_time, to_time, t1), from_origin.lerp(to_origin, t1) - global_position))
		_shape.points = Geometry2D.convex_hull(points)
		_query.transform = Transform2D(0.0, global_position)
		_query_hurtboxes(_query)


func _draw() -> void:
	if _staff == null:
		return
	var active_end: float = definition.windup_seconds + definition.active_seconds
	if _visual_time < definition.windup_seconds:
		return
	var fade: float = 1.0 - clampf((_visual_time - active_end) / maxf(definition.recovery_seconds * 0.5, 0.000001), 0.0, 1.0)
	var latest: float = minf(_visual_time, active_end)
	for index: int in range(8):
		var current: float = maxf(definition.windup_seconds, latest - definition.active_seconds * float(index) * 0.05)
		var previous: float = maxf(definition.windup_seconds, current - definition.active_seconds * 0.05)
		var color: Color = _staff.trail_color
		color.a *= (1.0 - float(index) / 8.0) * fade
		draw_line(_tip(previous), _tip(current), color, 1.5)
