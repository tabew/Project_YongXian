extends SceneTree

## godot --headless --path . --script res://tools/test_map_events.gd
##
## 第一版地图事件验收：事件房必有草丛药水，点位确定、可达、避开道路与已有内容；
## 运行时能交互拿奖励，地刺能造成一次伤害。

const GIVE_SCENE: PackedScene = preload("res://scenes/monsters/give_monster.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)


func _run() -> void:
	_check_plans()
	await _check_runtime()
	print("MAP_EVENTS: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_plans() -> void:
	var total_event_rooms: int = 0
	for seed_value: int in [1, 18473, 97231, 2147483646]:
		var generator := WorldGenerator.new(seed_value)
		var replica := WorldGenerator.new(seed_value)
		var event_rooms: int = 0
		var grass_events: int = 0
		var spike_traps: int = 0
		for spec: MapSpec in generator.map_specs():
			var population: Dictionary = generator.population_for(spec.node_id)
			var reserved: Array[Rect2i] = []
			reserved.assign(population.get("reserved", []))
			var plan: Array[Dictionary] = MapEventPlanner.plan(generator, spec, reserved)
			var replica_population: Dictionary = replica.population_for(spec.node_id)
			var replica_reserved: Array[Rect2i] = []
			replica_reserved.assign(replica_population.get("reserved", []))
			var replica_plan: Array[Dictionary] = MapEventPlanner.plan(replica, spec, replica_reserved)
			_check(var_to_str(plan) == var_to_str(replica_plan), "event_plan_deterministic_%d_%d" % [seed_value, spec.node_id])
			var room_kind: int = generator.run.type_of(spec.node_id)
			if room_kind == RoomType.Kind.EVENT:
				event_rooms += 1
				var room_grass: int = plan.filter(
					func(entry: Dictionary) -> bool: return entry["event_id"] == MapEventPlanner.GRASS_POTION
				).size()
				_check(room_grass >= 2, "event_room_has_multiple_grass_events_%d" % spec.node_id)
			if room_kind == RoomType.Kind.COMBAT:
				var room_traps: int = plan.filter(
					func(entry: Dictionary) -> bool: return entry["event_id"] == MapEventPlanner.SPIKE_TRAP
				).size()
				_check(room_traps >= 2, "combat_room_has_multiple_spike_traps_%d" % spec.node_id)
			var reachable: Dictionary = _reachable(generator, spec)
			var footprints: Array[Rect2i] = []
			for entry: Dictionary in plan:
				var tile: Vector2i = entry["tile"]
				var footprint := Rect2i(tile - Vector2i.ONE, Vector2i(3, 3))
				var local: Vector2i = tile - spec.origin
				_check(spec.contains_local(local.x, local.y), "event_inside_region")
				_check(reachable.has(tile), "event_is_reachable_%d_%d" % [seed_value, spec.node_id])
				_check(generator.is_walkable(tile), "event_is_walkable")
				_check(not Terrain.is_water(generator.sample_terrain(tile)), "event_not_in_water")
				_check(generator.sample_route(tile) == Route.Kind.NONE, "event_not_on_road")
				for rect: Rect2i in reserved:
					_check(not footprint.intersects(rect), "event_avoids_population")
				for other: Rect2i in footprints:
					_check(not footprint.intersects(other), "events_do_not_overlap")
				footprints.append(footprint)
				if entry["event_id"] == MapEventPlanner.GRASS_POTION:
					grass_events += 1
				elif entry["event_id"] == MapEventPlanner.SPIKE_TRAP:
					spike_traps += 1
		total_event_rooms += event_rooms
		_check(grass_events >= 15, "seed_has_dense_grass_events_%d" % seed_value)
		_check(spike_traps >= 15, "seed_has_dense_spike_traps_%d" % seed_value)
		print("EVENT_SAMPLE seed=%d rooms=%d grass=%d traps=%d" % [seed_value, event_rooms, grass_events, spike_traps])
	_check(total_event_rooms > 0, "at_least_one_event_room_in_samples")


func _check_runtime() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 18473)
	var world: Node = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("GameHUD/BagUi").hide()
	world.get_node("GameHUD/Alchemy").hide()

	var event_spec: MapSpec = null
	for spec: MapSpec in world._generator.map_specs():
		if world._generator.run.type_of(spec.node_id) == RoomType.Kind.EVENT:
			event_spec = spec
			break
	_check(event_spec != null, "runtime_event_room_exists")
	if event_spec == null:
		world.queue_free()
		await process_frame
		return

	world._setup_map_events(event_spec)
	var holder: Node2D = world._map_entity_root(event_spec.node_id)
	var world_event: WorldEvent = null
	for child: Node in holder.get_children():
		if child is WorldEvent:
			world_event = child as WorldEvent
			break
	_check(world_event != null, "runtime_event_instantiates")
	if world_event != null:
		world._current_node = event_spec.node_id
		world.player.global_position = world_event.global_position
		world._refresh_pickup()
		_check(world._nearby_event == world_event, "runtime_event_is_targeted")
		_check(world.hud.get_node("PickupHint").text.contains("搜索草丛"), "hud_explains_event_action")
		var before_total: int = _inventory_total(world.player.inventory)
		_press_e(world)
		_check(world_event.consumed, "runtime_event_consumed")
		_check(not world_event.visible, "runtime_event_hides_after_use")
		_check(_inventory_total(world.player.inventory) > before_total, "runtime_event_rewards_item")
		_check(not world_event.interact(world.player), "runtime_event_only_once")

	var health_before: float = world.player.health
	var trap := SpikeTrap.new()
	world.add_child(trap)
	trap.global_position = world.player.global_position
	trap._on_body_entered(world.player)
	await create_timer(SpikeTrap.TELEGRAPH_TIME + 0.15).timeout
	_check(world.player.health < health_before, "spike_trap_damages_player")
	var health_after_first: float = world.player.health
	await create_timer(SpikeTrap.DAMAGE_INTERVAL + 0.1).timeout
	_check(world.player.health < health_after_first, "spike_trap_continuous_damage")
	trap.queue_free()

	var monster_trap := SpikeTrap.new()
	world.add_child(monster_trap)
	monster_trap.global_position = world.player.global_position + Vector2(64, 0)
	var monster := GIVE_SCENE.instantiate() as BaseMonster
	_check(monster != null, "runtime_monster_instantiates_for_trap")
	if monster != null:
		world.add_child(monster)
		monster.global_position = monster_trap.global_position
		monster.configure(world.player, world._generator, Vector2i.ZERO)
		monster.set_physics_process(false)
		var monster_health := monster.get_node("Health") as HealthComponent
		var monster_before: float = monster_health.current_health
		monster_trap._on_body_entered(monster)
		await create_timer(SpikeTrap.TELEGRAPH_TIME + 0.15).timeout
		_check(monster_health.current_health < monster_before, "spike_trap_damages_monster")
	monster_trap.queue_free()
	world.queue_free()
	await process_frame


func _press_e(world: Node) -> void:
	var event := InputEventAction.new()
	event.action = &"pickup_item"
	event.pressed = true
	world._unhandled_input(event)


func _inventory_total(inventory: Inventory) -> int:
	var total: int = 0
	for item_id: int in inventory.items.keys():
		total += int(inventory.items[item_id])
	return total


func _reachable(generator: WorldGenerator, spec: MapSpec) -> Dictionary:
	var start: Vector2i = WorldGenerator.world_to_tile(generator.entry_position(spec.node_id))
	var visited: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var index: int = 0
	while index < queue.size():
		var tile: Vector2i = queue[index]
		index += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = tile + direction
			var local: Vector2i = next - spec.origin
			if visited.has(next):
				continue
			if not spec.contains_local(local.x, local.y):
				continue
			if not generator.is_walkable(next):
				continue
			visited[next] = true
			queue.append(next)
	return visited