class_name CrocodileMonster
extends BaseMonster

## 饿：通用巡逻/追击/攻击模板，两栖移动与咬击由专用数据和攻击实现提供。
const LAND_SPEED_RATIO: float = 0.60
@export_range(0.1, 1.0, 0.05) var patrol_speed_ratio: float = 0.45
var _water_tile: Vector2i = EnemyPathfinder.INVALID_TILE
var _water_generator: WorldGenerator = null
var _water_frame: int = -1
var _water_state: int = -1
var _water_value: bool = false
var gait_phase: float = 0.0:
	set(value):
		if is_equal_approx(gait_phase, value):
			return
		gait_phase = value
		var visual_body := get_node_or_null("Visual/Body") as CanvasItem
		if visual_body != null:
			visual_body.queue_redraw()
var jaw_open: float = 0.0:
	set(value):
		var next: float = clampf(value, 0.0, 1.0)
		if is_equal_approx(jaw_open, next):
			return
		jaw_open = next
		var body := get_node_or_null("Visual/Body") as CanvasItem
		if body != null:
			body.queue_redraw()

func _create_attack() -> EnemyAttack:
	return CrocodileBiteAttack.new()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	sync_facing()

func sync_facing() -> void:
	if blackboard == null or blackboard.facing.is_zero_approx():
		return
	var angle: float = blackboard.facing.angle()
	var body := get_node("Visual/Body") as Node2D
	var collision := get_node("CollisionShape2D") as CollisionShape2D
	var hurt := get_node("Hurtbox/CollisionShape2D") as CollisionShape2D
	if not is_equal_approx(body.rotation, angle):
		body.rotation = angle
	if not is_equal_approx(collision.rotation, angle + PI * 0.5):
		collision.rotation = angle + PI * 0.5
	if not is_equal_approx(hurt.rotation, angle + PI * 0.5):
		hurt.rotation = angle + PI * 0.5

func play_monster_animation(state: StringName, restart: bool = false) -> void:
	if state == &"Move":
		state = &"Swim" if is_in_water() else &"Walk"
	super.play_monster_animation(state, restart)

func stop_navigation() -> void:
	velocity = Vector2.ZERO
	if monster_animation_state() in [&"Idle", &"Move", &"Swim", &"Walk"]:
		play_monster_animation(&"Idle")

func is_in_water() -> bool:
	if world_generator == null:
		return false
	var tile: Vector2i = WorldGenerator.world_to_tile(global_position)
	var frame: int = Engine.get_physics_frames()
	var state: int = get_ai_state()
	if tile != _water_tile or world_generator != _water_generator or frame != _water_frame or state != _water_state:
		_water_tile = tile
		_water_generator = world_generator
		_water_frame = frame
		_water_state = state
		_water_value = Terrain.is_water(world_generator.sample_terrain(tile)) and world_generator.sample_route(tile) == Route.Kind.NONE
	return _water_value

func _amphibious_tile_allowed(tile: Vector2i) -> bool:
	if world_generator == null:
		return false
	if player != null and player.active_map != null:
		var local: Vector2i = tile - player.active_map.origin
		if not player.active_map.contains_local(local.x, local.y):
			return false
	return world_generator.is_walkable(tile) or Terrain.is_water(world_generator.sample_terrain(tile))

func is_navigation_tile_allowed(tile: Vector2i) -> bool:
	if not _amphibious_tile_allowed(tile):
		return false
	# 在水中巡逻不抄岸上近路；岸边出生/失去目标时允许走向水中巡逻点。
	if get_ai_state() == EnemyState.State.PATROL and is_in_water():
		return CrocodileSpawnData.is_swamp_water(world_generator, tile)
	return true

func is_visibility_tile_allowed(tile: Vector2i) -> bool:
	return _amphibious_tile_allowed(tile)

func is_patrol_tile_allowed(tile: Vector2i) -> bool:
	return CrocodileSpawnData.is_swamp_water(world_generator, tile)

func _resolve_patrol_anchor() -> Vector2:
	if world_generator != null and not is_in_water():
		var water: Vector2i = CrocodileSpawnData.nearest_swamp_water(world_generator, WorldGenerator.world_to_tile(global_position))
		if water != EnemyPathfinder.INVALID_TILE:
			return WorldGenerator.tile_to_world(water)
	return super._resolve_patrol_anchor()

func movement_speed() -> float:
	var water_speed: float = navigation_speed
	if get_ai_state() == EnemyState.State.PATROL:
		water_speed *= patrol_speed_ratio
	return water_speed if is_in_water() else water_speed * LAND_SPEED_RATIO

func take_damage(amount: int) -> void:
	var health := get_node("Health") as HealthComponent
	if _death_committed or amount <= 0 or not health.is_alive():
		return
	var hit := CombatHit.new()
	hit.source = self
	hit.damage = amount
	hit.position = global_position
	health.receive_hit(hit)
