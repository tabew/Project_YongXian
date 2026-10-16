extends SceneTree

class SwampGenerator extends WorldGenerator:
	func is_walkable(_tile: Vector2i) -> bool:
		return true
	func sample_biome(_tile: Vector2i) -> int:
		return Biome.Kind.SWAMP

const SHI: MonsterSpawnData = preload("res://resources/monsters/shi_spawn_data.tres")
const PLAYER: PackedScene = preload("res://scenes/game/player.tscn")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func fixture() -> Dictionary:
	var holder := Node2D.new()
	root.add_child(holder)
	var player := PLAYER.instantiate() as PlayerCharacter
	player.inventory = Inventory.new()
	holder.add_child(player)
	player.global_position = Vector2(1000, 1000)
	player.set_physics_process(false)
	var manager := ChunkManager.new()
	manager.process_mode = Node.PROCESS_MODE_DISABLED
	holder.add_child(manager)
	var spawner := MonsterSpawner.new()
	spawner.set_process(false)
	spawner.spawn_definitions = [SHI]
	holder.add_child(spawner)
	var source := SwampGenerator.new(18473)
	spawner.setup(source, manager, player)
	return {"holder": holder, "player": player, "source": source, "spawner": spawner}

func spawn(f: Dictionary, tile: Vector2i) -> ShiMonster:
	var actor := f.spawner.spawn_monster(SHI, tile) as ShiMonster
	actor.set_physics_process(false)
	return actor

func cleanup(holder: Node) -> void:
	holder.get_parent().remove_child(holder)
	holder.queue_free()
	await process_frame

func _run() -> void:
	Engine.max_fps = 120
	root.size = Vector2i(1280, 720)
	var items: Node = root.get_node("ItemListGlobal")
	check(items.get_template(9).name == "凝液", "liquid_registered")
	check(items.get_template(10).name == "粘性球", "ball_registered")
	check(items.templates.back().id == 300, "potion_last")
	for id: int in [9, 10]:
		var model: ItemModel = items.create(id).create_model()
		check(model != null and model.data.id == id, "loot_models_exist")
		if model != null:
			model.free()
	var table: MonsterLootTable = load("res://resources/monsters/shi_loot_table.tres")
	check(table.choose_for_roll(0).id == 9 and table.choose_for_roll(0.7999).id == 9, "80_percent_liquid_interval")
	check(table.choose_for_roll(0.8).id == 10 and table.choose_for_roll(1).id == 10, "20_percent_ball_interval")
	check(SHI.allowed_biomes == [Biome.Kind.SWAMP] and SHI.max_per_chunk >= 3, "swamp_pack_definition")

	var f: Dictionary = fixture()
	var actor: ShiMonster = spawn(f, Vector2i(2, 2))
	var stone := GroundPickup.new()
	var data: IngredientData = items.create(2)
	stone.bind(data, 3, f.source)
	f.holder.add_child(stone)
	stone.global_position = actor.global_position + Vector2(4, 0)
	var stick := GroundPickup.new()
	stick.bind(items.create(1), 2, f.source)
	f.holder.add_child(stick)
	stick.global_position = actor.global_position + Vector2(-4, 0)
	check(actor.swallow_nearby_items() == 2, "patrol_swallows_actual_world_items")
	check(actor.swallowed_items().size() == 2 and stone.data == data and stone.amount == 3, "swallow_preserves_original_node_data_and_quantity")
	check(not stone.collect(f.player) and not stone.can_be_thrown(), "swallowed_item_is_reserved")
	f.spawner.clear_monsters()
	actor = spawn(f, Vector2i(2, 2))
	check(actor.swallowed_items().size() == 2 and actor.swallowed_items()[0] == stone, "unload_replay_restores_same_belly_objects")
	var death_point := Vector2(100, 88)
	actor.global_position = death_point
	actor.kill()
	check(stone.global_position == death_point and stick.global_position == death_point, "swallowed_items_drop_at_death_not_old_positions")
	check(stone.data == data and stone.amount == 3 and stone.is_available_for_pickup(), "released_items_keep_exact_original_state")
	check(stone.collect(f.player) and f.player.inventory.get_count(2) == 3, "released_stone_stack_can_enter_inventory")
	check(f.spawner.spawn_monster(SHI, Vector2i(2, 2)) == null, "dead_swallow_owner_does_not_respawn")
	await cleanup(f.holder)

	f = fixture()
	actor = spawn(f, Vector2i(2, 2))
	actor.play_monster_animation(&"Move")
	actor._physics_process(ShiMonster.HOP_DURATION)
	check(actor._hop_count == 1 and actor._hop_rest == 0, "first_low_hop_without_rest")
	actor.play_monster_animation(&"Move")
	actor._physics_process(ShiMonster.HOP_DURATION)
	check(actor._hop_rest == 1.0 and actor.monster_animation_state() == &"Rest", "second_hop_enters_exact_one_second_rest")
	check(actor.movement_speed() == 0, "rest_has_no_walking")
	actor._physics_process(0.5)
	check(is_equal_approx(actor._hop_rest, 0.5), "rest_half_second_remains")
	actor._physics_process(0.5)
	check(actor.movement_speed() > 0, "walking_resumes_after_one_second")
	var machine := actor.animation_tree.tree_root as AnimationNodeStateMachine
	for state: StringName in [&"Idle", &"Hop", &"Rest", &"Form", &"Spin", &"Shoot", &"Hurt", &"Death"]:
		check(machine.has_node(state), "all_slime_states_connected_to_animationtree")
	for index: int in machine.get_transition_count():
		check(machine.get_transition_from(index) != &"Death", "death_state_has_no_outgoing_transition")
	await cleanup(f.holder)

	f = fixture()
	var posted: Array[ShiMonster] = [spawn(f, Vector2i(2, 2)), spawn(f, Vector2i(3, 2)), spawn(f, Vector2i(2, 3))]
	posted[0].set_supply_post(WorldGenerator.tile_to_world(Vector2i(2, 2)))
	posted[1].set_supply_post(WorldGenerator.tile_to_world(Vector2i(3, 2)))
	posted[2].set_supply_post(posted[0].supply_post)
	check(not posted[0].nearby_partners().has(posted[1]) and posted[0].nearby_partners().has(posted[2]), "supply_guards_only_group_with_their_own_post")
	posted[1].set_supply_post(posted[0].supply_post)
	check(posted[0].nearby_partners().size() == 2, "same_supply_post_keeps_normal_group_formation")
	var leader: ShiMonster = posted[0]
	f.player.global_position = leader.global_position + Vector2(7.0 * WorldGenerator.TILE_SIZE, 0)
	check(leader.attack.perform_attack(leader, f.player) and leader.is_group_leader(), "same_post_supply_guards_can_form_group")
	leader.global_position += Vector2(2.0 * WorldGenerator.TILE_SIZE, 0)
	f.player.global_position = leader.global_position + Vector2(9.0 * WorldGenerator.TILE_SIZE, 0)
	leader.blackboard.state = EnemyState.State.ATTACK
	leader.brain.tick(0.01)
	check(leader.brain.is_returning_to_supply_post() and not leader.attack.is_busy(), "group_leader_cancels_attack_and_returns_when_player_far")
	leader.global_position += Vector2(8, 0)
	leader._physics_process(0.016)
	check(posted[1].global_position == leader.global_position and posted[2].global_position == leader.global_position, "inactive_group_members_follow_leader_during_return")
	await cleanup(f.holder)

	f = fixture()
	var trio: Array[ShiMonster] = [spawn(f, Vector2i(2, 2)), spawn(f, Vector2i(3, 2)), spawn(f, Vector2i(2, 3))]
	actor = trio[0]
	f.player.global_position = actor.global_position + Vector2(128, 0)
	var carried := GroundPickup.new()
	carried.bind(items.create(1), 4, f.source)
	f.holder.add_child(carried)
	carried.global_position = trio[1].global_position
	check(trio[1].swallow_nearby_items() == 1, "future_group_member_swallows_original_stack")
	check(actor.attack.perform_attack(actor, f.player), "exact_three_form_group")
	check(actor.is_group_leader() and trio[1].is_group_member() and not trio[1].visible, "three_original_identities_one_visible_group")
	check(actor.get_node("NameLabel").text == "团团史", "group_name_changes")
	check(actor.get_node("Health").max_health == 180, "group_health_preserves_three_original_lives")
	var impl := actor.attack as ShiMonsterAttack
	impl._form_remaining = 0.0
	impl.update(actor, 2.01)
	check(impl._shots == [1, 1, 1], "each_member_fires_once_per_full_rotation")
	check(actor.movement_speed() == 24.0, "group_slow_movement")
	var projectile := ShiSlimeProjectile.new()
	f.holder.add_child(projectile)
	projectile.launch(actor, f.player, actor.global_position)
	projectile.set_physics_process(false)
	projectile._physics_process(1.0)
	check(f.player.health == 95.0, "actual_slime_projectile_damage_is_five_points")
	projectile._physics_process(1.0)
	check(f.player.health == 95.0, "one_projectile_cannot_damage_twice")
	# 真碰撞箱接触才伤害，并限制持续重叠不能每帧扣3血。
	f.player.global_position = actor.global_position
	await physics_frame
	await physics_frame
	var before: float = f.player.health
	impl._contact_remaining = 0.0
	impl.update(actor, 0.01)
	check(f.player.health == before - 30.0, "group_collision_deals_thirty_damage")
	var after: float = f.player.health
	impl.update(actor, 0.01)
	check(f.player.health == after, "contact_damage_not_every_frame")
	var origin_tiles: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3)]
	var group_death_point: Vector2 = actor.global_position
	actor.kill()
	check(carried.global_position == group_death_point and carried.amount == 4 and carried.is_available_for_pickup(), "group_death_releases_hidden_member_original_items_at_group_corpse")
	for tile: Vector2i in origin_tiles:
		check(f.spawner.spawn_monster(SHI, tile) == null, "group_death_records_each_original_spawn")
	var drops: int = 0
	for child: Node in f.spawner.get_children():
		if child is GroundPickup and child.data.id in [9, 10]:
			drops += 1
	check(drops == 3, "group_death_drops_once_for_each_original_slime")
	await cleanup(f.holder)

	await test_actual_swamp()
	print("SHI_TEST: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_actual_swamp() -> void:
	root.get_node("GameState").set("world_seed", 18473)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	var found: bool = false
	for seed_value: int in [18473, 777, 42, 12345]:
		world.build_world(seed_value)
		for spec: MapSpec in world._generator.map_specs():
			if spec.biome_id != Biome.Kind.SWAMP or world.monster_spawner.content.budget_of(spec.node_id, MapContent.ENEMY) <= 0:
				continue
			world._enter_map(spec.node_id)
			for frame: int in 240:
				if world.chunk_manager.map_ready():
					break
				await process_frame
			var count: int = 0
			for candidate: BaseMonster in world.monster_spawner.monsters:
				if candidate is ShiMonster:
					count += 1
			check(count >= 3, "real_swamp_combat_map_generates_slime_packs")
			check(world._generator.config.combat_biomes.has(Biome.Kind.SWAMP), "world_habitat_pool_includes_swamp")
			found = true
			break
		if found:
			break
	check(found, "real_world_has_supported_swamp_combat_habitat")
	world.queue_free()
	await process_frame
	await process_frame
