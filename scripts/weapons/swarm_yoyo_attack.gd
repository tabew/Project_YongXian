class_name SwarmYoyoAttack
extends YoyoAttack

const STRIKE_SECONDS: float = 0.35
const BEE_STEP: float = 1.0 / 60.0

var _effect: SwarmYoyoDefinition
var _secondary: bool = false
var _next_bee: float = 0.0
var _bees: Array[Dictionary] = []
var _strikes: Array[Dictionary] = []
var _storms: Array[Dictionary] = []
var _next_storm: float = 0.0
var _flight_done: bool = false
var _bomb_released: bool = false


func accepts_definition(data: WeaponDefinition) -> bool:
	return data is SwarmYoyoDefinition


func _on_started() -> void:
	super._on_started()
	_effect = definition as SwarmYoyoDefinition
	hit_landed.connect(_on_ball_hit)
	var controller := get_parent() as WeaponController
	if controller != null:
		controller.weapon_changed.connect(_on_weapon_changed)


func _on_weapon_changed(_weapon: WeaponDefinition) -> void:
	cancel()


func _complete() -> void:
	if _flight_done:
		return
	_flight_done = true
	_running = false
	ball.hide()
	for child: Node in get_children():
		if child is OrbitBall:
			child.queue_free()
	finished.emit()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	if not _flight_done:
		super._physics_process(delta)
		return
	if not is_instance_valid(wielder):
		queue_free()
		return
	elapsed += delta
	_advance_bees(delta)
	_tick_storms()
	_expire_strikes()
	queue_redraw()
	if _bees.is_empty() and _storms.is_empty() and _strikes.is_empty() and elapsed >= maxf(_next_storm, _next_bee):
		queue_free()


func _bee_count() -> int:
	var count: int = 0
	for child: Node in get_parent().get_children():
		if child is SwarmYoyoAttack and not child.is_queued_for_deletion():
			var attack := child as SwarmYoyoAttack
			if attack.definition != null and attack.definition.id == definition.id:
				count += attack._bees.size()
	return count


func _storm_available() -> bool:
	var count: int = 0
	for child: Node in get_parent().get_children():
		if child is SwarmYoyoAttack and not child.is_queued_for_deletion():
			var attack := child as SwarmYoyoAttack
			if attack.definition != null and attack.definition.id == definition.id:
				if attack.elapsed < attack._next_storm:
					return false
				count += attack._storms.size()
	return _effect.ultimate != SwarmYoyoDefinition.Ultimate.BEACON or count < 2


func _bee_available() -> bool:
	if _bee_count() >= _effect.bee_limit:
		return false
	for child: Node in get_parent().get_children():
		if child is SwarmYoyoAttack and not child.is_queued_for_deletion():
			var attack := child as SwarmYoyoAttack
			if attack.definition != null and attack.definition.id == definition.id and attack.elapsed < attack._next_bee:
				return false
	return true


func _on_ball_hit(_hit: CombatHit, hurtbox: CombatHurtbox) -> void:
	# Secondary damage emits normal feedback without rolling another proc.
	if _secondary or not _running or _phase != Phase.FOLLOW:
		return
	if _effect.ultimate == SwarmYoyoDefinition.Ultimate.BOMB:
		return
	if _effect.effect == SwarmYoyoDefinition.Effect.THUNDER:
		if not _storm_available():
			return
	if _effect.effect == SwarmYoyoDefinition.Effect.HIVE:
		if not _bee_available():
			return
	if MapRng.shared(MapRng.Stream.COMBAT).randf() >= _effect.proc_chance:
		return
	if _effect.effect == SwarmYoyoDefinition.Effect.THUNDER:
		match _effect.ultimate:
			SwarmYoyoDefinition.Ultimate.CORE:
				_next_storm = elapsed + 2.0
				_storms.append({"position": hurtbox.global_position, "next": elapsed + 0.6, "remaining": 1})
			SwarmYoyoDefinition.Ultimate.BEACON:
				_storms.append({"position": hurtbox.global_position, "next": elapsed + 0.5, "remaining": 3})
			_:
				_strike(hurtbox.global_position)
	else:
		_next_bee = elapsed + _effect.bee_spawn_interval
		_spawn_bees(ball.global_position)


func _tick_storms() -> void:
	for index: int in range(_storms.size() - 1, -1, -1):
		var storm: Dictionary = _storms[index]
		while int(storm["remaining"]) > 0 and elapsed >= float(storm["next"]):
			_strike(storm["position"])
			storm["remaining"] = int(storm["remaining"]) - 1
			storm["next"] = float(storm["next"]) + 0.7
		if int(storm["remaining"]) == 0:
			_storms.remove_at(index)


func _expire_strikes() -> void:
	for index: int in range(_strikes.size() - 1, -1, -1):
		if elapsed >= float(_strikes[index]["until"]):
			_strikes.remove_at(index)


func _strike(origin: Vector2) -> void:
	_strikes.append({"position": origin, "until": elapsed + STRIKE_SECONDS})
	_secondary = true
	for target: CombatHurtbox in _targets_in_range(origin):
		if is_instance_valid(target) and target.can_receive_hit(wielder, wielder_team):
			_land_hit(target, _effect.secondary_damage_scale)
	_secondary = false


func _spawn_bees(origin: Vector2) -> void:
	var rotation_offset: float = MapRng.shared(MapRng.Stream.COMBAT).randf() * TAU
	var count: int = mini(_effect.bee_burst_count, maxi(_effect.bee_limit - _bee_count(), 0))
	for index: int in count:
		var direction: Vector2 = Vector2.from_angle(rotation_offset + TAU * float(index) / float(count))
		_bees.append({"position": origin, "velocity": direction * _effect.bee_speed, "age": 0.0, "next_bite": 0.0})


func _targets_in_range(origin: Vector2) -> Array[CombatHurtbox]:
	var shape := CircleShape2D.new()
	shape.radius = _effect.effect_range
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, origin)
	query.collision_mask = definition.hit_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var targets: Array[CombatHurtbox] = []
	var receivers: Dictionary[int, bool] = {}
	var excluded: Array[RID] = []
	while true:
		query.exclude = excluded
		var results: Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query, QUERY_BATCH)
		for result: Dictionary in results:
			excluded.append(result["rid"])
			var candidate: CombatHurtbox = result["collider"] as CombatHurtbox
			if candidate == null or not candidate.can_receive_hit(wielder, wielder_team):
				continue
			if receivers.has(candidate.receiver_id()):
				continue
			receivers[candidate.receiver_id()] = true
			targets.append(candidate)
		if results.size() < QUERY_BATCH:
			break
	return targets


func _nearest(origin: Vector2) -> CombatHurtbox:
	var nearest: CombatHurtbox = null
	var best: float = INF
	for candidate: CombatHurtbox in _targets_in_range(origin):
		var distance: float = origin.distance_squared_to(candidate.global_position)
		if distance < best:
			nearest = candidate
			best = distance
	return nearest


func _advance_bees(delta: float) -> void:
	_secondary = true
	for index: int in range(_bees.size() - 1, -1, -1):
		var bee: Dictionary = _bees[index]
		var remaining: float = minf(delta, maxf(_effect.bee_lifetime - float(bee["age"]), 0.0))
		var consumed: bool = false
		# Fixed substeps preserve scatter time and swept hits on long frames.
		while remaining > 0.00001:
			var step: float = minf(BEE_STEP, remaining)
			var age: float = bee["age"]
			var scattering: bool = age < _effect.bee_scatter_seconds - 0.00001
			if scattering:
				step = minf(step, _effect.bee_scatter_seconds - age)
			var origin: Vector2 = bee["position"]
			var velocity: Vector2 = bee["velocity"]
			var target: CombatHurtbox = null if scattering else _nearest(origin)
			if target != null:
				var desired: Vector2 = origin.direction_to(target.global_position) * _effect.bee_speed
				velocity = velocity.move_toward(desired, _effect.bee_speed * 6.0 * step)
			var destination: Vector2 = origin + velocity * step
			bee["position"] = destination
			bee["velocity"] = velocity
			bee["age"] = age + step
			remaining -= step
			if target != null:
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(target.global_position, origin, destination)
				if closest.distance_to(target.global_position) <= 5.0 and float(bee["age"]) >= float(bee["next_bite"]):
					_land_hit(target, _effect.secondary_damage_scale)
					if _effect.ultimate == SwarmYoyoDefinition.Ultimate.MIGRATION:
						bee["next_bite"] = float(bee["age"]) + 0.4
					else:
						consumed = true
						break
		if consumed or float(bee["age"]) >= _effect.bee_lifetime - 0.00001:
			_bees.remove_at(index)
	_secondary = false


func _advance(previous: float, current: float) -> void:
	var delta: float = maxf(minf(current, definition.attack_duration()) - previous, 0.0)
	var released: bool = _trigger_released()
	if released or _active_window_over():
		if _effect.ultimate not in [SwarmYoyoDefinition.Ultimate.BOMB, SwarmYoyoDefinition.Ultimate.MIGRATION]:
			_bees.clear()
	# Existing bees advance before ball hits can create a new burst.
	_advance_bees(delta)
	if released and not _bomb_released and _effect.ultimate == SwarmYoyoDefinition.Ultimate.BOMB:
		_bomb_released = true
		if previous - definition.windup_seconds >= 1.0:
			_spawn_bees(ball.global_position)
	_expire_strikes()
	_tick_storms()
	super._advance(previous, current)
	queue_redraw()


func _draw() -> void:
	if not _flight_done:
		super._draw()
	if _effect == null:
		return
	for storm: Dictionary in _storms:
		var center: Vector2 = to_local(storm["position"])
		draw_circle(center, _effect.effect_range, Color(0.3, 0.6, 1.0, 0.12))
		draw_arc(center, _effect.effect_range, 0.0, TAU, 64, Color(0.7, 0.85, 1.0, 0.8), 1.0)
	if not _flight_done and _effect.ultimate == SwarmYoyoDefinition.Ultimate.BOMB:
		var charge: float = clampf((elapsed - definition.windup_seconds), 0.0, 1.0)
		draw_arc(ball.position, _yoyo.head_radius + 3.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 32, Color(1.0, 0.8, 0.25), 1.5)
	for strike: Dictionary in _strikes:
		var center: Vector2 = to_local(strike["position"])
		var fade: float = clampf((float(strike["until"]) - elapsed) / STRIKE_SECONDS, 0.0, 1.0)
		# The full disk and fixed outer ring share the exact physics-query radius.
		draw_circle(center, _effect.effect_range, Color(0.25, 0.65, 1.0, 0.24 * fade))
		draw_arc(center, _effect.effect_range, 0.0, TAU, 64, Color(0.6, 0.9, 1.0, fade), 1.5)
		var points := PackedVector2Array([
			center + Vector2(-10, -150), center + Vector2(6, -112),
			center + Vector2(-9, -80), center + Vector2(8, -48),
			center + Vector2(-4, -23), center])
		draw_polyline(points, Color(0.2, 0.55, 1.0, 0.45 * fade), 7.0)
		draw_polyline(points, Color(0.85, 1.0, 1.0, fade), 2.0)
		draw_circle(center, 5.0, Color(0.9, 1.0, 1.0, fade))
	for bee: Dictionary in _bees:
		var center: Vector2 = to_local(bee["position"])
		var velocity: Vector2 = bee["velocity"]
		var flutter: float = sin(float(bee["age"]) * 55.0) * 1.5
		draw_line(center - velocity.normalized() * 8.0, center, Color(1.0, 0.75, 0.25, 0.45), 1.0)
		draw_set_transform(center, velocity.angle())
		draw_texture_rect(_effect.bee_texture, Rect2(Vector2(-6, -6 + flutter), Vector2(12, 12)), false)
		draw_set_transform(Vector2.ZERO)
