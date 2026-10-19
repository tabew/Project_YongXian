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
	for coords: Vector2i in spawner._supply_guards_by_chunk.keys():
		if not spawner._monsters_by_chunk.has(coords):
			continue
		for guard: Dictionary in spawner._supply_guards_by_chunk[coords]:
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
		var room_kind: int = world._generator.run.type_of(spec.node_id)
		if room_kind == RoomType.Kind.EVENT:
			check(world.monster_spawner.content.budget_of(spec.node_id, MapContent.ENEMY) == 0, "event_habitat_has_no_enemy_budget")
			world._enter_map(spec.node_id)
			await ready_map(world)
			check(world.monster_spawner.monsters.is_empty(), "event_habitat_stays_monster_free")
			continue
		check(world.monster_spawner.content.budget_of(spec.node_id, MapContent.ENEMY) > 0, "supported_non_event_habitat_has_enemy_eligibility")
		if room_kind != RoomType.Kind.COMBAT:
			world._enter_map(spec.node_id)
			await ready_map(world)
			for actor: BaseMonster in world.monster_spawner.monsters:
				var local: Vector2i = actor.original_spawn_tile - spec.origin
				check(spec.contains_local(local.x, local.y), "noncombat_habitat_monsters_belong_to_active_room")
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
			check(guard_count == slots.size() and not ordinary_tiles.is_empty(), "entry_loads_supply_guards_and_ordinary_monsters node=%d side=%d guards=%d planned=%d ordinary=%d" % [spec.node_id, gate.x, guard_count, slots.size(), ordinary_tiles.size()])
			check(nearby_gate_count >= (3 if spec.biome_id == Biome.Kind.SWAMP else 2), "original_gate_pack_remains_visible")
			for post: Vector2i in posts:
				var planned_at_post: int = 0
				for guard_post: Vector2i in slots.values():
					planned_at_post += int(guard_post == post)
				check(site_counts[post] == planned_at_post, "loaded_supply_site_matches_guard_plan node=%d side=%d post=%s actual=%d planned=%d" % [spec.node_id, gate.x, post, site_counts[post], planned_at_post])
			var initial_loaded_chunks: Dictionary = {}
			for coords: Vector2i in world.monster_spawner._monsters_by_chunk.keys():
				initial_loaded_chunks[coords] = true
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
			check(defeated == 1, "killed_guard_records_one_spawn_identity")
			world._enter_map(0)
			world._enter_map(spec.node_id, gate.x, gate.y)
			await ready_map(world)
			var return_slots: Dictionary = planned_slots(world.monster_spawner)
			var remaining_guards: int = 0
			var matching_ordinary: int = 0
			for actor: BaseMonster in world.monster_spawner.monsters:
				var actor_tile: Vector2i = actor.original_spawn_tile
				var coords: Vector2i = WorldGenerator.tile_to_chunk(actor_tile)
				if actor.has_supply_post:
					remaining_guards += 1
					check(return_slots.has(actor_tile) and actor_tile != dead_tile, "return_restores_only_surviving_loaded_guard_slots")
				elif initial_loaded_chunks.has(coords):
					matching_ordinary += 1
					check(ordinary_tiles.has(actor_tile), "return_keeps_original_loaded_ordinary_spawn_slots")
			var expected_ordinary: int = 0
			for old_tile: Vector2i in ordinary_tiles.keys():
				expected_ordinary += int(world.monster_spawner._monsters_by_chunk.has(WorldGenerator.tile_to_chunk(old_tile)))
			var expected_guards: int = return_slots.size() - int(return_slots.has(dead_tile))
			check(remaining_guards == expected_guards and matching_ordinary == expected_ordinary, "return_keeps_loaded_slots_without_replacing_dead_guard node=%d side=%d guards=%d expected=%d ordinary=%d expected=%d" % [spec.node_id, gate.x, remaining_guards, expected_guards, matching_ordinary, expected_ordinary])
			print("SUPPLY_ENCOUNTER node=%d side=%d sites=%d guards=%d ordinary=%d" % [spec.node_id, gate.x, posts.size(), slots.size(), ordinary_tiles.size()])
			world.build_world(1741004498)
	world.queue_free()
	await process_frame
	await process_frame
	print("SUPPLY_ENCOUNTERS: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
