class_name BossLasso
extends Node2D

signal resolved(reached_boss: bool)

const HEALTH: float = 300.0
const TRAVEL_SPEED: float = 640.0
const PULL_SPEED: float = 32.0
const DAMAGE_INTERVAL: float = 0.5
const CATCH_RADIUS: float = 14.0
const DETONATE_DISTANCE: float = 48.0

var boss: BaseMonster
var victim: PlayerCharacter
var health: HealthComponent
var hurtbox: CombatHurtbox
var _shape: CapsuleShape2D
var _tip: Vector2
var _direction: Vector2 = Vector2.RIGHT
var _flight_time: float = 0.0
var _damage_time: float = 0.0
var _caught: bool = false
var _finished: bool = false


func _ready() -> void:
	health = HealthComponent.new()
	health.name = "Health"
	health.max_health = HEALTH
	add_child(health)
	health.died.connect(_on_rope_died)
	hurtbox = CombatHurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.health = health
	hurtbox.team = 2
	hurtbox.collision_layer = 0
	hurtbox.collision_mask = 0
	_shape = CapsuleShape2D.new()
	_shape.radius = 8.0
	_shape.height = 16.0
	var collider := CollisionShape2D.new()
	collider.shape = _shape
	hurtbox.add_child(collider)
	add_child(hurtbox)


func launch(owner: BaseMonster, player: PlayerCharacter) -> void:
	boss = owner
	victim = player
	_tip = boss.global_position
	global_position = _tip
	_direction = (player.global_position - _tip).normalized()
	if _direction.is_zero_approx():
		_direction = Vector2.RIGHT
	_update_hurtbox()


func _physics_process(delta: float) -> void:
	if _finished or not is_instance_valid(boss) or boss.is_queued_for_deletion() or int(boss.get("phase")) != 1:
		_resolve(false)
		return
	if not is_instance_valid(victim) or victim.health <= 0.0:
		_resolve(false)
		return
	if boss is FinalBoss and not (boss as FinalBoss).player_in_boss_room():
		_resolve(false)
		return
	if not _caught:
		var previous: Vector2 = _tip
		_tip += _direction * TRAVEL_SPEED * delta
		_flight_time += delta
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(victim.global_position, previous, _tip)
		if closest.distance_to(victim.global_position) <= CATCH_RADIUS:
			_caught = true
			_tip = victim.global_position
			victim.set_boss_grappled(true)
			hurtbox.set_deferred("collision_layer", 4)
		elif _outside_room() or _flight_time > 15.0:
			_resolve(false)
			return
	else:
		if not victim.move_by_boss_pull(boss.global_position, PULL_SPEED * delta):
			_resolve(false)
			return
		_tip = victim.global_position
		_damage_time += delta
		while _damage_time >= DAMAGE_INTERVAL:
			_damage_time -= DAMAGE_INTERVAL
			victim.take_damage(0.5, boss)
		if _tip.distance_to(boss.global_position) <= DETONATE_DISTANCE:
			_resolve(true)
			return
	_update_hurtbox()
	queue_redraw()


func _outside_room() -> bool:
	if victim.active_map == null:
		return false
	var tile: Vector2i = WorldGenerator.world_to_tile(_tip) - victim.active_map.origin
	return not victim.active_map.contains_local(tile.x, tile.y)


func _update_hurtbox() -> void:
	if not is_instance_valid(hurtbox) or not is_instance_valid(boss):
		return
	var span: Vector2 = _tip - boss.global_position
	hurtbox.global_position = (boss.global_position + _tip) * 0.5
	hurtbox.rotation = span.angle() + PI * 0.5
	_shape.height = maxf(span.length(), 16.0)


func _on_rope_died(_hit: CombatHit) -> void:
	_resolve(false)


func abort() -> void:
	_resolve(false)


func _resolve(reached_boss: bool) -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(victim):
		victim.set_boss_grappled(false)
	resolved.emit(reached_boss)
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(victim):
		victim.set_boss_grappled(false)


func _draw() -> void:
	if not is_instance_valid(boss):
		return
	var start: Vector2 = to_local(boss.global_position)
	var end: Vector2 = to_local(_tip)
	draw_line(start, end, Color(0.38, 0.13, 0.2, 0.8), 7.0)
	draw_line(start, end, Color(0.94, 0.56, 0.62, 0.95), 2.0)
	draw_circle(end, 9.0, Color(0.94, 0.51, 0.62, 0.85))
	if _caught:
		draw_arc(end, 12.0, 0.0, TAU, 24, Color(1.0, 0.92, 0.79, 0.95), 2.0)
