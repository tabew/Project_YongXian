class_name GiveMonster
extends BaseMonster

## 临时名“给”：只在热带雨林刷新、可跨群系活动的猿猴型怪物。

signal health_changed(current: int, maximum: int)
signal defeated

const TILE_SIZE: float = float(WorldGenerator.TILE_SIZE)
const AGGRO_RANGE: float = TILE_SIZE * 10.0
## 已经发现玩家后，绕墙期间超过该距离才彻底放弃追踪。
const PURSUIT_LOST_RANGE: float = TILE_SIZE * 16.0
const LEAP_MAX_RANGE: float = TILE_SIZE * 6.0
const RANGED_MIN_RANGE: float = TILE_SIZE * 6.0
const RANGED_MAX_RANGE: float = TILE_SIZE * 10.0
const STONE_PICKUP_RANGE: float = TILE_SIZE
const MAX_HEALTH: int = 100
const DAMAGE: int = 1
const ATTACK_COOLDOWN: float = 1.0
const FAILED_ATTACK_RETRY: float = 0.3
const LEAP_DURATION: float = 0.42
const LEAP_HEIGHT: float = 24.0
const MELEE_HIT_RANGE: float = TILE_SIZE * 2.0

var spawn_chunk: Vector2i = Vector2i.ZERO
var health: int = MAX_HEALTH

var _is_dead: bool = false
var _attack_cooldown: float = 0.0
var _is_pathing_around_obstacle: bool = false
var _has_attack_intent: bool = false
var _is_leaping: bool = false
var _leap_elapsed: float = 0.0
var _leap_start: Vector2 = Vector2.ZERO
var _leap_target: Vector2 = Vector2.ZERO
var _visual_height: float = 0.0


@onready var combat_health: HealthComponent = $Health


func _ready() -> void:
	super._ready()
	combat_health.health_changed.connect(_on_combat_health_changed)
	combat_health.died.connect(_on_combat_health_died)
	health = roundi(combat_health.current_health)


func configure(
	target_player: PlayerCharacter,
	generator: WorldGenerator,
	chunk_coords: Vector2i
) -> void:
	configure_target(target_player, generator)
	spawn_chunk = chunk_coords


func take_damage(amount: int) -> void:
	if amount <= 0 or _is_dead or not combat_health.is_alive():
		return
	var hit := CombatHit.new()
	hit.source = self
	hit.damage = float(amount)
	hit.position = global_position
	combat_health.receive_hit(hit)


func kill() -> void:
	if _is_dead:
		return
	if combat_health.is_alive():
		var hit := CombatHit.new()
		hit.source = self
		hit.damage = combat_health.current_health
		hit.position = global_position
		combat_health.receive_hit(hit)
		return
	_finalize_death()


func _on_combat_health_changed(current: float, maximum: float) -> void:
	health = roundi(current)
	health_changed.emit(health, roundi(maximum))


func _on_combat_health_died(_hit: CombatHit) -> void:
	_finalize_death()


func _finalize_death() -> void:
	if _is_dead:
		return
	_is_dead = true
	health = 0
	defeated.emit()
	super.kill()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if not is_instance_valid(player) or world_generator == null:
		return
	if player.health <= 0:
		_set_attack_intent(false)
		return

	if _is_leaping:
		_update_leap(delta)
		return

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	var distance: float = global_position.distance_to(player.global_position)
	var newly_sensed: bool = distance <= AGGRO_RANGE
	if not newly_sensed and (
		not _is_pathing_around_obstacle or distance > PURSUIT_LOST_RANGE
	):
		_is_pathing_around_obstacle = false
		_set_attack_intent(false)
		stop_navigation()
		return

	var has_clear_line: bool = has_clear_line_to_player()
	if not has_clear_line:
		_is_pathing_around_obstacle = true
		_set_attack_intent(false)
		navigate_toward_player(delta)
		return

	if _is_pathing_around_obstacle and not newly_sensed:
		_set_attack_intent(false)
		navigate_toward_player(delta)
		return

	_is_pathing_around_obstacle = false
	stop_navigation()
	_set_attack_intent(newly_sensed)
	if not _has_attack_intent or _attack_cooldown > 0.0:
		return

	if distance >= RANGED_MIN_RANGE and distance <= RANGED_MAX_RANGE:
		if not _try_throw_stone():
			_set_attack_intent(false)
	elif distance < LEAP_MAX_RANGE:
		_start_leap()


func _start_leap() -> void:
	var direction: Vector2 = global_position.direction_to(player.global_position)
	if direction == Vector2.ZERO:
		return
	var target: Vector2 = player.global_position - direction * TILE_SIZE
	var target_tile: Vector2i = WorldGenerator.world_to_tile(target)
	if not world_generator.is_walkable(target_tile):
		_attack_cooldown = FAILED_ATTACK_RETRY
		return
	if not has_clear_line_to_position(target):
		_attack_cooldown = FAILED_ATTACK_RETRY
		_is_pathing_around_obstacle = true
		return

	_is_leaping = true
	_leap_elapsed = 0.0
	_leap_start = global_position
	_leap_target = target
	_attack_cooldown = ATTACK_COOLDOWN


func _update_leap(delta: float) -> void:
	_leap_elapsed += delta
	var progress: float = minf(_leap_elapsed / LEAP_DURATION, 1.0)
	global_position = _leap_start.lerp(_leap_target, progress)
	_visual_height = sin(progress * PI) * LEAP_HEIGHT
	queue_redraw()

	if progress < 1.0:
		return
	_is_leaping = false
	_visual_height = 0.0
	queue_redraw()
	if global_position.distance_to(player.global_position) <= MELEE_HIT_RANGE:
		player.take_damage(DAMAGE)


func _try_throw_stone() -> bool:
	var nearest: Node2D = null
	var nearest_distance: float = STONE_PICKUP_RANGE + 0.001
	for node: Node in get_tree().get_nodes_in_group("throwable_stones"):
		if not node is Node2D or not node.has_method("throw_at"):
			continue
		var stone := node as Node2D
		var distance: float = global_position.distance_to(stone.global_position)
		if distance <= nearest_distance:
			nearest = stone
			nearest_distance = distance

	if nearest == null:
		stop_navigation()
		return false
	nearest.call("throw_at", player, DAMAGE)
	_attack_cooldown = ATTACK_COOLDOWN
	return true


func _set_attack_intent(value: bool) -> void:
	if _has_attack_intent == value:
		return
	_has_attack_intent = value
	queue_redraw()


func has_attack_intent() -> bool:
	return _has_attack_intent


func _draw() -> void:
	var offset := Vector2(0.0, -_visual_height)
	var fur := Color(0.34, 0.24, 0.16)
	var light_fur := Color(0.56, 0.40, 0.25)
	var outline := Color(0.10, 0.08, 0.07)

	draw_line(offset + Vector2(-6, 5), offset + Vector2(-10, 11), outline, 4.0)
	draw_line(offset + Vector2(6, 5), offset + Vector2(10, 11), outline, 4.0)
	draw_line(offset + Vector2(-5, -1), offset + Vector2(-11, 3), fur, 4.0)
	draw_line(offset + Vector2(5, -1), offset + Vector2(11, 3), fur, 4.0)
	draw_circle(offset + Vector2(0, 1), 8.0, fur)
	draw_circle(offset + Vector2(0, -7), 6.5, fur)
	draw_circle(offset + Vector2(0, -6), 4.0, light_fur)
	var eye_color := Color(0.95, 0.18, 0.12) if _has_attack_intent else Color(0.08, 0.07, 0.06)
	draw_circle(offset + Vector2(-2, -8), 1.0, eye_color)
	draw_circle(offset + Vector2(2, -8), 1.0, eye_color)
	if _has_attack_intent:
		draw_arc(offset + Vector2.ZERO, 13.0, PI * 1.1, PI * 1.9, 16, Color(0.95, 0.20, 0.12), 1.5)
