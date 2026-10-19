class_name FinalBoss
extends BaseMonster

signal phase_changed(new_phase: int)
signal attack_started(kind: StringName)
signal rage_changed(current: int)

const BOSS_NAME: String = "贝&%*#彩？？？"
const PHASE_COUNT: int = 3
const PHASE_HEALTH: float = 3000.0
const TRANSITION_SECONDS: float = 4.0
const NORMAL_INTERVAL: float = 5.0
const PHASE_COLORS: Array[Color] = [Color("b75072"), Color("8586c2"), Color("d17d46")]
const TILE: float = float(WorldGenerator.TILE_SIZE)
const SLAM_WARNING_SECONDS: float = 3.0
const EYE_SECONDS: float = 10.0
const CHARGE_SECONDS: float = 15.0
const ENGAGE_RADIUS: float = 9.0 * TILE
const SLAM_SPREAD_TILES: int = 7

enum AttackState { WAIT, SOULS, LASSO, SLAM, EYES, ENRAGED }

var phase: int = 1
var attack_state: AttackState = AttackState.WAIT
var rage: int = 0
var _engaged: bool = false
var _transition_timer: SceneTreeTimer = null
var _normal_wait: float = NORMAL_INTERVAL
var _attack_remaining: float = 0.0
var _normal_casts: int = 0
var _souls_pending: int = 0
var _missiles: Array[BossSoulMissile] = []
var _lasso: BossLasso = null
var _slam_centers: Array[Vector2] = []
var _tentacle_target: Vector2 = Vector2.ZERO
var _tentacle_warning: float = -1.0
var _throw_remaining: float = -1.0
var _throw_origin: Vector2 = Vector2.ZERO
var _throw_destination: Vector2 = Vector2.ZERO
var _laser_tick: float = 1.0
var _dot_last_rage_ms: int = -1000000
var _flashes: Array[Dictionary] = []
var _rng: RandomNumberGenerator = null

@onready var boss_hud: BossHud = $BossOverlay/BossHud


func _ready() -> void:
	super._ready()
	var health := get_node("Health") as HealthComponent
	health.depleted.connect(_on_health_depleted)
	health.damaged.connect(_on_boss_damaged)
	health.max_health = PHASE_HEALTH
	health.reset()
	boss_hud.bind_health(health, BOSS_NAME)
	_rng = MapRng.shared(MapRng.Stream.COMBAT)
	_refresh_phase_display()


func is_distance_sleep_blocked() -> bool:
	return true


func configure_target(target_player: PlayerCharacter, generator: WorldGenerator) -> void:
	super.configure_target(target_player, generator)
	# This fixed encounter owns its attacks and never needs patrol, chase or A* requests.
	brain = null
	navigation_speed = 0.0


## The boss keeps exactly 3000 health per phase, even on later room entries.
func apply_difficulty(entry: int) -> void:
	if _difficulty_applied:
		return
	_difficulty_applied = true
	difficulty_entry = maxi(entry, 1)
	difficulty_multiplier = 1.0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_tick_flashes(delta)
	if _death_committed or not is_instance_valid(player) or player.health <= 0.0:
		return
	if not _engaged:
		if player.global_position.distance_squared_to(global_position) > ENGAGE_RADIUS * ENGAGE_RADIUS:
			return
		_engaged = true
	var health := get_node("Health") as HealthComponent
	if health.invulnerable:
		return
	if phase == 2:
		_tick_tentacle(delta)
	match attack_state:
		AttackState.WAIT:
			_normal_wait -= delta
			if _normal_wait <= 0.0:
				_start_normal_attack()
		AttackState.SLAM:
			_attack_remaining -= delta
			if _attack_remaining <= 0.0:
				_resolve_slams()
				_finish_normal_attack()
			queue_redraw()
		AttackState.EYES:
			_attack_remaining -= delta
			_laser_tick -= delta
			while _laser_tick <= 0.0 and _attack_remaining > -1.0:
				_laser_tick += 1.0
				if player.health > 0.0:
					player.take_damage(1.0, self)
			if _attack_remaining <= 0.0:
				_finish_normal_attack()
			queue_redraw()
		AttackState.ENRAGED:
			_attack_remaining -= delta
			if _attack_remaining <= 0.0:
				_complete_self_destruct()
			else:
				_refresh_rage_display()
			queue_redraw()


func _start_normal_attack() -> void:
	if not is_instance_valid(player) or player.health <= 0.0:
		return
	match phase:
		1:
			attack_state = AttackState.SOULS
			var count: int = _rng.randi_range(7, 8)
			_souls_pending = count
			for index: int in count:
				var angle: float = TAU * float(index) / float(count)
				var direction := Vector2.RIGHT.rotated(angle)
				var missile := BossSoulMissile.new()
				add_child(missile)
				missile.launch(self, player, global_position + direction * 26.0, direction)
				missile.resolved.connect(_on_soul_resolved)
				missile.expired.connect(soul_explosion)
				_missiles.append(missile)
			attack_started.emit(&"souls")
		2:
			attack_state = AttackState.SLAM
			_attack_remaining = SLAM_WARNING_SECONDS
			_pick_slam_centers()
			if _rng.randf() < 0.3:
				_tentacle_target = player.global_position
				_tentacle_warning = 0.4
			attack_started.emit(&"slam")
			queue_redraw()
		3:
			attack_state = AttackState.EYES
			_attack_remaining = EYE_SECONDS
			_laser_tick = 1.0
			attack_started.emit(&"eyes")
			queue_redraw()


func _on_soul_resolved() -> void:
	if attack_state != AttackState.SOULS:
		return
	_souls_pending -= 1
	if _souls_pending <= 0:
		_missiles.clear()
		_finish_normal_attack()


func soul_explosion(at: Vector2) -> void:
	if phase != 1 or attack_state != AttackState.SOULS:
		return
	_hit_player_in_circle(at, 4.0 * TILE, 15.0)
	_add_flash(at, 4.0 * TILE, Color(0.88, 0.37, 0.65, 0.8))


func _finish_normal_attack() -> void:
	attack_state = AttackState.WAIT
	_normal_wait = NORMAL_INTERVAL
	if phase == 1:
		_normal_casts += 1
		if _normal_casts >= 3:
			_normal_casts = 0
			_start_lasso()
	elif phase == 2:
		slam_centers_clear()


func _start_lasso() -> void:
	if not is_instance_valid(player) or player.health <= 0.0:
		return
	attack_state = AttackState.LASSO
	_lasso = BossLasso.new()
	add_child(_lasso)
	_lasso.launch(self, player)
	_lasso.resolved.connect(_on_lasso_resolved)
	attack_started.emit(&"lasso")


func _on_lasso_resolved(reached_boss: bool) -> void:
	if attack_state != AttackState.LASSO:
		return
	_lasso = null
	if reached_boss:
		_hit_player_in_circle(global_position, 6.0 * TILE, 50.0)
		_add_flash(global_position, 6.0 * TILE, Color(1.0, 0.3, 0.31, 0.85))
	attack_state = AttackState.WAIT
	_normal_wait = NORMAL_INTERVAL


func _pick_slam_centers() -> void:
	_slam_centers.clear()
	var spec: MapSpec = player.active_map
	if world_generator != null and spec != null:
		var origin: Vector2i = WorldGenerator.world_to_tile(player.global_position)
		var selected: Dictionary = {}
		for attempt: int in 160:
			if _slam_centers.size() >= 5:
				break
			var tile: Vector2i = origin + Vector2i(
				_rng.randi_range(-SLAM_SPREAD_TILES, SLAM_SPREAD_TILES),
				_rng.randi_range(-SLAM_SPREAD_TILES, SLAM_SPREAD_TILES)
			)
			if not spec.contains_local(tile.x - spec.origin.x, tile.y - spec.origin.y):
				continue
			if not world_generator.is_walkable(tile) or selected.has(tile):
				continue
			selected[tile] = true
			_slam_centers.append(WorldGenerator.tile_to_world(tile))
	if _slam_centers.is_empty():
		_slam_centers.append(player.global_position)
	while _slam_centers.size() < 5:
		_slam_centers.append(_slam_centers[_rng.randi_range(0, _slam_centers.size() - 1)])


func _resolve_slams() -> void:
	for center: Vector2 in _slam_centers:
		_hit_player_in_circle(center, 3.0 * TILE, 30.0)
		_add_flash(center, 3.0 * TILE, Color(1.0, 0.25, 0.18, 0.9))


func slam_centers_clear() -> void:
	_slam_centers.clear()
	queue_redraw()


func _tick_tentacle(delta: float) -> void:
	if _tentacle_warning >= 0.0:
		_tentacle_warning -= delta
		if _tentacle_warning <= 0.0:
			_tentacle_warning = -1.0
			if player.health > 0.0 and player.global_position.distance_to(_tentacle_target) <= TILE * 1.5:
				_throw_origin = player.global_position
				_throw_destination = _random_throw_destination()
				_throw_remaining = 0.65
				player.set_boss_captured(true)
		queue_redraw()
	if _throw_remaining < 0.0:
		return
	_throw_remaining = maxf(_throw_remaining - delta, 0.0)
	var progress: float = 1.0 - _throw_remaining / 0.65
	player.global_position = _throw_origin.lerp(_throw_destination, progress)
	player.sprite.position.y = -24.0 * sin(progress * PI)
	queue_redraw()
	if _throw_remaining <= 0.0:
		_throw_remaining = -1.0
		player.sprite.position.y = 0.0
		player.set_boss_captured(false)
		player.take_damage(20.0, self)
		if player.health > 0.0:
			player.apply_boss_stun(2.0)


func _random_throw_destination() -> Vector2:
	if world_generator == null or player.active_map == null:
		return player.global_position
	var choices: Array[Vector2i] = MapContent.pick_tiles(world_generator, player.active_map.node_id, 12, _rng)
	if choices.is_empty():
		return player.global_position
	var tile: Vector2i = choices[_rng.randi_range(0, choices.size() - 1)]
	return WorldGenerator.tile_to_world(tile)


func _hit_player_in_circle(center: Vector2, radius: float, damage: float) -> void:
	if is_instance_valid(player) and player.health > 0.0 and player.global_position.distance_to(center) <= radius:
		player.take_damage(damage, self)


func _on_boss_damaged(hit: CombatHit, _actual_damage: float) -> void:
	if phase != 3 or _death_committed or not is_instance_valid(player):
		return
	# Alchemy currently omits its applier, but every anonymous attack in this
	# room is player-initiated; only explicitly tagged DOT is rate-limited.
	var periodic: bool = hit.weapon_id == &"damage_over_time"
	if hit.source != player and hit.source != null:
		return
	if periodic:
		var now: int = Time.get_ticks_msec()
		if now - _dot_last_rage_ms < 1000:
			return
		_dot_last_rage_ms = now
	if attack_state == AttackState.ENRAGED:
		rage = maxi(rage - 25, 500)
		if rage <= 500:
			_exit_rage()
	else:
		rage = mini(rage + 25, 1000)
		if rage >= 1000:
			_enter_rage()
	_refresh_rage_display()
	rage_changed.emit(rage)


func _enter_rage() -> void:
	_cancel_attack()
	attack_state = AttackState.ENRAGED
	_attack_remaining = CHARGE_SECONDS
	queue_redraw()


func _exit_rage() -> void:
	attack_state = AttackState.WAIT
	_normal_wait = NORMAL_INTERVAL
	_attack_remaining = 0.0
	_refresh_rage_display()
	queue_redraw()


func _complete_self_destruct() -> void:
	_hit_player_in_circle(player.global_position, INF, 80.0)
	_add_flash(global_position, 6.0 * TILE, Color(1.0, 0.66, 0.23, 0.95))
	var hit := CombatHit.new()
	hit.source = self
	hit.damage = 400.0
	hit.position = global_position
	(get_node("Health") as HealthComponent).receive_hit(hit)
	if _death_committed:
		return
	rage = 500
	rage_changed.emit(rage)
	_refresh_rage_display()
	_exit_rage()


func _cancel_attack() -> void:
	attack_state = AttackState.WAIT
	_souls_pending = 0
	for missile: BossSoulMissile in _missiles:
		if is_instance_valid(missile):
			missile.queue_free()
	_missiles.clear()
	if is_instance_valid(_lasso):
		_lasso.abort()
	_lasso = null
	slam_centers_clear()
	_tentacle_warning = -1.0
	_throw_remaining = -1.0
	if is_instance_valid(player):
		player.set_boss_captured(false)
		player.sprite.position.y = 0.0
	queue_redraw()


func _on_health_depleted(_hit: CombatHit) -> void:
	if phase >= PHASE_COUNT:
		return
	_cancel_attack()
	phase += 1
	_normal_casts = 0
	_normal_wait = NORMAL_INTERVAL
	if phase == 3:
		rage = 500
		rage_changed.emit(rage)
	var health := get_node("Health") as HealthComponent
	health.invulnerable = true
	health.max_health = PHASE_HEALTH
	health.reset()
	_refresh_phase_display()
	phase_changed.emit(phase)
	_transition_timer = get_tree().create_timer(TRANSITION_SECONDS, false)
	_transition_timer.timeout.connect(_end_transition)


func _end_transition() -> void:
	_transition_timer = null
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var health := get_node("Health") as HealthComponent
	if health.is_alive():
		health.invulnerable = false


func _refresh_phase_display() -> void:
	(get_node("Visual/Placeholder") as Polygon2D).color = PHASE_COLORS[phase - 1]
	boss_hud.set_phase(phase, PHASE_COUNT, PHASE_COLORS[phase - 1])
	_refresh_rage_display()


func _refresh_rage_display() -> void:
	boss_hud.set_rage(phase == 3, rage, attack_state == AttackState.ENRAGED, _attack_remaining)


func _add_flash(at: Vector2, radius: float, tint: Color) -> void:
	_flashes.append({"position": at, "radius": radius, "color": tint, "remaining": 0.32})
	queue_redraw()


func _tick_flashes(delta: float) -> void:
	if _flashes.is_empty():
		return
	for flash: Dictionary in _flashes.duplicate():
		flash["remaining"] = float(flash["remaining"]) - delta
		if float(flash["remaining"]) <= 0.0:
			_flashes.erase(flash)
	queue_redraw()


func _draw() -> void:
	for flash: Dictionary in _flashes:
		var fade: float = clampf(float(flash["remaining"]) / 0.32, 0.0, 1.0)
		var color: Color = flash["color"]
		color.a *= fade
		var center: Vector2 = to_local(flash["position"])
		draw_circle(center, float(flash["radius"]), Color(color.r, color.g, color.b, color.a * 0.22))
		draw_arc(center, float(flash["radius"]), 0.0, TAU, 64, color, 3.0)
	if attack_state == AttackState.SLAM:
		var strength: float = clampf(1.0 - _attack_remaining / SLAM_WARNING_SECONDS, 0.0, 1.0)
		for center: Vector2 in _slam_centers:
			var local: Vector2 = to_local(center)
			draw_circle(local, 3.0 * TILE, Color(0.95, 0.12, 0.13, 0.15 + 0.29 * strength))
			draw_arc(local, 3.0 * TILE, 0.0, TAU, 48, Color(1.0, 0.24, 0.15, 0.62 + 0.38 * strength), 3.0)
			var soul: Vector2 = local + Vector2(0.0, -96.0 * (1.0 - strength))
			var soul_radius: float = 16.0 + 32.0 * strength
			draw_circle(soul, soul_radius, Color(0.77, 0.88, 1.0, 0.29 + 0.30 * strength))
			draw_arc(soul, soul_radius, 0.0, TAU, 40, Color(0.85, 0.95, 1.0, 0.7), 2.0)
			draw_circle(soul + Vector2(-10.0, -4.0), 3.0, Color(0.28, 0.12, 0.35, 0.8))
			draw_circle(soul + Vector2(10.0, -4.0), 3.0, Color(0.28, 0.12, 0.35, 0.8))
	if _tentacle_warning >= 0.0:
		draw_line(Vector2.ZERO, to_local(_tentacle_target), Color(0.95, 0.32, 0.56, 0.85), 4.0)
		draw_circle(to_local(_tentacle_target), 16.0, Color(0.94, 0.29, 0.51, 0.65))
	if _throw_remaining >= 0.0 and is_instance_valid(player):
		var grabbed: Vector2 = to_local(player.global_position) + Vector2(0.0, player.sprite.position.y)
		draw_line(Vector2.ZERO, grabbed, Color(0.46, 0.14, 0.38, 0.82), 6.0)
		draw_line(Vector2.ZERO, grabbed, Color(0.89, 0.46, 0.66, 0.9), 2.0)
		draw_circle(grabbed, 9.0, Color(0.82, 0.29, 0.52, 0.8))
	if attack_state == AttackState.EYES and is_instance_valid(player):
		var target: Vector2 = to_local(player.global_position)
		draw_rect(Rect2(-128.0, -163.0, 256.0, 102.0), Color(0.11, 0.08, 0.17, 0.65))
		for index: int in 20:
			var eye := Vector2(-104.0 + float(index % 5) * 52.0, -146.0 + float(index / 5) * 20.0)
			var gaze: Vector2 = (target - eye).normalized()
			draw_line(eye, target, Color(1.0, 0.31, 0.37, 0.62), 2.0)
			draw_circle(eye, 6.0, Color(0.92, 0.83, 0.78, 0.98))
			draw_circle(eye + gaze * 2.0, 2.7, Color(0.49, 0.11, 0.24, 1.0))
		draw_arc(target, 13.0, 0.0, TAU, 24, Color(1.0, 0.41, 0.37, 0.95), 2.0)
	if attack_state == AttackState.ENRAGED:
		var fill: float = 1.0 - _attack_remaining / CHARGE_SECONDS
		draw_arc(Vector2.ZERO, 70.0, -PI * 0.5, -PI * 0.5 + TAU * fill, 60, Color(1.0, 0.6, 0.21, 0.95), 4.0)


## Debug kills respect the phase transition and its invulnerability window.
func kill() -> void:
	if _death_committed:
		return
	var health := get_node("Health") as HealthComponent
	if health.invulnerable:
		return
	if phase < PHASE_COUNT and health.is_alive():
		var hit := CombatHit.new()
		hit.source = player
		hit.damage = health.current_health + health.defense
		hit.position = global_position
		health.receive_hit(hit)
		return
	_cancel_attack()
	super.kill()
