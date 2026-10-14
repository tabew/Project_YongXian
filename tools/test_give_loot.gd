extends SceneTree

## 真正死亡才二选一掉一件；覆盖实际 E 拾取、返图保存与背包模型。
const GIVE_SCENE: PackedScene = preload("res://scenes/monsters/give_monster.tscn")
const GIVE_DATA: MonsterSpawnData = preload("res://resources/monsters/give_spawn_data.tres")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)


func _loot(parent: Node) -> Array[GroundPickup]:
	var result: Array[GroundPickup] = []
	for child: Node in parent.get_children():
		if child is GroundPickup and not child.is_queued_for_deletion():
			result.append(child)
	return result


func _run() -> void:
	var items: Node = root.get_node("ItemListGlobal")
	# 阈值两侧与端点必须覆盖整个抽样范围，没有空掉落或双掉落区间。
	_check(GiveMonster.death_loot_for_roll(0.0).id == 4, "zero_roll_is_fur")
	_check(GiveMonster.death_loot_for_roll(0.699999).id == 4, "fur_interval_ends_below_70_percent")
	_check(GiveMonster.death_loot_for_roll(0.70).id == 3, "hide_interval_starts_at_70_percent")
	_check(GiveMonster.death_loot_for_roll(1.0).id == 3, "maximum_roll_still_drops_hide")
	for item_id: int in [4, 3]:
		var data: IngredientData = items.create(item_id) as IngredientData
		_check(data != null and data.id == item_id and data.texture != null, "registered_loot_has_data_and_icon")
		if data != null:
			var model: ItemModel = data.create_model()
			_check(model != null and model.data.id == item_id, "registered_loot_has_inventory_drag_model")
			if model != null:
				model.free()
	_check(items.templates.back().id == items.POTION_ID_STRAT, "potion_template_stays_last")

	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 24681357)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("GameHUD/BagUi").hide()
	world.get_node("GameHUD/Alchemy").hide()
	var allowed: Array[int] = [Biome.Kind.SAVANNA, Biome.Kind.GRASSLAND, Biome.Kind.FOREST, Biome.Kind.TROPICAL_RAINFOREST]
	_check(GIVE_DATA.allowed_biomes == allowed, "give_keeps_exact_four_requested_biomes")
	var pool: Array[int] = []
	for definition: MonsterSpawnData in world.monster_spawner.spawn_definitions:
		for biome_id: int in definition.allowed_biomes:
			if not pool.has(biome_id):
				pool.append(biome_id)
	pool.sort()
	_check(world._generator.config.combat_biomes == PackedInt32Array(pool), "game_uses_all_registered_monster_habitats")
	for spec: MapSpec in world._generator.map_specs():
		if world.monster_spawner.content.budget_of(spec.node_id, MapContent.ENEMY) > 0:
			_check(spec.biome_id in pool, "actual_combat_region_supports_registered_monster_pool")
		for entry: Dictionary in GroundMaterials.plan(world._generator, spec):
			_check(entry["item_id"] not in [4, 3], "exclusive_death_loot_never_spawns_as_ground_material")

	var original_position: Vector2 = world.player.global_position
	var original_tile: Vector2i = WorldGenerator.world_to_tile(original_position)
	var monster := world.monster_spawner.spawn_monster(GIVE_DATA, original_tile) as GiveMonster
	monster.global_position = original_position
	_check(_loot(world.monster_spawner).is_empty(), "alive_monster_drops_nothing")
	monster.take_damage(99)
	_check(_loot(world.monster_spawner).is_empty(), "nonlethal_damage_drops_nothing")
	monster.take_damage(1)
	var pickups: Array[GroundPickup] = _loot(world.monster_spawner)
	_check(pickups.size() == 1, "lethal_damage_drops_exactly_one_item")
	if pickups.size() != 1:
		world.queue_free()
		await process_frame
		quit(1)
		return
	var drop: GroundPickup = pickups[0]
	_check(drop.data.id in [4, 3] and drop.amount == 1, "drop_is_one_requested_material")
	_check(drop.global_position.is_equal_approx(original_position), "drop_uses_death_position")
	monster.kill()
	_check(_loot(world.monster_spawner).size() == 1, "repeated_kill_does_not_duplicate_loot")
	world._refresh_pickup()
	_check(world._nearby_pickup == drop, "new_death_drop_is_immediately_targetable")
	world._enter_map(2)
	_check(is_instance_valid(drop) and not drop.is_visible_in_tree(), "leaving_region_preserves_and_hides_loot")
	world._enter_map(0)
	_check(drop.is_visible_in_tree() and drop.global_position.is_equal_approx(original_position), "return_restores_same_loot_and_position")
	_check(world.monster_spawner.spawn_monster(GIVE_DATA, original_tile) == null, "dead_spawn_cannot_return_and_drop_again")
	world.player.global_position = drop.global_position
	var item_id: int = drop.data.id
	var before: int = world.player.inventory.get_count(item_id)
	var pickup_event := InputEventAction.new()
	pickup_event.action = &"pickup_item"
	pickup_event.pressed = true
	world._unhandled_input(pickup_event)
	_check(world.player.inventory.get_count(item_id) == before + 1, "pickup_action_adds_one_drop_to_inventory")
	_check(not drop.collect(world.player), "same_drop_cannot_be_collected_twice")
	world._enter_map(2)
	world._enter_map(0)
	_check(_loot(world.monster_spawner).is_empty(), "return_does_not_recreate_collected_monster_loot")

	# 多只真正死亡的怪物各自独立掉一件；正常卸载不掉任何东西。
	var holder := Node2D.new()
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(holder)
	var unloaded := GIVE_SCENE.instantiate() as GiveMonster
	holder.add_child(unloaded)
	unloaded.queue_free()
	_check(_loot(holder).is_empty(), "unloading_alive_give_drops_nothing")
	MapRng.shared(MapRng.Stream.LOOT).seed = 20260817
	for index: int in 100:
		var actor := GIVE_SCENE.instantiate() as GiveMonster
		holder.add_child(actor)
		actor.global_position = Vector2(index * 16, 0)
		actor.take_damage(100)
		actor.kill()
		_check(_loot(holder).size() == index + 1, "each_real_death_produces_one_and_only_one_drop")
	var fur_count: int = 0
	var hide_count: int = 0
	for pickup: GroundPickup in _loot(holder):
		fur_count += int(pickup.data.id == 4)
		hide_count += int(pickup.data.id == 3)
	_check(fur_count + hide_count == 100 and fur_count > 0 and hide_count > 0, "seeded_deaths_cover_both_exclusive_outcomes")
	print("GIVE_LOOT_SAMPLE fur=%d hide=%d total=%d" % [fur_count, hide_count, fur_count + hide_count])
	holder.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	print("GIVE_LOOT: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
