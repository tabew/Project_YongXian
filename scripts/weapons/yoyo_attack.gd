class_name YoyoAttack
extends WeaponAttack

## 泰拉瑞亚式溜溜球：球停在指针位置，指针超出绳长时贴在绳长边界上；按住左键维持，
## 松手立刻收回。整段飞行都做判定，同一个目标按 hit_interval 重复受伤；
## 球实际经过哪里就判定哪里。

enum Phase { FOLLOW, RETURN }

const CIRCLE_POINTS: int = 12
const MAX_SWEEP_SAMPLES: int = 12
const TRAIL_SAMPLES: int = 6

@onready var ball: Sprite2D = $Ball

var _yoyo: YoyoWeaponDefinition
var _direction: Vector2 = Vector2.RIGHT
var _distance: float = 0.0
var _phase: Phase = Phase.FOLLOW
var _spin_radians: float = 0.0
var _saw_press: bool = false
var _landed: bool = false
var _previous_origin: Vector2
var _previous_offset: Vector2
var _trail: Array[Vector2] = []
var _next_hit_times: Dictionary[int, float] = {}
var _shape: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
var _query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()


func accepts_definition(data: WeaponDefinition) -> bool:
	return data is YoyoWeaponDefinition


func _on_started() -> void:
	_yoyo = definition as YoyoWeaponDefinition
	_direction = aim_direction
	_distance = _yoyo.hand_distance
	_phase = Phase.FOLLOW
	_previous_origin = global_position
	_previous_offset = _direction * _distance
	_trail.clear()
	ball.texture = _yoyo.texture
	ball.scale = Vector2.ONE * (_yoyo.head_radius * 2.0 / maxf(_yoyo.texture.get_width(), 1.0))
	_query.shape = _shape
	_query.collision_mask = definition.hit_mask
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	_pose()


func _advance(previous: float, current: float) -> void:
	# 前摇里球收在手上，不判定；跨过前摇的那一帧只推进剩余的时间。
	var flight_delta: float = maxf(current - maxf(previous, definition.windup_seconds), 0.0)
	if flight_delta > 0.0:
		var from_position: Vector2 = _previous_origin + _previous_offset
		_advance_flight(flight_delta)
		_spin_radians = fmod(_spin_radians + deg_to_rad(_yoyo.spin_degrees_per_second) * flight_delta, TAU)
		_pose()
		_sweep_ball(from_position, global_position + _direction * _distance)
	_previous_origin = global_position
	_previous_offset = _direction * _distance
	if _landed:
		_landed = false
		_complete()


## 溜溜球按受击冷却重复命中，而不是一次攻击对同一个目标只结算一次。
func _try_hit(hurtbox: CombatHurtbox) -> void:
	if not hurtbox.can_receive_hit(wielder, wielder_team):
		return
	var target_id: int = hurtbox.receiver_id()
	var next_time: float = _next_hit_times.get(target_id, -INF)
	if next_time > elapsed:
		return
	_next_hit_times[target_id] = elapsed + _yoyo.hit_interval
	_land_hit(hurtbox)


func _advance_flight(delta: float) -> void:
	if _phase != Phase.RETURN and (_trigger_released() or _active_window_over()):
		_phase = Phase.RETURN
	var offset: Vector2 = _direction * _distance
	if _phase == Phase.FOLLOW:
		offset = offset.move_toward(_target_offset(), _yoyo.follow_speed * delta)
	else:
		offset = offset.move_toward(offset.normalized() * _yoyo.hand_distance, _yoyo.return_speed * delta)
		if offset.length() <= _yoyo.hand_distance + 0.01:
			_landed = true
	_distance = offset.length()
	if not offset.is_zero_approx():
		_direction = offset.normalized()


## 指针在攻击范围内就落在指针上，超出绳长则贴在边界。
func _target_offset() -> Vector2:
	var controller: WeaponController = get_parent() as WeaponController
	var aim: Vector2 = controller.aim_vector if controller != null else aim_direction
	return _yoyo.target_offset(aim)


## 没人按住时，球滞空到有效期结束就自己回来，AI 与测试因此也能直接 try_attack。
func _active_window_over() -> bool:
	return elapsed >= definition.windup_seconds + definition.active_seconds


## 只有收到过按下才响应松开，避免没有输入的攻击（AI、测试）被误判成“已松手”。
func _trigger_released() -> bool:
	if _trigger_held():
		_saw_press = true
		return false
	return _saw_press


func _trigger_held() -> bool:
	var controller: WeaponController = get_parent() as WeaponController
	return controller != null and controller.is_trigger_held()


func _pose() -> void:
	ball.position = _direction * _distance
	ball.rotation = _spin_radians
	_trail.push_front(ball.position)
	if _trail.size() > TRAIL_SAMPLES:
		_trail.resize(TRAIL_SAMPLES)
	queue_redraw()


## 用球的圆形采样覆盖两帧之间的路径，高攻速或低帧率下也不会穿过目标。
func _sweep_ball(from_position: Vector2, to_position: Vector2) -> void:
	var span: float = from_position.distance_to(to_position)
	var steps: int = clampi(ceili(span / maxf(_yoyo.head_radius, 0.5)), 1, MAX_SWEEP_SAMPLES)
	var points: PackedVector2Array = []
	for index: int in range(steps + 1):
		var center: Vector2 = from_position.lerp(to_position, float(index) / float(steps)) - global_position
		points.append_array(_circle_points(center))
	_shape.points = Geometry2D.convex_hull(points)
	_query.transform = Transform2D(0.0, global_position)
	_query_hurtboxes(_query)


func _circle_points(center: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for index: int in range(CIRCLE_POINTS):
		points.append(center + Vector2.from_angle(TAU * float(index) / float(CIRCLE_POINTS)) * _yoyo.head_radius)
	return points


func _draw() -> void:
	if _yoyo == null:
		return
	if _yoyo.string_width > 0.0:
		draw_line(_direction * _yoyo.hand_distance, _direction * _distance, _yoyo.string_color, _yoyo.string_width)
	var samples: int = _trail.size()
	for index: int in range(samples - 1):
		var color: Color = _yoyo.trail_color
		color.a *= 1.0 - float(index) / float(samples)
		draw_line(_trail[index + 1], _trail[index], color, _yoyo.head_radius * 0.8)
