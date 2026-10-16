extends SceneTree

## godot --headless --path . --script res://tools/test_pyramid_world.gd
## 使用图形渲染并加 -- --capture 保存地图总览及黑幕画面。
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)


func _run() -> void:
	Engine.max_fps = 120
	for seed_value: int in [1, 18473, 97231, 2147483646]:
		for variant: int in [0, 1]:
			_check_layout(WorldGenerator.new(seed_value, null, variant))
	await _check_runtime()
	print("PYRAMID_WORLD: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_layout(generator: WorldGenerator) -> void:
	var specs: Array[MapSpec] = generator.map_specs()
	_check(specs.size() == 15, "保留14张原地图并补第三列额外分支")
	_check(generator.run.floors[0].size() == 1 and generator.run.floors[1].size() == 2 and generator.run.floors[2].size() == 3, "前三列应分别为1、2、3个真实区域")
	for original_id: int in [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]:
		_check(generator.map_spec(original_id) != null, "原节点丢失 %d" % original_id)
	_check(generator.map_spec(RunGraph.node_id(2, RunGraph.THIRD_VARIANT)) != null, "额外分支未加入第三列")
	_check(MapValidator.validate(generator).is_empty(), "全图图约束/碰撞失效")
	_check(generator._groves.noise_type == FastNoiseLite.TYPE_PERLIN and generator._edges.noise_type == FastNoiseLite.TYPE_PERLIN, "地貌未使用世界坐标Perlin")
	for floor_index: int in generator.run.floors.size():
		var ids: PackedInt32Array = generator.run.floors[floor_index]
		var floor_specs: Array[MapSpec] = []
		for id: int in ids:
			floor_specs.append(generator.map_spec(id))
		floor_specs.sort_custom(func(a: MapSpec, b: MapSpec) -> bool: return a.origin.y < b.origin.y)
		for index: int in floor_specs.size():
			var spec: MapSpec = floor_specs[index]
			_check(spec.origin.x == floor_specs[0].origin.x and spec.extent.x == floor_specs[0].extent.x, "同列地图没有共用完整东西侧边界")
			if index > 0:
				_check(floor_specs[index - 1].origin.y + floor_specs[index - 1].extent.y == spec.origin.y, "同列上下区域没有接壤")
		if floor_index == 0:
			continue
		var previous: PackedInt32Array = generator.run.floors[floor_index - 1]
		var last: MapSpec = generator.map_spec(previous[0])
		_check(last.origin.x + last.extent.x == floor_specs[0].origin.x, "相邻列之间有空白或交叠")
		var shared: bool = false
		for prev_id: int in previous:
			var a: MapSpec = generator.map_spec(prev_id)
			for b: MapSpec in floor_specs:
				shared = shared or mini(a.origin.y + a.extent.y, b.origin.y + b.extent.y) - maxi(a.origin.y, b.origin.y) >= 12
		_check(shared, "相邻箱庭列只在角落相接")
	var blended_seams: int = 0
	for spec: MapSpec in specs:
		for other: MapSpec in specs:
			if other.origin.x != spec.origin.x + spec.extent.x or other.boundary_kind == spec.boundary_kind:
				continue
			var upper: int = maxi(spec.origin.y, other.origin.y) + 1
			var lower: int = mini(spec.origin.y + spec.extent.y, other.origin.y + other.extent.y) - 1
			if upper >= lower:
				continue
			var tile := Vector2i(other.origin.x - 1, (upper + lower) / 2)
			var blend: Vector2i = TerrainTransitions.seam_at(generator, spec, tile, spec.boundary_kind)
			_check(blend != TerrainTransitions.NO_BLEND and blend.x >= 20 and blend.x <= 23, "贴合箱庭间缺少柏林微扰渐变")
			blended_seams += 1
	_check(blended_seams > 0, "测试种子没有触发跨箱庭的过渡地块")
	for connection: Dictionary in generator.connections():
		var from_spec: MapSpec = generator.map_spec(connection["from"])
		var to_spec: MapSpec = generator.map_spec(connection["to"])
		_check(from_spec.origin.x + from_spec.extent.x == to_spec.origin.x, "图边跨越了不相邻列")
		_check(generator.is_walkable(Vector2i(connection["a"])) and generator.is_walkable(Vector2i(connection["b"])), "图边出入口被Perlin地形阻断")
	var replica := WorldGenerator.new(generator.world_seed, generator.config, generator.variant)
	for spec: MapSpec in specs:
		var other: MapSpec = replica.map_spec(spec.node_id)
		_check(spec.origin == other.origin and spec.extent == other.extent and spec.biome_id == other.biome_id, "同种子列布局不确定")
	var legacy := MapConfig.new()
	legacy.pyramid_third_branch = false
	var old_graph := RoomGraph.plan(generator.world_seed, legacy, generator.variant)
	_check(old_graph.floors[2].size() == 2 and old_graph.main_path == generator.run.main_path, "原主线路线不可恢复")


func _check_runtime() -> void:
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
	var minimap: Minimap = game.get_node("GameHUD/HUD/Minimap")
	var generator: WorldGenerator = game._generator
	minimap.set_expanded(true)
	var full := Rect2i(minimap._map_origin, minimap._map_image_size)
	for spec: MapSpec in generator.map_specs():
		_check(full.encloses(Rect2i(spec.origin, spec.extent)), "全屏总览无法看到某列地图")
	_check(minimap._active_tiles_per_pixel == 1, "全屏地图探索分辨率改变")
	_check(minimap._explored_chunks.size() < 200, "未访问的箱庭被错误标记为已探索")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture("res://.godot/pyramid-map-preview.png")
	minimap.set_expanded(false)
	var link: Dictionary = generator.gate_links(0)[0]
	var scene_manager: Node = root.get_node("SceneManager")
	var overlay: ColorRect = scene_manager.get_node("ColorRect")
	var expected: Vector2 = generator.entry_position(int(link["target"]), int(link["arrival_side"]), int(link["arrival_y"]))
	var epoch: int = game.chunk_manager._epoch
	game._transition_to_map(link)
	_check(game._transitioning and game._current_node == 0 and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "淡出前提前切图/玩家输入未暂停")
	var regenerate := InputEventAction.new()
	regenerate.action = "regenerate_world"
	regenerate.pressed = true
	game._unhandled_input(regenerate)
	_check(game.chunk_manager._epoch == epoch, "黑屏期间仍能通过快捷键重建世界")
	game._transition_to_map(link)
	_check(game._current_node == 0, "重复出口调用绕过切换锁")
	var saw_black: bool = false
	for frame: int in 140:
		await process_frame
		if overlay.visible and overlay.modulate.a >= 0.98:
			saw_black = true
			_check(overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "黑屏期间点击没有被遮挡")
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				var black_frame: Image = root.get_texture().get_image()
				_check(black_frame.get_pixel(black_frame.get_width() / 2, black_frame.get_height() / 2).r < 0.03 and black_frame.get_pixel(2, 2).r < 0.03, "全黑转场画面仍透出地图或 HUD")
				_check(black_frame.save_png("res://.godot/pyramid-gate-fade.png") == OK, "黑屏截图保存失败")
			break
	_check(saw_black, "入口切换未覆盖完整黑屏")
	for frame: int in 140:
		if not game._transitioning:
			break
		await process_frame
	_check(not game._transitioning and not overlay.visible and is_zero_approx(overlay.modulate.a), "切换后未淡出黑幕")
	_check(game._current_node == link["target"] and game.chunk_manager.get_map_spec().node_id == link["target"], "黑幕后没有到达正确箱庭")
	_check(player.global_position.is_equal_approx(expected) and player.can_stand_at(expected), "新入口位置不可走或不正确")
	_check(game.chunk_manager._epoch == epoch and not player.is_physics_processing(), "切换重建了世界或破坏暂停状态")
	_check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "结束后黑幕仍挡住鼠标输入")
	game._enter_map(3)
	var extra_id: int = RunGraph.node_id(2, RunGraph.THIRD_VARIANT)
	var extra_link: Dictionary = {}
	for candidate: Dictionary in generator.gate_links(3):
		if candidate["target"] == extra_id:
			extra_link = candidate
	_check(not extra_link.is_empty(), "新增箱庭缺少由第二列下侧进入的出口")
	if not extra_link.is_empty():
		player.global_position = WorldGenerator.tile_to_world(extra_link["point"])
		player.velocity = Vector2(float(extra_link["side"]) * 50.0, 0.0)
		game._process(0.0)
		await _wait_transition(game)
		_check(game._current_node == extra_id and game.chunk_manager.get_map_spec().node_id == extra_id, "第三列新增箱庭无法真正进入")
		_check(player.can_stand_at(player.global_position), "新增箱庭的真实落点不可通行")
		var return_link: Dictionary = {}
		for candidate: Dictionary in generator.gate_links(extra_id):
			if candidate["target"] == 3:
				return_link = candidate
		_check(not return_link.is_empty(), "新增箱庭缺少原路回程入口")
		if not return_link.is_empty():
			player.global_position = WorldGenerator.tile_to_world(return_link["point"])
			player.velocity = Vector2(float(return_link["side"]) * 50.0, 0.0)
			game._process(0.0)
			await _wait_transition(game)
			_check(game._current_node == 3 and not overlay.visible, "新增岔路黑幕回程失败")
	game.queue_free()
	await process_frame
	await process_frame


func _wait_transition(game: Node2D) -> void:
	for frame: int in 160:
		if not game._transitioning:
			return
		await process_frame
	_check(false, "新增箱庭出入口黑屏动画未结束")


func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(path) == OK, "截图保存失败 %s" % path)
