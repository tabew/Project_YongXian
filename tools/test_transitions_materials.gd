extends SceneTree

## godot --headless --path . --script res://tools/test_transitions_materials.gd
## 添加 -- --capture 可保存真实地形过渡与地面材料画面。
var _checks: int = 0
var _failures: int = 0
var _materials: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	Engine.max_fps = 120
	_check_edges()
	for seed_value: int in [1, 18473, 97231, 2147483646]:
		_check_plans(seed_value)
	await _check_runtime()
	print("TRANSITIONS_MATERIALS: checks=%d failures=%d materials=%d" % [_checks, _failures, _materials])
	quit(0 if _failures == 0 else 1)


func _check_edges() -> void:
	var side: int = WorldGenerator.CHUNK_SIZE + 2
	var samples := PackedByteArray()
	samples.resize(side * side)
	samples.fill(Terrain.Kind.GRASS)
	var cell := Vector2i(31, 10)
	var index: int = (cell.y + 1) * side + cell.x + 1
	_check(TerrainTransitions.edge_at(samples, cell) == TerrainTransitions.NO_BLEND, "相同地面不应产生边缘")
	samples[index + 1] = 16
	_check(TerrainTransitions.edge_at(samples, cell) == Vector2i(2, Terrain.Kind.GRASS * 19 + 16), "区块右边缘未识别邻接土路")
	samples[index - side] = 16
	_check(TerrainTransitions.edge_at(samples, cell) == Vector2i(3, Terrain.Kind.GRASS * 19 + 16), "多个邻边未合并过渡")
	samples.fill(Terrain.Kind.GRASS)
	samples[index - side + 1] = 16
	_check(TerrainTransitions.edge_at(samples, cell) == Vector2i(17, Terrain.Kind.GRASS * 19 + 16), "对角接触缺少圆角过渡")
	samples[index] = 18
	_check(TerrainTransitions.edge_at(samples, cell) == TerrainTransitions.NO_BLEND, "桥面结构不应被过渡覆盖")
	var generator := WorldGenerator.new(18473)
	var spec: MapSpec = generator.map_spec(0)
	var chunk: ChunkData = generator.generate_chunk(WorldGenerator.tile_to_chunk(spec.origin + Vector2i(spec.center)))
	var before: int = hash([chunk.terrain, chunk.route, chunk.biome])
	var halo: PackedByteArray = TerrainTransitions.halo(generator, chunk, spec)
	_check(hash([chunk.terrain, chunk.route, chunk.biome]) == before, "视觉过渡改写了地图数据")
	var origin: Vector2i = chunk.coords * WorldGenerator.CHUNK_SIZE
	var halo_ok: bool = true
	for y: int in WorldGenerator.CHUNK_SIZE:
		var tile: Vector2i = origin + Vector2i(WorldGenerator.CHUNK_SIZE, y)
		var local: Vector2i = tile - spec.origin
		if not spec.contains_local(local.x, local.y) or (spec.cottage != null and spec.cottage.bounds.has_point(local)):
			continue
		var expected: int = TerrainTransitions.display_kind(generator.sample_terrain(tile), generator.sample_route(tile))
		halo_ok = halo_ok and halo[(y + 1) * side + side - 1] == expected
	_check(halo_ok, "halo未使用跨区块的真实邻格")
	var blended_gates: int = 0
	for region: MapSpec in generator.map_specs():
		for link: Dictionary in generator.gate_links(region.node_id):
			var tile: Vector2i = link["point"] + Vector2i(0, 5)
			var base: int = RegionBiomes.ground_for(region.biome_id)
			var transition: Vector2i = TerrainTransitions.gate_at(generator, region, tile, base)
			if transition != TerrainTransitions.NO_BLEND:
				blended_gates += 1
				_check(transition.x >= 20 and transition.x <= 23, "入口渐变强度越界")
				_check(generator.sample_biome(tile) == region.biome_id, "入口过渡改变了箱庭群系")
	_check(blended_gates > 0, "不同箱庭入口未产生地面色调衔接")


func _check_plans(seed_value: int) -> void:
	var generator := WorldGenerator.new(seed_value)
	var replica := WorldGenerator.new(seed_value)
	for spec: MapSpec in generator.map_specs():
		var planned: Array[Dictionary] = GroundMaterials.plan(generator, spec)
		_check(planned == GroundMaterials.plan(replica, replica.map_spec(spec.node_id)), "材料规划不确定 seed=%d node=%d" % [seed_value, spec.node_id])
		_check(not planned.is_empty() and planned.size() <= 100, "材料数量不合理")
		var seen: Dictionary = {}
		var kinds: Dictionary = {}
		for entry: Dictionary in planned:
			_materials += 1
			var tile: Vector2i = entry["tile"]
			var local: Vector2i = tile - spec.origin
			_check(not seen.has(tile) and spec.contains_local(local.x, local.y) and generator.is_walkable(tile), "材料重复或落在阻挡/区域外")
			_check(spec.cottage == null or not spec.cottage.bounds.has_point(local), "材料出现在屋内")
			_check(int(entry["amount"]) > 0 and int(entry["item_id"]) in [2, 3], "材料数据无效")
			seen[tile] = true
			kinds[entry["item_id"]] = true
		_check(kinds.has(2) and kinds.has(3), "区域缺少石头或木棍")


func _settle(manager: ChunkManager) -> void:
	for _frame: int in 600:
		await process_frame
		if manager.map_ready():
			return
	_check(false, "当前地图未在600帧内完成加载")


func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(not image.is_empty() and image.save_png(path) == OK, "截图保存失败")


func _check_runtime() -> void:
	var registry: Node = root.get_node("ItemListGlobal")
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 18473)
	var scene: PackedScene = load("res://scenes/game/game_world.tscn")
	var game: Node2D = scene.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	var player: PlayerCharacter = game.get_node("Player")
	player.set_physics_process(false)
	game.get_node("MonsterSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	var manager: ChunkManager = game.get_node("ChunkManager")
	await process_frame
	var start_root: Node2D = game._map_entity_roots[0]
	var pickups: Array[GroundPickup] = []
	for child: Node in start_root.get_children():
		if child is GroundPickup:
			pickups.append(child)
	_check(pickups.size() >= 2, "起始屋外缺少可拾取材料")
	_check(manager.tile_set.has_source(TerrainTransitions.SOURCE_ID), "地图未安装过渡图集")
	await _settle(manager)
	var blended_tiles: int = 0
	for layer: TileMapLayer in manager._layers.values():
		for cell: Vector2i in layer.get_used_cells():
			if layer.get_cell_source_id(cell) == TerrainTransitions.SOURCE_ID:
				blended_tiles += 1
	_check(blended_tiles > 0, "实际地图未铺设过渡地块")
	if pickups.is_empty():
		game.queue_free()
		await process_frame
		return
	var pickup: GroundPickup = pickups[0]
	var item_id: int = pickup.data.id
	var amount: int = pickup.amount
	var tile: Vector2i = WorldGenerator.world_to_tile(pickup.global_position)
	var plan_before: Array[Dictionary] = GroundMaterials.plan(manager.get_generator(), manager.get_map_spec())
	player.global_position = pickup.global_position + Vector2(16, 0)
	game._refresh_pickup()
	_check(game._nearby_pickup == pickup, "近处物品未成为拾取目标")
	_check(game.hud.get_node("PickupHint").visible, "近处未显示E拾取提示")
	if "--capture" in OS.get_cmdline_user_args():
		game.hud.get_node("StatsLabel").visible = false
		await _capture("res://.godot/transitions-materials-preview.png")
	var original_count: int = player.inventory.get_count(item_id)
	game.get_node("GameHUD/Alchemy").visible = true
	game._refresh_pickup()
	_check(game._nearby_pickup == null, "炼金界面打开时仍能拾取地图物品")
	game.get_node("GameHUD/Alchemy").visible = false
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	game._unhandled_input(event)
	_check(player.inventory.get_count(item_id) == original_count + amount, "E拾取未增加背包数量")
	_check(not pickup.collect(player), "重复拾取增加了第二次材料")
	await process_frame
	_check(not is_instance_valid(pickup), "拾取后地面节点未删除")
	game._enter_map(2)
	await process_frame
	_check(not start_root.is_visible_in_tree() and not start_root.can_process(), "离图后材料仍可见/处理")
	game._enter_map(0)
	await process_frame
	_check(start_root.is_visible_in_tree() and start_root.get_child_count() == pickups.size() - 1, "返回地图重复生成了已拾取材料")
	var found: bool = false
	for child: Node2D in start_root.get_children():
		found = found or WorldGenerator.world_to_tile(child.global_position) == tile
	_check(not found, "已拾取点位返回后重新出现")
	_check(player.inventory.get_count(item_id) == original_count + amount, "切图未保留拾取材料")
	for id: int in [2, 3]:
		var data: IngredientData = registry.get_template(id) as IngredientData
		_check(data != null and not data.alchemical_attribute.is_empty(), "材料没有炼金属性")
		var model: ItemModel = data.create_model()
		_check(model != null and model.data == data, "材料不能创建炼金投放模型")
		if model != null:
			model.free()
	var mineral: AlchemicalData = registry.get_template(2).alchemical_attribute[0]
	var woody: AlchemicalData = registry.get_template(3).alchemical_attribute[0]
	_check(mineral.can_interact_with(woody) and woody.can_interact_with(mineral), "石头与木棍属性不能反应")
	var ingredients: Array[AlchemicalData] = [woody]
	_check(not mineral.interact(ingredients).is_empty(), "材料组合没有产出炼金属性")
	var alchemy: Node2D = game.get_node("GameHUD/Alchemy")
	var zone: Control = alchemy.get_node("Cauldon/LeftDropZone")
	var cauldron: Node = alchemy.get_node("Cauldon")
	var spawned: Node2D = alchemy.get_node("SpawnedItems")
	cauldron.attribute.clear()
	for id: int in [2, 3]:
		var payload: Dictionary = {"item_id": id, "count": 1, "rotation": 0.2}
		_check(zone._can_drop_data(Vector2.ZERO, payload), "炼金投放区拒绝新材料")
		zone._drop_data(Vector2.ZERO, payload)
		var model: ItemModel = spawned.get_child(spawned.get_child_count() - 1) as ItemModel
		_check(model != null and model.data.id == id and is_equal_approx(model.global_rotation, 0.2), "实际投放模型/旋转错误")
		cauldron._get_attributes(model)
	_check(cauldron.attribute.size() == 2, "坩埚未接收两种材料的属性")
	cauldron.start_transform()
	_check(cauldron.attribute.size() == 1 and cauldron.attribute[0].attribute_id == 5, "矿物与木质未在实际坩埚中反应为固结")
	await process_frame
	_check(spawned.get_child_count() == 0, "炼金消耗后模型未释放")
	game.build_world(97231)
	await process_frame
	_check(not is_instance_valid(start_root), "重建世界未清理旧材料节点")
	_check(GroundMaterials.plan(manager.get_generator(), manager.get_map_spec()) != plan_before, "新种子未改变地面材料分布")
	_check(player.inventory.get_count(item_id) == original_count + amount, "重建世界清空了背包材料")
	game.queue_free()
	await process_frame
	await process_frame
