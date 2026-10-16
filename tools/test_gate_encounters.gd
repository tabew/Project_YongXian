extends SceneTree

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func ready_map(world: Node2D) -> void:
	for frame: int in 480:
		if world.chunk_manager.map_ready() and world.monster_spawner.get_pending_spawn_count() == 0:
			return
		await process_frame
	check(false, "map_and_supply_guards_finish_loading")

func planned_slots(spawner: MonsterSpawner) -> Dictionary:
	var slots: Dictionary = {}
	for group: Array in spawner._supply_guards_by_chunk.values():
		for guard: Dictionary in group:
			slots[guard["tile"]] = guard["post"]
	return slots

func _run() -> void:
	Engine.max_fps = 240
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 1741004498)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	for spec: MapSpec in world._generator.map_specs():
		if spec.biome_id not in [Biome.Kind.SWAMP, Biome.Kind.TROPICAL_RAINFOREST]:
			continue
		if world.monster_spawner.content.budget_of(spec.node_id, MapContent.ENEMY) <= 0:
			world._enter_map(spec.node_id)
			await ready_map(world)
			check(world.monster_spawner.monsters.is_empty(), "safe_habitat_supply_site_is_unoccupied")
			continue
		var posts: Dictionary = {}
		for structure: Dictionary in world._generator.population_for(spec.node_id)["structures"]:
			if structure["kind"] == &"supplies":
				posts[structure["tile"]] = 0
		check(not posts.is_empty(), "combat_room_contains_supply_site")
		var gates: Array[Vector2i] = [Vector2i(-1, spec.west_gate_y)]
		for y: int in spec.east_gates:
			gates.append(Vector2i(1, y))
		for gate: Vector2i in gates:
			world._enter_map(spec.node_id, gate.x, gate.y)
			await ready_map(world)
			var slots: Dictionary = planned_slots(world.monster_spawner)
			var site_counts: Dictionary = posts.duplicate()
			var ordinary_tiles: Dictionary = {}
			var guard_count: int = 0
			var nearby_gate_count: int = 0
			for actor: BaseMonster in world.monster_spawner.monsters:
				var tile: Vector2i = actor.original_spawn_tile
				if not actor.has_supply_post:
					ordinary_tiles[tile] = true
					check(not slots.has(tile), "ordinary_enemy_does_not_overlap_supply_guard")
					if actor.global_position.distance_to(world.player.global_position) < 16.0 * 15.0:
						nearby_gate_count += 1
					continue
				guard_count += 1
				var post: Vector2i = WorldGenerator.world_to_tile(actor.supply_post)
				check(slots.get(tile) == post and posts.has(post), "guard_remains_assigned_to_real_supply_site")
				check((tile - post).length_squared() <= 64, "guard_slot_inside_supply_patrol_radius")
				site_counts[post] += 1
			check(guard_count == slots.size() and not ordinary_tiles.is_empty(), "entry_loads_supply_guards_and_ordinary_monsters")
			check(nearby_gate_count >= (3 if spec.biome_id == Biome.Kind.SWAMP else 2), "original_gate_pack_remains_visible")
			for post: Vector2i in posts:
				check(site_counts[post] in [2, 3], "each_combat_supply_site_has_two_or_three_occupants")
			var victim: BaseMonster = null
			for actor: BaseMonster in world.monster_spawner.monsters:
				if actor.has_supply_post:
					victim = actor
					break
			if victim == null:
				continue
			var dead_tile: Vector2i = victim.original_spawn_tile
			var defeated_before: int = world.monster_spawner._defeated_spawn_ids.size()
			victim.kill()
			var defeated: int = world.monster_spawner._defeated_spawn_ids.size() - defeated_before
			world._enter_map(0)
			world._enter_map(spec.node_id, gate.x, gate.y)
			await ready_map(world)
			var remaining_guards: int = 0
			var remaining_ordinary: int = 0
			for actor: BaseMonster in world.monster_spawner.monsters:
				if actor.has_supply_post:
					remaining_guards += 1
					check(slots.has(actor.original_spawn_tile) and actor.original_spawn_tile != dead_tile, "return_restores_only_surviving_guard_slots")
				else:
					remaining_ordinary += 1
					check(ordinary_tiles.has(actor.original_spawn_tile), "return_keeps_original_ordinary_spawn_slots")
			check(remaining_guards == slots.size() - defeated and remaining_ordinary == ordinary_tiles.size(), "return_keeps_scattered_monsters_without_replacing_dead_guard")
			print("SUPPLY_ENCOUNTER node=%d side=%d sites=%d guards=%d ordinary=%d" % [spec.node_id, gate.x, posts.size(), slots.size(), ordinary_tiles.size()])
			world.build_world(1741004498)
	world.queue_free()
	await process_frame
	await process_frame
	print("SUPPLY_ENCOUNTERS: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
