extends SceneTree

## godot --headless --path . --script res://tools/test_world_population.gd
## 有图形运行并添加 -- --capture 可输出五类结构与宝箱截图。
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
	if not OS.get_cmdline_user_args().has("--runtime-only"):
		_check_plans()
	await _check_runtime()
	print("WORLD_POPULATION: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_plans() -> void:
	var signatures: Dictionary = {}
	for seed_value: int in [1, 18473, 97231, 2147483646]:
		var generator := WorldGenerator.new(seed_value)
		var replica := WorldGenerator.new(seed_value)
		var worker := WorldGenerator.new(seed_value, generator.config, generator.variant, generator.population_snapshot())
		var kinds: Dictionary = {}
		var barrel_total: int = 0
		var chest_total: int = 0
		var structure_total: int = 0
		var drop_total: int = 0
		for spec: MapSpec in generator.map_specs():
			var population: Dictionary = generator.population_for(spec.node_id)
			var chunk_coords: Vector2i = WorldGenerator.tile_to_chunk(spec.origin + Vector2i(spec.center))
			var main_chunk: ChunkData = generator.generate_chunk(chunk_coords)
			var worker_chunk: ChunkData = worker.generate_chunk(chunk_coords)
			_check(main_chunk.terrain == worker_chunk.terrain and main_chunk.route == worker_chunk.route and main_chunk.biome == worker_chunk.biome, "worker_reuses_identical_population_and_collision")
			_check(var_to_str(population) == var_to_str(replica.population_for(spec.node_id)), "population_deterministic_%d_%d" % [seed_value, spec.node_id])
			_check(population["structures"].size() >= 5, "region_has_varied_structures")
			_check(population["chests"].size() >= 2, "region_has_random_chests")
			_check(population["drops"].size() >= 10, "region_has_scattered_loot")
			var reachable: Dictionary = _reachable(generator, spec)
			var alchemy_count: int = 0
			var centers: Array[Vector2i] = []
			for structure: Dictionary in population["structures"]:
				kinds[structure["kind"]] = true
				structure_total += 1
				_check(reachable.has(structure["tile"]), "structure_center_is_reachable")
				if structure["kind"] == WorldPopulation.ALCHEMY_KIND:
					alchemy_count += 1
				centers.append(structure["tile"] as Vector2i)
			# 每张箱庭保证有一台炼金台；结构之间留出间距，不挤成一堆。
			_check(alchemy_count >= 1, "region_has_an_alchemy_station")
			_check(
				(population["structures"] as Array).size() <= WorldPopulation.STRUCTURE_MAX,
				"structure_count_stays_sparse"
			)
			# 木桶：只摆在营地/补给点/炼金台旁，占一格，旁边有可站的空地。
			for barrel: Dictionary in population["barrels"]:
				var barrel_tile: Vector2i = barrel["tile"]
				barrel_total += 1
				_check(not generator.is_walkable(barrel_tile), "barrel_blocks_its_tile")
				_check(int(barrel["item_id"]) == WorldPopulation.BARREL_ITEM, "barrel_drops_wood")
				_check(int(barrel["amount"]) >= 1, "barrel_has_loot")
				var open_neighbour: bool = false
				for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if generator.is_walkable(barrel_tile + offset):
						open_neighbour = true
				_check(open_neighbour, "barrel_is_reachable")
			var too_close: bool = false
			for left: int in centers.size():
				for right: int in range(left + 1, centers.size()):
					if centers[left].distance_to(centers[right]) < 14.0:
						too_close = true
			_check(not too_close, "structures_keep_their_distance")
			for tile: Vector2i in population["blocked"]:
				_check(not generator.is_walkable(tile), "structure_collision_is_real")
				_check(generator.sample_route(tile) == Route.Kind.NONE, "structure_does_not_block_road")
				_check(Terrain.BLOCKING[generator.sample_terrain(tile)], "terrain_and_collision_agree")
			for chest: Dictionary in population["chests"]:
				chest_total += 1
				_check(reachable.has(chest["tile"]), "chest_is_reachable")
				for entry: Dictionary in chest["loot"]:
					_check(reachable.has(entry["tile"]), "chest_drop_is_reachable")
					_check(entry["amount"] > 0 and entry["item_id"] in WorldPopulation.LOOT_POOL, "chest_has_valid_loot")
			for entry: Dictionary in population["drops"]:
				drop_total += 1
				_check(reachable.has(entry["tile"]), "scattered_loot_is_reachable")
			for entry: Dictionary in GroundMaterials.plan(generator, spec):
				var overlaps: bool = false
				for reserved: Rect2i in population["reserved"]:
					overlaps = overlaps or reserved.has_point(entry["tile"])
				_check(not overlaps, "original_material_avoids_population")
			for link: Dictionary in generator.gate_links(spec.node_id):
				_check(reachable.has(link["point"]), "gates_remain_reachable")
		_check(kinds.size() == WorldPopulation.KINDS.size(), "all_five_structure_types_spawn")
		_check(MapValidator.validate(generator).is_empty(), "world_constraints_remain_valid")
		signatures[var_to_str(generator.population_for(0))] = true
		_check(barrel_total > 0, "world_has_wooden_barrels")
		print("POPULATION_SAMPLE seed=%d structures=%d barrels=%d chests=%d drops=%d" % [
			seed_value, structure_total, barrel_total, chest_total, drop_total])
	_check(signatures.size() == 4, "different_seeds_change_population")


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
			if not visited.has(next) and spec.contains_local(local.x, local.y) and generator.is_walkable(next):
				visited[next] = true
				queue.append(next)
	return visited


func _children_of_type(parent: Node, type_name: String) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in parent.get_children():
		if child.is_queued_for_deletion():
			continue
		if (type_name == "chest" and child is WorldChest) or (type_name == "pickup" and child is GroundPickup):
			result.append(child)
	return result


func _press_e(world: Node) -> void:
	var event := InputEventAction.new()
	event.action = &"pickup_item"
	event.pressed = true
	world._unhandled_input(event)


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
	var holder: Node2D = world._map_entity_root(0)
	var chests: Array[Node] = _children_of_type(holder, "chest")
	_check(chests.size() >= 2, "actual_world_instantiates_chests")
	if chests.is_empty():
		world.queue_free()
		await process_frame
		return
	var chest: WorldChest = chests[0] as WorldChest
	world.player.global_position = chest.global_position
	world._refresh_pickup()
	_check(world._nearby_chest == chest, "nearest_chest_is_targeted")
	_check(world.hud.get_node("PickupHint").text.contains("打开"), "hud_explains_open_action")
	world.get_node("GameHUD/BagUi").show()
	_press_e(world)
	_check(not chest.opened, "inventory_blocks_opening")
	world.get_node("GameHUD/BagUi").hide()
	world.get_node("GameHUD/Alchemy").show()
	_press_e(world)
	_check(not chest.opened, "alchemy_blocks_opening")
	world.get_node("GameHUD/Alchemy").hide()
	var before: int = _children_of_type(holder, "pickup").size()
	_press_e(world)
	_check(chest.opened, "e_opens_chest")
	_check(_children_of_type(holder, "pickup").size() == before + chest.loot.size(), "opening_creates_exact_loot_count")
	_check(not chest.open(), "chest_cannot_open_twice")
	for child: Node in _children_of_type(holder, "pickup"):
		var sprite: Sprite2D = child.get_node("Sprite2D") as Sprite2D
		var drawn_size: float = maxf(sprite.texture.get_width() * sprite.scale.x, sprite.texture.get_height() * sprite.scale.y)
		_check(drawn_size <= 16.001, "world_loot_icons_fit_one_tile size=%.9f" % drawn_size)
	var target: GroundPickup = null
	var loot_tile: Vector2i = chest.loot[0]["tile"]
	for child: Node in _children_of_type(holder, "pickup"):
		if WorldGenerator.world_to_tile(child.global_position) == loot_tile:
			target = child as GroundPickup
	_check(target != null, "chest_loot_exists_at_planned_tile")
	if target != null:
		world.player.global_position = target.global_position
		var item_id: int = target.data.id
		var amount: int = target.amount
		var inventory_before: int = world.player.inventory.get_count(item_id)
		_press_e(world)
		_check(world.player.inventory.get_count(item_id) == inventory_before + amount, "e_collects_chest_loot_into_inventory")
		_check(not target.collect(world.player), "loot_cannot_be_collected_twice")
	await process_frame
	var count_after_pickup: int = _children_of_type(holder, "pickup").size()
	world._enter_map(2)
	_check(not holder.is_visible_in_tree() and not holder.can_process(), "leaving_hides_and_pauses_population")
	_check(not (chests[1] as WorldChest).open(), "hidden_chest_cannot_open")
	world._enter_map(0)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	_check(chest.opened and _children_of_type(holder, "chest").size() == chests.size(), "return_preserves_chest_state_without_respawn")
	_check(_children_of_type(holder, "pickup").size() == count_after_pickup, "return_preserves_collected_loot_state")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await _capture(world, holder, chest)
	world.build_world(97231)
	_check(world._population_maps.size() == 1, "new_world_clears_visited_population_flags")
	_check(_children_of_type(world._map_entity_root(0), "chest").all(func(item: Node) -> bool: return not item.opened), "new_world_chests_start_closed")
	world.queue_free()
	await process_frame
	await process_frame


func _capture(world: Node, holder: Node2D, chest: WorldChest) -> void:
	world.hud.get_node("StatsLabel").hide()
	world.hud.get_node("ToastLabel").modulate.a = 0.0
	var captured: Dictionary = {}
	for child: Node in holder.get_children():
		if not child is WorldStructure or captured.has(child.kind):
			continue
		captured[child.kind] = true
		world.player.global_position = child.global_position + Vector2(0, 56)
		world.camera.reset_smoothing()
		world.camera.force_update_scroll()
		world.chunk_manager.prepare_visible()
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot: Image = root.get_texture().get_image()
		_check(screenshot.save_png("res://.godot/population-%s.png" % child.kind) == OK, "structure_screenshot_saved")
	var unopened: WorldChest = _children_of_type(holder, "chest")[1] as WorldChest
	world.player.global_position = unopened.global_position + Vector2(0, 24)
	world.camera.reset_smoothing()
	world.camera.force_update_scroll()
	world.chunk_manager.prepare_visible()
	world._refresh_pickup()
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/population-chest.png") == OK, "chest_screenshot_saved")
