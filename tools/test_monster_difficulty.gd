extends SceneTree

class OpenGenerator extends WorldGenerator:
	func is_walkable(_tile: Vector2i) -> bool:
		return true
	func sample_biome(_tile: Vector2i) -> int:
		return Biome.Kind.SWAMP

const PLAYER: PackedScene = preload("res://scenes/game/player.tscn")
const GIVE: PackedScene = preload("res://scenes/monsters/give_monster.tscn")
const CROC: PackedScene = preload("res://scenes/monsters/crocodile_monster.tscn")
const RABBIT: PackedScene = preload("res://scenes/monsters/shabei_monster.tscn")
const SHI: MonsterSpawnData = preload("res://resources/monsters/shi_spawn_data.tres")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _close(holder: Node) -> void:
	holder.queue_free()
	await process_frame

func _fixture(scene: PackedScene, entry: int, target_offset: Vector2) -> Dictionary:
	var holder := Node2D.new()
	root.add_child(holder)
	var player := PLAYER.instantiate() as PlayerCharacter
	player.inventory = Inventory.new()
	holder.add_child(player)
	player.set_physics_process(false)
	var monster := scene.instantiate() as BaseMonster
	holder.add_child(monster)
	monster.global_position = Vector2(8, 8)
	monster.configure(player, OpenGenerator.new(71), Vector2i.ZERO)
	monster.set_physics_process(false)
	monster.apply_difficulty(entry)
	player.global_position = monster.global_position + target_offset
	return {"holder": holder, "player": player, "monster": monster}

func _test_curve() -> void:
	var expected: Array[float] = [1.0, 1.5, 2.0, 2.4, 2.8, 3.1, 3.4]
	for index: int in expected.size():
		check(is_equal_approx(MonsterDifficulty.multiplier_for_entry(index + 1), expected[index]), "exact_cumulative_multiplier_%d" % (index + 1))
	check(MonsterDifficulty.multiplier_for_entry(0) == 1.0, "difficulty_clamps_to_first_entry")
	var previous: float = expected.back()
	var prior_increment: float = 0.3
	for entry: int in range(8, 101):
		var multiplier: float = MonsterDifficulty.multiplier_for_entry(entry)
		var increment: float = multiplier - previous
		check(increment > 0.0 and increment < prior_increment, "positive_diminishing_log_increment_%d" % entry)
		previous = multiplier
		prior_increment = increment

func _find_same_slot(spawner: MonsterSpawner, script_path: String, tile: Vector2i) -> BaseMonster:
	for monster: BaseMonster in spawner.monsters:
		if monster.get_script().resource_path == script_path and WorldGenerator.world_to_tile(monster.global_position) == tile:
			return monster
	return null

func _wait_room(world: Node2D) -> void:
	for frame: int in 480:
		if world.chunk_manager.map_ready() and world.monster_spawner.get_pending_spawn_count() == 0:
			return
		await process_frame
	check(false, "all_room_monsters_finished_spawning")

func _test_room_entries() -> void:
	root.get_node("GameState").set("world_seed", 18473)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	var spawner: MonsterSpawner = world.monster_spawner
	check(world._combat_entry_count == 0 and spawner.monsters.is_empty(), "starting_safe_room_does_not_advance")
	var combat: MapSpec = null
	var next_combat: MapSpec = null
	for spec: MapSpec in world._generator.map_specs():
		if spawner.content.budget_of(spec.node_id, MapContent.ENEMY) > 0:
			if combat == null and spec.biome_id == Biome.Kind.SWAMP:
				combat = spec
			elif next_combat == null and spec.biome_id == Biome.Kind.TROPICAL_RAINFOREST:
				next_combat = spec
	check(combat != null and next_combat != null, "seed_has_two_distinct_enemy_rooms")
	if combat == null or next_combat == null:
		await _close(world)
		return
	world._enter_map(combat.node_id, -1, combat.west_gate_y)
	check(world._combat_entry_count == 1 and not spawner.monsters.is_empty(), "first_combat_entry_has_immediate_gate_encounter")
	var first: BaseMonster = spawner.monsters[0]
	var first_hp: float = (first.get_node("Health") as HealthComponent).max_health
	var first_tile: Vector2i = WorldGenerator.world_to_tile(first.global_position)
	var first_script: String = first.get_script().resource_path
	check(first.difficulty_entry == 1 and first.difficulty_multiplier == 1.0, "initial_monster_has_individual_baseline")
	world._enter_map(0)
	check(world._combat_entry_count == 1, "safe_room_does_not_increase_difficulty")
	world._enter_map(combat.node_id, -1, combat.west_gate_y)
	var second: BaseMonster = _find_same_slot(spawner, first_script, first_tile)
	check(world._combat_entry_count == 2 and second != null, "return_to_same_combat_room_advances_entry")
	if second != null:
		var second_health := second.get_node("Health") as HealthComponent
		check(is_equal_approx(second_health.max_health, first_hp * 1.5) and is_equal_approx(second_health.current_health, second_health.max_health), "reentered_monster_hp_is_full_and_scaled")
		check(second.difficulty_entry == 2 and is_equal_approx(second.outgoing_damage(1.0), 1.5), "second_entry_multiplier_lives_on_monster")
		second.apply_difficulty(2)
		check(is_equal_approx(second_health.max_health, first_hp * 1.5), "difficulty_cannot_stack_twice_on_one_instance")
		second.kill()
		world._enter_map(0)
		world._enter_map(combat.node_id, -1, combat.west_gate_y)
		check(world._combat_entry_count == 3 and _find_same_slot(spawner, first_script, first_tile) == null, "dead_slot_stays_empty_despite_difficulty_growth")
		await _wait_room(world)
		check(spawner.monsters.size() > 3, "interior_monsters_spawn_in_later_batches")
		for monster: BaseMonster in spawner.monsters:
			check(monster.difficulty_entry == 3 and is_equal_approx(monster.difficulty_multiplier, 2.0), "all_delayed_monsters_use_arrival_entry")
	world._enter_map(next_combat.node_id, -1, next_combat.west_gate_y)
	check(world._combat_entry_count == 4, "different_enemy_room_uses_same_run_progression")
	await _wait_room(world)
	check(not spawner.monsters.is_empty(), "second_enemy_room_has_monsters")
	for monster: BaseMonster in spawner.monsters:
		check(monster.difficulty_entry == 4 and is_equal_approx(monster.difficulty_multiplier, 2.4), "other_room_monsters_own_fourth_entry_multiplier")
	world.build_world(18473)
	check(world._combat_entry_count == 0, "new_run_same_seed_resets_difficulty")
	world._enter_map(combat.node_id, -1, combat.west_gate_y)
	var restarted: BaseMonster = _find_same_slot(spawner, first_script, first_tile)
	check(restarted != null and restarted.difficulty_entry == 1, "same_seed_new_run_restores_first_entry_monster")
	await _close(world)

func _test_damage() -> void:
	var f: Dictionary = _fixture(GIVE, 2, Vector2(128, 0))
	var stone := GroundPickup.new()
	stone.bind(load("res://resources/items/ingredients/stone.tres") as IngredientData, 1, f.monster.world_generator)
	f.holder.add_child(stone)
	stone.global_position = f.monster.global_position + Vector2(4, 0)
	check(f.monster.attack.perform_attack(f.monster, f.player), "scaled_give_throw_starts")
	check(is_equal_approx(stone._throw_damage, 1.5), "stone_captures_fractional_damage_from_throwing_monster")
	stone.set_physics_process(false)
	stone._physics_process(1.0)
	check(is_equal_approx(f.player.health, 8.5), "scaled_stone_deals_fractional_damage_on_hit")
	await _close(f.holder)

	f = _fixture(GIVE, 2, Vector2(48, 0))
	var leap := f.monster.attack as GiveMonsterAttack
	check(leap.perform_attack(f.monster, f.player), "scaled_give_leap_starts")
	leap.update(f.monster, GiveMonsterAttack.LEAP_DURATION)
	check(is_equal_approx(f.player.health, 8.5), "give_leap_uses_monster_multiplier")
	await _close(f.holder)

	f = _fixture(CROC, 2, Vector2(16, 0))
	var bite := f.monster.attack as CrocodileBiteAttack
	check(bite.perform_attack(f.monster, f.player), "scaled_crocodile_bite_starts")
	bite.update(f.monster, CrocodileBiteAttack.WINDUP + 0.01)
	check(is_equal_approx(f.player.health, 7.0), "crocodile_bite_uses_monster_multiplier")
	await _close(f.holder)

	f = _fixture(RABBIT, 4, Vector2(100, 0))
	var wave := ShabeiSoundWave.new()
	f.holder.add_child(wave)
	wave.launch(f.monster, f.player, f.monster.global_position, Vector2.RIGHT)
	wave.set_physics_process(false)
	wave._physics_process(1.0)
	check(is_equal_approx(f.player.health, 7.6), "rabbit_wave_uses_owning_monster_multiplier")
	await _close(f.holder)

	var holder := Node2D.new()
	root.add_child(holder)
	var player := PLAYER.instantiate() as PlayerCharacter
	player.inventory = Inventory.new()
	holder.add_child(player)
	player.set_physics_process(false)
	var manager := ChunkManager.new()
	manager.process_mode = Node.PROCESS_MODE_DISABLED
	holder.add_child(manager)
	var spawner := MonsterSpawner.new()
	spawner.set_process(false)
	spawner.spawn_definitions = [SHI]
	holder.add_child(spawner)
	spawner.setup(OpenGenerator.new(71), manager, player, null, 3)
	var trio: Array[ShiMonster] = []
	for tile: Vector2i in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3)]:
		var shi := spawner.spawn_monster(SHI, tile) as ShiMonster
		shi.set_physics_process(false)
		trio.append(shi)
	check(trio.size() == 3 and is_equal_approx((trio[0].get_node("Health") as HealthComponent).max_health, 120.0), "slime_spawn_hp_scales_before_grouping")
	player.global_position = trio[0].global_position + Vector2(128, 0)
	check(trio[0].attack.perform_attack(trio[0], player), "scaled_slime_group_forms")
	check(is_equal_approx((trio[0].get_node("Health") as HealthComponent).max_health, 360.0), "group_health_sums_scaled_member_health")
	var projectile := ShiSlimeProjectile.new()
	holder.add_child(projectile)
	projectile.launch(trio[0], player, trio[0].global_position)
	projectile.set_physics_process(false)
	projectile._physics_process(1.0)
	check(is_equal_approx(player.health, 9.0), "slime_projectile_uses_leader_multiplier")
	player.global_position = trio[0].global_position
	await physics_frame
	await physics_frame
	var attack := trio[0].attack as ShiMonsterAttack
	attack._form_remaining = 0.0
	attack._contact_remaining = 0.0
	attack.update(trio[0], 0.01)
	check(is_equal_approx(player.health, 3.0), "slime_group_contact_uses_leader_multiplier")
	await _close(holder)

func _run() -> void:
	Engine.max_fps = 240
	root.size = Vector2i(1280, 720)
	_test_curve()
	await _test_room_entries()
	await _test_damage()
	print("MONSTER_DIFFICULTY: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
