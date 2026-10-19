extends SceneTree

const SEEDS: Array[int] = [1, 18473, 2147483646]
const FINAL_BOSS_SPAWN: MonsterSpawnData = preload("res://resources/monsters/final_boss_spawn_data.tres")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func wait_room(world: Node2D) -> void:
	for frame: int in 900:
		for monster: BaseMonster in world.monster_spawner.monsters:
			if not monster is FinalBoss:
				monster.process_mode = Node.PROCESS_MODE_DISABLED
		if world.chunk_manager.map_ready() and world.monster_spawner.get_pending_spawn_count() == 0:
			return
		await process_frame
	check(false, "room_and_monsters_finish_loading")


func bosses_in(spawner: MonsterSpawner) -> Array[FinalBoss]:
	var bosses: Array[FinalBoss] = []
	for monster: BaseMonster in spawner.monsters:
		if monster is FinalBoss:
			bosses.append(monster as FinalBoss)
	return bosses


func pause_ordinary_monsters(spawner: MonsterSpawner) -> void:
	spawner.set_process(false)
	for monster: BaseMonster in spawner.monsters:
		if not monster is FinalBoss:
			monster.process_mode = Node.PROCESS_MODE_DISABLED


func hit_boss(boss: FinalBoss, amount: float) -> bool:
	var hit := CombatHit.new()
	hit.source = boss.player
	hit.damage = amount
	hit.position = boss.global_position
	return (boss.get_node("Hurtbox") as CombatHurtbox).receive_hit(hit)


func _test_phases(world: Node2D, boss: FinalBoss, spec: MapSpec) -> void:
	var spawner: MonsterSpawner = world.monster_spawner
	var health := boss.get_node("Health") as HealthComponent
	var original_tile: Vector2i = boss.original_spawn_tile
	var boss_spawn_id: String = spawner._spawn_id(FINAL_BOSS_SPAWN, original_tile)
	var deaths: Dictionary = {"count": 0}
	health.died.connect(func(_hit: CombatHit) -> void: deaths["count"] += 1)
	check(hit_boss(boss, FinalBoss.PHASE_HEALTH + 1000.0), "first_phase_accepts_lethal_hit")
	check(boss.phase == 2 and health.current_health == 3000.0 and health.max_health == 3000.0, "first_transition_refills_second_phase")
	check(boss.boss_hud.health_bar.value == 3000.0 and boss.boss_hud.phase_label.text == "2 / 3", "second_phase_bar_and_label_refresh")
	check(health.invulnerable and deaths["count"] == 0 and not boss.is_queued_for_deletion(), "first_transition_is_not_death")
	check(not hit_boss(boss, 9000.0), "weapons_cannot_damage_first_transition")
	check(Buffs.hurt_entity(boss, 9000.0) == 0.0, "effects_cannot_damage_first_transition")
	boss.apply_chain_damage(9000.0, world.player)
	boss.kill()
	check(boss.phase == 2 and health.current_health == 3000.0 and not spawner._defeated_spawn_ids.has(boss_spawn_id), "chain_and_debug_kill_cannot_bypass_invulnerability")
	await create_timer(3.8, false).timeout
	check(health.invulnerable and not hit_boss(boss, 1.0), "first_transition_still_immune_before_four_seconds")
	await create_timer(0.4, false).timeout
	check(not health.invulnerable and health.current_health == 3000.0, "first_transition_ends_after_four_seconds")

	check(hit_boss(boss, 10000.0), "second_phase_accepts_lethal_hit")
	check(boss.phase == 3 and health.current_health == 3000.0 and health.max_health == 3000.0, "second_transition_refills_third_phase")
	check(boss.boss_hud.health_bar.value == 3000.0 and boss.boss_hud.phase_label.text == "3 / 3", "third_phase_bar_and_label_refresh")
	check(health.invulnerable and deaths["count"] == 0 and not boss.is_queued_for_deletion(), "second_transition_is_not_death")
	check(not hit_boss(boss, 9000.0) and health.current_health == 3000.0, "second_transition_blocks_overkill")
	await create_timer(3.8, false).timeout
	check(health.invulnerable and Buffs.hurt_entity(boss, 1.0) == 0.0, "second_transition_still_immune_before_four_seconds")
	await create_timer(0.4, false).timeout
	check(not health.invulnerable, "second_transition_ends_after_four_seconds")

	check(hit_boss(boss, 10000.0), "third_phase_accepts_final_hit")
	check(deaths["count"] == 1 and boss.is_queued_for_deletion(), "boss_dies_only_after_third_phase")
	await process_frame
	await process_frame
	check(bosses_in(spawner).is_empty() and spawner._defeated_spawn_ids.has(boss_spawn_id), "final_death_records_boss_spawn_identity")
	check(not bool(world.hud.get("_boss_visible")), "boss_death_restores_standard_hud_layout")
	world._enter_map(0)
	world._enter_map(spec.node_id, -1, spec.west_gate_y)
	await wait_room(world)
	check(bosses_in(spawner).is_empty() and spawner._defeated_spawn_ids.has(boss_spawn_id) and not bool(world.hud.get("_boss_visible")), "dead_boss_does_not_respawn_or_reserve_hud_on_reentry")
	world.build_world(world._generator.world_seed)
	world._enter_map(spec.node_id, -1, spec.west_gate_y)
	await wait_room(world)
	var restored_bosses: Array[FinalBoss] = bosses_in(spawner)
	check(restored_bosses.size() == 1 and not spawner._defeated_spawn_ids.has(boss_spawn_id) and bool(world.hud.get("_boss_visible")), "new_run_restores_single_boss_and_hud")
	if restored_bosses.size() == 1:
		var restored: FinalBoss = restored_bosses[0]
		check(restored.original_spawn_tile == original_tile and restored.phase == 1, "new_run_restores_original_boss_slot_and_phase")
		check((restored.get_node("Health") as HealthComponent).current_health == 3000.0, "new_run_restores_first_phase_health")


func _run() -> void:
	Engine.max_fps = 120
	root.size = Vector2i(1280, 720)
	for seed_value: int in SEEDS:
		root.get_node("GameState").set("world_seed", seed_value)
		var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
		root.add_child(world)
		current_scene = world
		world.set_process(false)
		world.player.set_physics_process(false)
		var spec: MapSpec = world._generator.map_spec(world._generator.run.final_node())
		check(spec != null and world._generator.run.type_of(spec.node_id) == RoomType.Kind.BOSS, "final_node_is_boss_room")
		check(world.monster_spawner.content.budget_of(spec.node_id, MapContent.BOSS) == 1 and world.monster_spawner.content.budget_of(spec.node_id, MapContent.ENEMY) > 0, "final_node_has_boss_and_ordinary_enemy_budgets")
		if seed_value == SEEDS[1]:
			world._combat_entry_count = 6
		world._enter_map(spec.node_id, -1, spec.west_gate_y)
		await wait_room(world)
		var spawner: MonsterSpawner = world.monster_spawner
		var bosses: Array[FinalBoss] = bosses_in(spawner)
		check(bosses.size() == 1, "exactly_one_fixed_boss_spawns_for_seed_%d" % seed_value)
		check(spawner.monsters.size() > bosses.size(), "ordinary_monsters_coexist_with_boss_for_seed_%d" % seed_value)
		if bosses.size() == 1:
			var boss: FinalBoss = bosses[0]
			pause_ordinary_monsters(spawner)
			boss.set_physics_process(false)
			var health := boss.get_node("Health") as HealthComponent
			var tile: Vector2i = boss.original_spawn_tile
			check(spec.contains_local(tile.x - spec.origin.x, tile.y - spec.origin.y) and world._generator.is_walkable(tile), "boss_has_walkable_slot_inside_final_room")
			for ordinary: BaseMonster in spawner.monsters:
				if ordinary != boss:
					check(ordinary.original_spawn_tile != tile, "ordinary_monster_never_uses_reserved_boss_tile")
			check(boss.global_position == WorldGenerator.tile_to_world(tile), "boss_starts_at_deterministic_slot")
			check(boss.boss_hud.name_label.text == FinalBoss.BOSS_NAME and boss.attack == null and FinalBoss.NORMAL_INTERVAL == 5.0, "exact_name_and_independent_timed_attack_controller")
			check(not (boss.get_node("NameLabel") as Label).visible and not boss.health_bar.visible, "world_space_boss_labels_are_hidden")
			check(boss.boss_hud.health_bar.size.x >= 500.0 and boss.boss_hud.health_bar.size.y >= 18.0 and boss.boss_hud.health_bar.get_global_rect().end.y < 80.0, "large_health_bar_stays_at_screen_top")
			var boss_layer := boss.boss_hud.get_parent() as CanvasLayer
			var game_layer := world.get_node("GameHUD") as CanvasLayer
			check(boss_layer != null and boss_layer.layer > game_layer.layer and bool(world.hud.get("_boss_visible")), "boss_hud_draws_above_world_and_standard_hud")
			check(boss.brain == null, "stationary_boss_does_not_run_chase_pathfinding")
			var wait_before: float = boss._normal_wait
			boss._physics_process(5.1)
			check(not boss._engaged and boss.attack_state == FinalBoss.AttackState.WAIT and boss._normal_wait == wait_before, "offscreen_entrance_does_not_waste_boss_attacks")
			var entrance: Vector2 = world.player.global_position
			world.player.global_position = boss.global_position + Vector2(8.0 * WorldGenerator.TILE_SIZE, 0.0)
			boss._physics_process(0.1)
			check(boss._engaged and boss._normal_wait < wait_before, "approaching_boss_starts_first_attack_cooldown")
			world.player.global_position = entrance
			check(boss.phase == 1 and health.max_health == 3000.0 and health.current_health == 3000.0, "boss_starts_at_full_first_phase")
			if seed_value == SEEDS[1]:
				check(boss.difficulty_entry == 7 and boss.difficulty_multiplier == 1.0, "late_entry_does_not_scale_boss_health")
			if seed_value == SEEDS[0]:
				await _test_phases(world, boss, spec)
		world.queue_free()
		await process_frame
		await process_frame
	print("FINAL_BOSS: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
