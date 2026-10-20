extends SceneTree

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func wait_room(world: Node2D) -> void:
	for frame: int in 480:
		if world.chunk_manager.map_ready() and world.monster_spawner.get_pending_spawn_count() == 0:
			return
		await process_frame
	check(false, "room_finishes_loading_supply_guards")

func supply_posts(generator: WorldGenerator, spec: MapSpec) -> Array[Vector2i]:
	var posts: Array[Vector2i] = []
	var population: Dictionary = generator.population_for(spec.node_id)
	for structure: Dictionary in population.get("structures", []):
		if structure["kind"] == &"supplies":
			posts.append(structure["tile"])
	return posts

func plan_signature(spawner: MonsterSpawner) -> Array[String]:
	var signature: Array[String] = []
	for group: Array in spawner._supply_guards_by_chunk.values():
		for slot: Dictionary in group:
			var tile: Vector2i = slot["tile"]
			var post: Vector2i = slot["post"]
			var definition: MonsterSpawnData = slot["definition"]
			signature.append("%s:%d:%d:%d:%d" % [definition.monster_id, tile.x, tile.y, post.x, post.y])
	signature.sort()
	return signature

func occupants(spawner: MonsterSpawner, guards: bool) -> Array[BaseMonster]:
	var result: Array[BaseMonster] = []
	for monster: BaseMonster in spawner.monsters:
		if monster.has_supply_post == guards:
			result.append(monster)
	return result

func eligible_guard_tiles(generator: WorldGenerator, spawner: MonsterSpawner, spec: MapSpec, post: Vector2i) -> int:
	var count: int = 0
	for y: int in range(-8, 9):
		for x: int in range(-8, 9):
			var offset := Vector2i(x, y)
			if offset.length_squared() > 64:
				continue
			var tile: Vector2i = post + offset
			if not spawner.allows_spawn_at(tile) or not generator.is_walkable(tile):
				continue
			for definition: MonsterSpawnData in spawner.spawn_definitions:
				if definition != null and definition.monster_scene != null and (definition.allowed_biomes.is_empty() or definition.allowed_biomes.has(spec.biome_id)) and definition.can_spawn_at(generator, tile):
					count += 1
					break
	return count

func _run() -> void:
	Engine.max_fps = 240
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 18473)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	var spawner: MonsterSpawner = world.monster_spawner
	await wait_room(world)
	var generator: WorldGenerator = world._generator
	check(not supply_posts(generator, generator.map_spec(0)).is_empty(), "start_room_has_a_supply_site")
	var start: MapSpec = generator.map_spec(0)
	check(world._combat_entry_count == 0 and spawner.monsters.is_empty(), "starting_floor_has_no_guards_or_enemies")
	check(spawner.content.budget_of(start.node_id, MapContent.ENEMY) == 0, "starting_floor_has_no_enemy_budget")

	var combat: MapSpec = null
	var boss: MapSpec = null
	var event_room: MapSpec = null
	for spec: MapSpec in generator.map_specs():
		if generator.run.type_of(spec.node_id) == RoomType.Kind.EVENT and event_room == null:
			event_room = spec
		if spec.node_id == generator.run.final_node():
			boss = spec
		elif combat == null and generator.run.type_of(spec.node_id) == RoomType.Kind.COMBAT and spawner.content.budget_of(spec.node_id, MapContent.ENEMY) > 0 and not supply_posts(generator, spec).is_empty():
			for definition: MonsterSpawnData in spawner.spawn_definitions:
				if definition != null and definition.monster_scene != null and (definition.allowed_biomes.is_empty() or definition.allowed_biomes.has(spec.biome_id)):
					combat = spec
					break
	check(combat != null and boss != null, "seed_has_combat_and_boss_sites")
	if combat == null or boss == null:
		world.queue_free()
		quit(1)
		return
	if event_room != null:
		check(spawner.content.budget_of(event_room.node_id, MapContent.ENEMY) == 0, "event_room_has_no_enemy_budget")
		world._enter_map(event_room.node_id, -1, event_room.west_gate_y)
		await wait_room(world)
		check(world._combat_entry_count == 0 and spawner.monsters.is_empty(), "event_room_has_no_enemies_or_guards")

	world._enter_map(combat.node_id, -1, combat.west_gate_y)
	await wait_room(world)
	var posts: Array[Vector2i] = supply_posts(generator, combat)
	var signature: Array[String] = plan_signature(spawner)
	check(not posts.is_empty(), "combat_area_contains_supply_sites")
	var guards: Array[BaseMonster] = occupants(spawner, true)
	var scattered: Array[BaseMonster] = occupants(spawner, false)
	check(guards.size() == signature.size() and not scattered.is_empty(), "combat_room_adds_guards_without_removing_ordinary_monsters")
	var by_post: Dictionary = {}
	for post: Vector2i in posts:
		by_post[post] = 0
	for group: Array in spawner._supply_guards_by_chunk.values():
		for slot: Dictionary in group:
			var tile: Vector2i = slot["tile"]
			var post: Vector2i = slot["post"]
			check(by_post.has(post) and (tile - post).length_squared() <= 64, "spawn_slot_within_eight_tiles_of_supply")
			check(generator.is_walkable(tile), "guard_starts_on_open_terrain")
			by_post[post] += 1
	for post: Vector2i in posts:
		var candidates: int = eligible_guard_tiles(generator, spawner, combat, post)
		check(by_post[post] <= mini(3, candidates), "supply_site_only_uses_eligible_guard_slots")
		if candidates >= 20:
			check(by_post[post] in [2, 3], "well_supported_supply_site_has_two_or_three_guards")
	var guard_tiles: Dictionary = {}
	for group: Array in spawner._supply_guards_by_chunk.values():
		for slot: Dictionary in group:
			guard_tiles[slot["tile"]] = true
	for monster: BaseMonster in guards:
		var post: Vector2i = WorldGenerator.world_to_tile(monster.supply_post)
		check(by_post.has(post), "each_guard_belongs_to_real_supply_site")
		check(monster.ai_config.patrol_radius_tiles == 8.0 and monster.blackboard.patrol_anchor == monster.supply_post, "each_guard_has_eight_tile_fixed_patrol")
	for monster: BaseMonster in scattered:
		check(not guard_tiles.has(monster.original_spawn_tile), "ordinary_monster_does_not_take_guard_spawn_tile")
	for monster: BaseMonster in spawner.monsters:
		check(monster.difficulty_entry == 1 and is_equal_approx(monster.difficulty_multiplier, MonsterDifficulty.multiplier_for_entry(1)), "guards_and_ordinary_monsters_use_first_entry_stats")

	if guards.is_empty():
		world.queue_free()
		quit(1)
		return
	var guard: BaseMonster = guards[0]
	spawner._wake_monster(guard)
	var post_position: Vector2 = guard.supply_post
	world.player.global_position = guard.global_position + Vector2(7.0 * WorldGenerator.TILE_SIZE, 0)
	guard.blackboard.state = EnemyState.State.CHASE
	guard.brain.tick(0.01)
	check(not guard.brain.is_returning_to_supply_post(), "guard_can_chase_within_eight_tiles_of_player")
	world.player.global_position = guard.global_position + Vector2(8.0 * WorldGenerator.TILE_SIZE, 0)
	guard.brain.tick(0.01)
	check(not guard.brain.is_returning_to_supply_post(), "exactly_eight_tiles_does_not_break_chase")
	world.player.global_position = guard.global_position + Vector2(9.0 * WorldGenerator.TILE_SIZE, 0)
	guard.brain.tick(0.01)
	check(guard.brain.is_returning_to_supply_post() and guard.blackboard.patrol_anchor == post_position, "guard_breaks_chase_and_paths_home_beyond_eight_tiles")
	check(guard.navigator.last_target_tile == WorldGenerator.world_to_tile(post_position), "return_destination_is_supply_center")
	var far_player_position: Vector2 = world.player.global_position
	world.player.global_position = guard.global_position + Vector2(2.0 * WorldGenerator.TILE_SIZE, 0)
	guard.brain.tick(0.01)
	check(guard.brain.is_returning_to_supply_post(), "guard_does_not_reacquire_player_before_reaching_post")
	world.player.global_position = far_player_position
	spawner._update_monster_activity(guard)
	check(guard.process_mode != Node.PROCESS_MODE_DISABLED, "returning_guard_does_not_sleep_midway")
	var returned: bool = false
	for frame: int in 360:
		if not guard.brain.is_returning_to_supply_post():
			returned = true
			break
		await physics_frame
	check(returned and guard.global_position.distance_to(post_position) <= WorldGenerator.TILE_SIZE, "guard_navigates_home_then_resumes_post_patrol")
	check(guard.blackboard.patrol_anchor == post_position, "arriving_guard_keeps_supply_patrol_anchor")
	check(guard.supply_patrol_allows(WorldGenerator.world_to_tile(post_position) + Vector2i(8, 0)) and not guard.supply_patrol_allows(WorldGenerator.world_to_tile(post_position) + Vector2i(9, 0)), "patrol_boundary_stops_at_eight_tiles")
	var path_guard: BaseMonster = guard
	if path_guard is CrocodileMonster:
		for actor: BaseMonster in guards:
			if not actor is CrocodileMonster:
				path_guard = actor
				break
	if not path_guard is CrocodileMonster:
		var site: Vector2i = WorldGenerator.world_to_tile(path_guard.supply_post)
		var patrol_path: Array[Vector2i] = EnemyPathfinder.build_path(path_guard, site + Vector2i(-4, -1), site + Vector2i(4, -1), 6, {})
		check(patrol_path.size() > 1, "guard_patrol_paths_around_supply_crates")
		for step: Vector2i in patrol_path:
			check(path_guard.supply_patrol_allows(step), "guard_patrol_path_never_exits_supply_circle")

	if event_room != null:
		world._enter_map(event_room.node_id, -1, event_room.west_gate_y)
		await wait_room(world)
		check(world._combat_entry_count == 1 and spawner.monsters.is_empty(), "event_room_stays_safe_after_guard_encounter")
	world._enter_map(0)
	await wait_room(world)
	check(world._combat_entry_count == 1 and spawner.monsters.is_empty(), "return_to_start_has_no_enemies_or_difficulty_increase")
	world._enter_map(combat.node_id, -1, combat.west_gate_y)
	await wait_room(world)
	check(plan_signature(spawner) == signature, "return_preserves_deterministic_guard_slots")
	check(not occupants(spawner, false).is_empty(), "first_return_keeps_ordinary_room_monsters")
	for monster: BaseMonster in spawner.monsters:
		check(monster.difficulty_entry == 2 and is_equal_approx(monster.difficulty_multiplier, MonsterDifficulty.multiplier_for_entry(2)), "revisited_guard_scales_as_normal_monster")
	var dead_before: int = spawner._defeated_spawn_ids.size()
	var killed_guard: Array[BaseMonster] = occupants(spawner, true)
	check(not killed_guard.is_empty(), "reentered_supply_guard_available_for_kill")
	if not killed_guard.is_empty():
		killed_guard[0].kill()
	var killed_slots: int = spawner._defeated_spawn_ids.size() - dead_before
	check(killed_slots > 0, "supply_guard_death_records_original_slot")
	world._enter_map(0)
	await wait_room(world)
	check(world._combat_entry_count == 2 and spawner.monsters.is_empty(), "second_return_to_start_remains_safe")
	world._enter_map(combat.node_id, -1, combat.west_gate_y)
	await wait_room(world)
	check(world._combat_entry_count == 3, "third_combat_visit_uses_third_entry")
	check(occupants(spawner, true).size() == signature.size() - killed_slots, "return_does_not_replace_dead_supply_guard")
	check(not occupants(spawner, false).is_empty(), "return_keeps_original_scattered_encounters")
	for ordinary: BaseMonster in occupants(spawner, false):
		check(not guard_tiles.has(ordinary.original_spawn_tile), "revisited_ordinary_spawn_stays_clear_of_guard_slots")

	world._enter_map(boss.node_id, -1, boss.west_gate_y)
	await wait_room(world)
	check(world._combat_entry_count == 4, "boss_room_advances_fourth_entry")
	var final_boss_count: int = 0
	var boss_guard_count: int = 0
	for monster: BaseMonster in spawner.monsters:
		if monster is FinalBoss:
			final_boss_count += 1
		elif monster.has_supply_post:
			boss_guard_count += 1
	check(final_boss_count == 1 and spawner.monsters.size() == 1, "final_room_contains_only_one_fixed_boss")
	check(boss_guard_count == 0 and plan_signature(spawner).is_empty(), "final_room_has_no_supply_guards")

	world.build_world(18473)
	check(world._combat_entry_count == 0 and spawner.monsters.is_empty(), "new_run_restarts_safe_at_zero")
	world._enter_map(combat.node_id, -1, combat.west_gate_y)
	await wait_room(world)
	check(plan_signature(spawner) == signature and occupants(spawner, true).size() == signature.size() and not occupants(spawner, false).is_empty(), "same_seed_new_run_restores_guard_and_scattered_encounters")
	for monster: BaseMonster in spawner.monsters:
		check(monster.difficulty_entry == 1 and is_equal_approx(monster.difficulty_multiplier, MonsterDifficulty.multiplier_for_entry(1)), "new_run_combat_monsters_restart_at_first_entry")
	for seed_value: int in [1, 1741004498, 97231, 2147483646]:
		world.build_world(seed_value)
		var planner := MonsterSpawner.new()
		planner.spawn_definitions = spawner.spawn_definitions
		planner.content = spawner.content
		planner._generator = world._generator
		for spec: MapSpec in world._generator.map_specs():
			if planner.content.budget_of(spec.node_id, MapContent.ENEMY) <= 0:
				continue
			planner._active_map = spec
			planner._supply_guards_by_chunk.clear()
			planner._plan_supply_guards()
			var counts: Dictionary = {}
			for post: Vector2i in supply_posts(world._generator, spec):
				counts[post] = 0
			for group: Array in planner._supply_guards_by_chunk.values():
				for slot: Dictionary in group:
					counts[slot["post"]] += 1
			for post: Vector2i in counts:
				var candidates: int = eligible_guard_tiles(world._generator, planner, spec, post)
				check(counts[post] >= 0 and counts[post] <= mini(3, candidates), "seed_%d_room_%d_supply_%s_only_uses_eligible_guard_slots" % [seed_value, spec.node_id, post])
		planner.free()
	world.queue_free()
	await process_frame
	print("SUPPLY_GUARDS: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
