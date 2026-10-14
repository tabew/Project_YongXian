class_name ShiMonster
extends BaseMonster

## 史独有的低跳、吞物与合团；这些机制不进入通用怪物模板。
const HOP_DURATION: float = 0.22
const HOP_REST: float = 1.0
const SWALLOW_RADIUS: float = 10.0
const FORM_RADIUS: float = 64.0
const GROUP_RADIUS: float = 18.0
const GROUP_SPEED: float = 24.0
const LOOT_TABLE: MonsterLootTable = preload("res://resources/monsters/shi_loot_table.tres")

var group_leader: ShiMonster = null
var group_members: Array[ShiMonster] = []
var spin_phase: float = 0.0
var body_squash: Vector2 = Vector2.ONE:
	set(value):
		body_squash = value
		var body := get_node_or_null("Visual/Body") as Node2D
		if body != null:
			body.scale = value
var _hop_active: bool = false
var _hop_elapsed: float = 0.0
var _hop_count: int = 0
var _hop_rest: float = 0.0
var _swallow_timer: float = 0.0
var _belly: Node2D = null
var _shi_dead: bool = false


func _ready() -> void:
	if death_loot == null:
		death_loot = LOOT_TABLE
	super._ready()
	add_to_group("shi_monsters")
	ShiProximityCache.invalidate()


func _create_attack() -> EnemyAttack:
	return ShiMonsterAttack.new()


func configure(target_player: PlayerCharacter, generator: WorldGenerator, chunk_coords: Vector2i) -> void:
	super.configure(target_player, generator, chunk_coords)
	# 腹内节点按原始生成格存放于地图实体根，卸载怪物不会销毁吞入的原物品。
	var storage: Node = get_parent()
	var owner_world: Node = storage.get_parent() if storage != null else null
	var spec: MapSpec = generator.sample_map(WorldGenerator.world_to_tile(global_position)) if generator != null else null
	if owner_world != null and owner_world.has_method("_map_entity_root") and spec != null:
		storage = owner_world.call("_map_entity_root", spec.node_id)
	if storage == null:
		return
	var cache := storage.get_node_or_null("ShiStomachs") as Node2D
	if cache == null:
		cache = Node2D.new()
		cache.name = "ShiStomachs"
		cache.visible = false
		cache.process_mode = Node.PROCESS_MODE_DISABLED
		storage.add_child(cache)
	var tile: Vector2i = WorldGenerator.world_to_tile(global_position)
	var key: String = "Shi_%d_%d_%d" % [generator.get_instance_id() if generator != null else 0, tile.x, tile.y]
	_belly = cache.get_node_or_null(key) as Node2D
	if _belly == null:
		_belly = Node2D.new()
		_belly.name = key
		cache.add_child(_belly)


func is_group_leader() -> bool:
	return group_leader == self and group_members.size() == 3


func is_group_member() -> bool:
	return is_instance_valid(group_leader) and group_leader != self


func _physics_process(delta: float) -> void:
	if _shi_dead or is_group_member():
		return
	_hop_rest = maxf(_hop_rest - delta, 0.0)
	super._physics_process(delta)
	if is_group_leader():
		if monster_animation_state() == &"Idle":
			play_monster_animation(&"Spin")
		return
	if is_receiving_knockback():
		_hop_active = false
		return
	if _hop_active:
		_hop_elapsed += delta
		if _hop_elapsed >= HOP_DURATION:
			_hop_active = false
			_hop_count += 1
			if _hop_count >= 2:
				_hop_count = 0
				_hop_rest = HOP_REST
				velocity = Vector2.ZERO
				play_monster_animation(&"Rest", true)
	if get_ai_state() == EnemyState.State.PATROL:
		_swallow_timer -= delta
		if _swallow_timer <= 0.0:
			_swallow_timer = 0.10
			swallow_nearby_items()
	# 单体外形静态；跳跃与挤压由动画变换完成，不需每物理帧重建绘图命令。


func movement_speed() -> float:
	if is_group_leader():
		return GROUP_SPEED
	return 0.0 if _hop_rest > 0.0 else navigation_speed


func play_monster_animation(state: StringName, restart: bool = false) -> void:
	if state == &"Move" and not is_group_leader():
		if _hop_rest > 0.0:
			super.play_monster_animation(&"Rest")
			return
		if not _hop_active:
			_hop_active = true
			_hop_elapsed = 0.0
			restart = true
		state = &"Hop"
	elif state == &"Move" and is_group_leader():
		if monster_animation_state() in [&"Form", &"Shoot", &"Hurt"]:
			return
		state = &"Spin"
	elif state == &"Idle" and _hop_rest > 0.0:
		state = &"Rest"
	elif state == &"Idle" and _hop_active and not _death_committed:
		return
	super.play_monster_animation(state, restart)


func swallow_nearby_items() -> int:
	if _shi_dead or is_group_leader() or is_group_member() or get_ai_state() != EnemyState.State.PATROL or not is_instance_valid(_belly):
		return 0
	var count: int = 0
	for node: Node in ShiProximityCache.nearby(self, &"ground_pickups", SWALLOW_RADIUS):
		if not node is GroundPickup:
			continue
		var item := node as GroundPickup
		if not item.is_available_for_pickup() or not item.is_visible_in_tree() or not item.can_process():
			continue
		if global_position.distance_to(item.global_position) > SWALLOW_RADIUS:
			continue
		if world_generator != null and not has_clear_line_to_position(item.global_position):
			continue
		item.set_highlighted(false)
		# 仅史维护吞入物的占用标记，不发背包收取信号，也不改变原数据或数量。
		item._collected = true
		item._update_throwable_group()
		item.reparent(_belly, true)
		count += 1
	return count


func swallowed_items() -> Array[GroundPickup]:
	var items: Array[GroundPickup] = []
	if is_instance_valid(_belly):
		for child: Node in _belly.get_children():
			if child is GroundPickup and not child.is_queued_for_deletion():
				items.append(child)
	return items


func nearby_partners() -> Array[ShiMonster]:
	var result: Array[ShiMonster] = []
	if _shi_dead or group_leader != null:
		return result
	for node: Node in ShiProximityCache.nearby(self, &"shi_monsters", FORM_RADIUS):
		var candidate := node as ShiMonster
		if candidate == null or candidate == self or candidate._shi_dead or candidate.is_queued_for_deletion() or candidate.group_leader != null:
			continue
		if candidate.get_parent() != get_parent() or candidate.world_generator != world_generator or not candidate.is_visible_in_tree():
			continue
		if global_position.distance_to(candidate.global_position) > FORM_RADIUS:
			continue
		if world_generator != null and not has_clear_line_to_position(candidate.global_position):
			continue
		result.append(candidate)
	result.sort_custom(func(a: ShiMonster, b: ShiMonster) -> bool: return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return result


func form_group() -> bool:
	var partners: Array[ShiMonster] = nearby_partners()
	if partners.size() < 2:
		return false
	group_members = [self, partners[0], partners[1]]
	group_leader = self
	_hop_active = false
	_hop_rest = 0.0
	_visual_height = 0.0
	var health_component := get_node("Health") as HealthComponent
	var total_health: float = health_component.current_health
	var total_max: float = health_component.max_health
	for index: int in range(1, 3):
		var member: ShiMonster = group_members[index]
		member.group_leader = self
		member.stop_navigation()
		member.set_physics_process(false)
		member.visible = false
		member.global_position = global_position
		var health := member.get_node("Health") as HealthComponent
		total_health += health.current_health
		total_max += health.max_health
		(member.get_node("Hurtbox") as CombatHurtbox).health = health_component
		(member.get_node("CollisionShape2D") as CollisionShape2D).set_deferred("disabled", true)
		(member.get_node("Hurtbox/CollisionShape2D") as CollisionShape2D).set_deferred("disabled", true)
	health_component.max_health = total_max
	health_component.current_health = total_health
	health_component.health_changed.emit(total_health, total_max)
	var shape := CircleShape2D.new()
	shape.radius = GROUP_RADIUS
	(get_node("CollisionShape2D") as CollisionShape2D).set_deferred("shape", shape)
	(get_node("Hurtbox/CollisionShape2D") as CollisionShape2D).set_deferred("shape", shape)
	(get_node("NameLabel") as Label).text = "团团史"
	(get_node("Visual/Body") as CanvasItem).queue_redraw()
	play_monster_animation(&"Form", true)
	return true


func take_damage(amount: float) -> void:
	var health := get_node("Health") as HealthComponent
	if amount <= 0.0 or _shi_dead or not health.is_alive():
		return
	var hit := CombatHit.new()
	hit.source = self
	hit.damage = amount
	hit.position = global_position
	health.receive_hit(hit)


func kill() -> void:
	if _shi_dead or _death_committed:
		return
	if is_group_member() and not group_leader._shi_dead:
		group_leader.kill()
		return
	_shi_dead = true
	var death_position: Vector2 = global_position
	if is_group_leader():
		for member: ShiMonster in group_members:
			if member == self or not is_instance_valid(member):
				continue
			member.group_leader = null
			member.global_position = death_position
			member.kill()
	for item: GroundPickup in swallowed_items():
		item.reparent(get_parent(), true)
		item.global_position = death_position
		item._collected = false
		item._update_visual()
	if is_instance_valid(_belly):
		_belly.queue_free()
	super.kill()
