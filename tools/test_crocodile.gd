extends SceneTree

class SwampGenerator extends WorldGenerator:
	var spec: MapSpec = MapSpec.new()
	var blocked: Dictionary = {}
	var bridges: Dictionary = {}
	func _init(seed_value: int = 123) -> void:
		super(seed_value)
		spec.node_id = 2
		spec.biome_id = Biome.Kind.SWAMP
		spec.origin = Vector2i.ZERO
		spec.extent = Vector2i(64, 64)
	func sample_biome(_tile: Vector2i) -> int:
		return Biome.Kind.SWAMP
	func sample_terrain(tile: Vector2i) -> int:
		if blocked.has(tile):
			return Terrain.Kind.MOUNTAIN
		return Terrain.Kind.WATER if tile.x < 16 else Terrain.Kind.SWAMP
	func sample_route(tile: Vector2i) -> int:
		return Route.Kind.BRIDGE if bridges.has(tile) else Route.Kind.NONE
	func is_walkable(tile: Vector2i) -> bool:
		return not blocked.has(tile) and (tile.x >= 16 or bridges.has(tile))
	func sample_map(_tile: Vector2i) -> MapSpec:
		return spec

var _checks: int = 0
var _failures: int = 0
var _scene: PackedScene
var _definition: CrocodileSpawnData
var _loot: MonsterLootTable

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)

func _fixture(player_tile: Vector2i = Vector2i(24, 16), monster_tile: Vector2i = Vector2i(14, 16)) -> Dictionary:
	var holder := Node2D.new()
	root.add_child(holder)
	var generator := SwampGenerator.new()
	var player := (load("res://scenes/game/player.tscn") as PackedScene).instantiate() as PlayerCharacter
	player.inventory = Inventory.new()
	holder.add_child(player)
	player.global_position = WorldGenerator.tile_to_world(player_tile)
	player.active_map = generator.spec
	player.set_physics_process(false)
	var monster := _scene.instantiate() as CrocodileMonster
	holder.add_child(monster)
	monster.global_position = WorldGenerator.tile_to_world(monster_tile)
	monster.configure(player, generator, Vector2i.ZERO)
	monster.set_physics_process(false)
	return {"holder": holder, "player": player, "monster": monster, "generator": generator}

func _clean(holder: Node) -> void:
	holder.get_parent().remove_child(holder)
	holder.queue_free()
	await process_frame

func _drops(holder: Node) -> Array[GroundPickup]:
	var result: Array[GroundPickup] = []
	for child: Node in holder.get_children():
		if child is GroundPickup and not child.is_queued_for_deletion():
			result.append(child)
	return result

func _run() -> void:
	Engine.max_fps = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/monsters/crocodile_monster.tscn") as PackedScene
	_definition = load("res://resources/monsters/crocodile_spawn_data.tres") as CrocodileSpawnData
	_loot = load("res://resources/monsters/crocodile_loot_table.tres") as MonsterLootTable
	for entry: Array in [[0.0,6], [0.099999,6], [0.10,7], [0.699999,7], [0.70,8], [1.0,8]]:
		_check(_loot.choose_for_roll(entry[0]).id == entry[1], "loot_threshold_%s" % entry[0])
	var counts: Dictionary = {6:0, 7:0, 8:0}
	for index: int in 1000:
		counts[_loot.choose_for_roll((index + 0.5) / 1000.0).id] += 1
	_check(counts == {6:100,7:600,8:300}, "one_roll_covers_all_requested_loot_intervals")
	var registry: Node = root.get_node("ItemListGlobal")
	for id: int in [6,7,8]:
		var item: IngredientData = registry.create(id)
		_check(item != null and item.texture != null and item.id == id, "crocodile_item_registered_with_icon")
		var model: ItemModel = item.create_model()
		_check(model != null and model.data.id == id, "crocodile_item_has_inventory_drag_model")
		model.free()
	_check(registry.templates.back().id == 300, "potion_template_remains_last")
	var f: Dictionary = _fixture()
	_check(f.monster is BaseMonster and f.monster.brain != null and f.monster.animation_tree != null, "crocodile_uses_shared_template_ai_and_animationtree")
	_check(f.monster.death_loot == _loot, "crocodile_scene_uses_shared_death_table")
	var tree: AnimationNodeStateMachine = f.monster.animation_tree.tree_root
	for state: StringName in [&"Idle", &"Swim", &"Walk", &"Attack", &"Hurt", &"Death"]:
		_check(tree.has_node(state), "crocodile_has_real_specialized_animation_state")
	_check(not tree.has_node(&"Leap") and not tree.has_node(&"Throw"), "crocodile_tree_has_no_unimplemented_template_actions")
	for index: int in tree.get_transition_count():
		_check(tree.get_transition_from(index) != &"Death", "crocodile_death_is_terminal")
	f.monster.play_monster_animation(&"Move")
	_check(f.monster.monster_animation_state() == &"Swim", "water_movement_uses_swim_state")
	f.monster.advance_monster_animation(0.2)
	_check(f.monster.gait_phase > 0.1, "swim_animation_drives_tail_phase")
	f.monster.stop_navigation()
	_check(f.monster.monster_animation_state() == &"Idle", "swim_stops_at_idle")
	f.monster.blackboard.facing = Vector2.DOWN
	f.monster.sync_facing()
	_check(is_equal_approx(f.monster.get_node("Visual/Body").rotation, PI * 0.5), "visual_faces_movement")
	_check(is_equal_approx(f.monster.get_node("CollisionShape2D").rotation, PI), "body_shape_follows_visual_facing")
	_check(is_equal_approx(f.monster.get_node("Hurtbox/CollisionShape2D").rotation, PI), "hurt_shape_follows_visual_facing")
	_check(f.monster.get_node("Hurtbox/CollisionShape2D").shape is CapsuleShape2D, "hurtbox_covers_long_crocodile_body")
	f.monster.blackboard.facing = Vector2.RIGHT
	f.monster.sync_facing()
	_check(f.monster.ai_config.vision_distance_tiles == 10.0, "vision_is_ten_tiles")
	_check(f.monster.perception.can_see(f.player), "water_patrol_can_detect_shore_player_exactly_ten_tiles_away")
	f.player.global_position.x += 0.1
	_check(not f.monster.perception.can_see(f.player), "player_beyond_ten_tiles_is_not_detected")
	f.monster.blackboard.state = EnemyState.State.CHASE
	var swim_speed: float = f.monster.movement_speed()
	f.monster.global_position = WorldGenerator.tile_to_world(Vector2i(18,16))
	f.monster.play_monster_animation(&"Move")
	_check(f.monster.monster_animation_state() == &"Walk", "land_movement_switches_from_swim_to_walk")
	f.monster.advance_monster_animation(0.2)
	_check(f.monster.gait_phase > 0.1, "walk_animation_drives_alternating_legs")
	f.monster.stop_navigation()
	_check(f.monster.monster_animation_state() == &"Idle", "land_movement_stops_at_idle")
	_check(is_equal_approx(f.monster.movement_speed(), swim_speed * 0.60), "land_chase_speed_is_exactly_sixty_percent")
	f.monster.global_position = WorldGenerator.tile_to_world(Vector2i(14,16))
	f.generator.bridges[Vector2i(14,16)] = true
	_check(not f.monster.is_in_water() and is_equal_approx(f.monster.movement_speed(), swim_speed * 0.60), "bridge_is_land_for_speed_not_swimming_spawn")
	_check(not _definition.can_spawn_at(f.generator, Vector2i(14,16)), "bridges_are_not_crocodile_spawn_tiles")
	f.generator.bridges.clear()
	f.monster.blackboard.state = EnemyState.State.PATROL
	_check(f.monster.is_navigation_tile_allowed(Vector2i(10,16)) and not f.monster.is_navigation_tile_allowed(Vector2i(18,16)), "idle_water_patrol_cannot_take_ground_shortcuts")
	_check(f.monster.is_patrol_tile_allowed(Vector2i(10,16)) and not f.monster.is_patrol_tile_allowed(Vector2i(18,16)), "patrol_candidates_are_swamp_water_only")
	_check(_definition.can_spawn_at(f.generator, Vector2i(20,16)) and not _definition.can_spawn_at(f.generator, Vector2i(21,16)), "bank_spawn_includes_five_tiles_and_excludes_six")
	f.generator.blocked[Vector2i(18,16)] = true
	_check(not f.monster.is_visibility_tile_allowed(Vector2i(18,16)), "amphibious_vision_does_not_bypass_terrain_walls")
	f.generator.blocked.clear()
	f.player.global_position = WorldGenerator.tile_to_world(Vector2i(24,16))
	f.monster.set_physics_process(true)
	for frame: int in 240:
		await physics_frame
		if f.player.health < 100:
			break
	f.monster.set_physics_process(false)
	_check(f.monster.has_player_aggro() and f.player.health == 80, "real_shared_ai_swims_ashore_and_bites_for_twenty_damage")
	_check(not f.monster.is_in_water(), "water_chase_reaches_player_on_land")
	await _clean(f.holder)

	f = _fixture(Vector2i(40,16), Vector2i(8,16))
	var original: Vector2 = f.monster.global_position
	f.monster.set_physics_process(true)
	for frame: int in 180:
		await physics_frame
		_check(f.monster.is_in_water(), "natural_idle_patrol_remains_in_water")
	f.monster.set_physics_process(false)
	_check(f.monster.global_position.distance_to(original) > 4.0, "shared_patrol_actually_wanders_in_water")
	_check(f.monster.get_ai_state() == EnemyState.State.PATROL, "far_player_does_not_trigger_chase")
	await _clean(f.holder)

	f = _fixture(Vector2i(18,16),Vector2i(17,16))
	_check(f.monster.attack.perform_attack(f.monster,f.player), "bite_enters_attack")
	_check(f.monster.monster_animation_state() == &"Attack", "bite_uses_animationtree_attack_state")
	f.monster.advance_monster_animation(0.12)
	_check(f.monster.jaw_open > 0.5, "attack_animation_opens_crocodile_jaw")
	f.monster.attack.update(f.monster,0.18)
	_check(f.player.health == 80, "bite_hit_is_exactly_twenty_damage")
	f.monster.attack.update(f.monster,0.1)
	_check(f.player.health == 80, "one_bite_cannot_apply_damage_twice")
	f.monster.attack.update(f.monster,0.2)
	f.monster.advance_monster_animation(0.3)
	_check(not f.monster.attack.is_busy() and f.monster.monster_animation_state() == &"Idle", "bite_recovers_to_idle")
	f.player.health = 100
	f.monster.attack.perform_attack(f.monster,f.player)
	f.monster.take_damage(1)
	_check(f.monster.monster_animation_state() == &"Hurt" and not f.monster.attack.is_busy(), "shared_hurt_interrupts_bite")
	f.monster.attack.update(f.monster,0.4)
	_check(f.player.health == 100, "interrupted_bite_cannot_hit_later")
	f.monster.advance_monster_animation(0.2)
	f.monster.attack.perform_attack(f.monster,f.player)
	f.player.global_position += Vector2(64,0)
	f.monster.attack.update(f.monster,0.2)
	_check(f.player.health == 100, "bite_windup_can_be_evaded")
	await _clean(f.holder)

	f = _fixture(Vector2i(40,16),Vector2i(8,16))
	f.monster.take_damage(1)
	_check(_drops(f.holder).is_empty(), "nonlethal_hit_does_not_drop_loot")
	f.monster.take_damage(1000)
	_check(_drops(f.holder).size() == 1, "lethal_damage_drops_exactly_one_item")
	var drop: GroundPickup = _drops(f.holder)[0]
	_check(drop.data.id in [6,7,8] and drop.amount == 1, "crocodile_death_uses_its_three_item_table")
	_check(f.generator.is_walkable(WorldGenerator.world_to_tile(drop.global_position)), "underwater_death_loot_lands_on_collectible_shore")
	f.monster.kill()
	_check(_drops(f.holder).size() == 1, "duplicate_death_does_not_duplicate_drop")
	f.monster.play_monster_animation(&"Move",true)
	_check(f.monster.monster_animation_state() == &"Death", "death_animation_is_terminal")
	_check(drop.collect(f.player) and f.player.inventory.get_count(drop.data.id) == 1, "crocodile_drop_enters_inventory_once")
	await _clean(f.holder)

	await _test_spawning()
	await _test_actual_world()
	print("CROCODILE: checks=%d failures=%d" % [_checks,_failures])
	quit(0 if _failures == 0 else 1)

func _test_spawning() -> void:
	var f: Dictionary = _fixture(Vector2i(40,16),Vector2i(8,16))
	var wet: int = 0
	var dry: int = 0
	var source := RandomNumberGenerator.new()
	source.seed = 778899
	for sample: int in 1000:
		var variant: int = _definition.choose_spawn_variant(source)
		var tile: Vector2i = _definition.select_spawn_tile(f.generator,Vector2i.ZERO,source,variant,f.generator.spec)
		_check(_definition.can_spawn_variant_at(f.generator,tile,variant), "chosen_habitat_produces_valid_candidate")
		if variant == CrocodileSpawnData.BANK_VARIANT:
			dry += 1
		else:
			wet += 1
	_check(dry >= 70 and dry <= 130 and wet + dry == 1000, "ninety_ten_habitat_sampling_without_candidate_reweighting")
	print("CROCODILE_HABITAT_SAMPLE water=%d bank=%d" % [wet,dry])
	var manager := ChunkManager.new()
	var spawner := MonsterSpawner.new()
	spawner.spawn_definitions = [_definition]
	spawner.process_mode = Node.PROCESS_MODE_DISABLED
	manager.process_mode = Node.PROCESS_MODE_DISABLED
	f.holder.add_child(manager)
	f.holder.add_child(spawner)
	spawner.setup(f.generator,manager,f.player,f.generator.spec)
	spawner._on_chunk_applied(Vector2i.ZERO)
	_check(spawner.monsters.size() == 2, "generic_spawner_creates_crocodile_slots")
	var tiles: Array[Vector2i] = []
	for actor: BaseMonster in spawner.monsters:
		tiles.append(WorldGenerator.world_to_tile(actor.global_position))
		actor.kill()
	spawner.setup(f.generator,manager,f.player,f.generator.spec)
	spawner._on_chunk_applied(Vector2i.ZERO)
	_check(spawner.monsters.is_empty(), "dead_crocodile_slots_never_respawn_or_generate_replacements")
	_check(_drops(spawner).size() == 2, "each_original_crocodile_kill_drops_one")
	var fresh := SwampGenerator.new(f.generator.world_seed)
	spawner.setup(fresh,manager,f.player,fresh.spec)
	spawner._on_chunk_applied(Vector2i.ZERO)
	_check(spawner.monsters.size() == 2, "new_run_resets_crocodile_death_ledger")
	var before: int = _drops(spawner).size()
	spawner.clear_monsters()
	_check(_drops(spawner).size() == before, "unloading_live_crocodiles_does_not_create_death_loot")
	await _clean(f.holder)

func _test_actual_world() -> void:
	root.get_node("GameState").set("world_seed",18473)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	var registered: Array[StringName] = []
	for definition: MonsterSpawnData in world.monster_spawner.spawn_definitions:
		registered.append(definition.monster_id)
	_check(registered.has(&"give") and registered.has(&"crocodile"), "game_registers_give_and_crocodile_in_same_spawner")
	_check(world._generator.config.combat_biomes == PackedInt32Array([4,5,6,7,8,10,11]), "combat_biome_pool_includes_swamp_snow_and_preserves_give_habitats")
	_check(world.monster_spawner.monsters.is_empty(), "starting_cottage_remains_safe")
	var target: MapSpec = null
	for spec: MapSpec in world._generator.map_specs():
		if spec.biome_id == Biome.Kind.SWAMP and world.monster_spawner.content.budget_of(spec.node_id,MapContent.ENEMY)>0:
			target = spec
			break
	_check(target != null, "game_world_has_swamp_combat_habitat")
	if target == null:
		world.queue_free()
		await process_frame
		return
	world._enter_map(target.node_id)
	for frame: int in 240:
		if world.chunk_manager.map_ready():
			break
		await process_frame
	_check(world.chunk_manager.map_ready(), "actual_swamp_map_finishes_loading")
	var count: int = world.monster_spawner.monsters.size()
	var crocodiles: Array[BaseMonster] = []
	for actor: BaseMonster in world.monster_spawner.monsters:
		if actor is CrocodileMonster:
			crocodiles.append(actor)
			_check(_definition.can_spawn_at(world._generator,WorldGenerator.world_to_tile(actor.global_position)), "actual_swamp_actors_use_valid_crocodile_habitat")
	_check(not crocodiles.is_empty(), "actual_swamp_naturally_spawns_crocodiles")
	if not crocodiles.is_empty():
		var victim: BaseMonster = crocodiles[0]
		var tile: Vector2i = WorldGenerator.world_to_tile(victim.global_position)
		victim.kill()
		var drops: Array[GroundPickup] = _drops(world.monster_spawner)
		_check(drops.size() == 1 and drops[0].data.id in [6,7,8], "actual_swamp_death_is_single_configured_drop")
		world._enter_map(0)
		world._enter_map(target.node_id)
		for frame: int in 240:
			if world.chunk_manager.map_ready():
				break
			await process_frame
		_check(world.monster_spawner.monsters.size() == count-1, "actual_swamp_return_does_not_replace_dead_crocodile")
		for actor: BaseMonster in world.monster_spawner.monsters:
			_check(WorldGenerator.world_to_tile(actor.global_position) != tile, "actual_swamp_dead_identity_stays_absent")
		if not drops.is_empty():
			var pickup: GroundPickup = drops[0]
			_check(pickup.is_visible_in_tree(), "actual_swamp_return_restores_uncollected_drop")
			world.player.global_position = pickup.global_position
			world._refresh_pickup()
			_check(world._nearby_pickup == pickup, "actual_swamp_drop_is_immediately_e_collectible")
			_check(pickup.collect(world.player), "actual_swamp_drop_collects_into_inventory")
	print("CROCODILE_ACTUAL_WORLD seed=18473 map=%d actors=%d" % [target.node_id,count])
	world.queue_free()
	await process_frame
	await process_frame
