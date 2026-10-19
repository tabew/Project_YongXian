extends SceneTree

## godot --headless --path . --script res://tools/test_continuous_world.gd
## 添加 -- --capture 可在有图形界面的运行中保存当前箱庭、边界和切图画面。
var _failures: int = 0
var _path_samples: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	Engine.max_fps = 120
	for seed_value: int in [1, 18473, 97231, 2147483646]:
		_check_layout(seed_value)
	await _check_runtime()
	print("CONTINUOUS_WORLD: failures=%d, walkable_path_samples=%d" % [_failures, _path_samples])
	quit(0 if _failures == 0 else 1)


func _check_layout(seed_value: int) -> void:
	var generator := WorldGenerator.new(seed_value)
	var replica := WorldGenerator.new(seed_value)
	var sizes: Dictionary = {}
	var shapes: Dictionary = {}
	var expected_edges: int = 0
	for spec: MapSpec in generator.map_specs():
		_check(not sizes.has(spec.origin), "区域起点重复 seed=%d node=%d" % [seed_value, spec.node_id])
		sizes[spec.origin] = true
		shapes[spec.shape] = true
		expected_edges += generator.run.exit_count(spec.node_id)
		var other: MapSpec = replica.map_spec(spec.node_id)
		_check(other.origin == spec.origin and other.extent == spec.extent and other.axes == spec.axes, "同种子布局不一致")
		_check_land_box(generator, spec)
		var roads: PackedFloat32Array = spec.build_roads()
		_check(roads == other.build_roads(), "同种子内部道路不一致")
		for base: int in range(0, roads.size(), 5):
			var a := Vector2(roads[base], roads[base + 1])
			var b := Vector2(roads[base + 2], roads[base + 3])
			_check_path(generator, Vector2(spec.origin) + a, Vector2(spec.origin) + b, roads[base + 4])
	_check(generator.map_specs().size() == 15, "每seed应包含14个原区域和第三列新增的1个支线")
	_check(shapes.size() == MapSpec.SHAPE_NAMES.size(), "世界没有覆盖六类轮廓")
	_check(generator.connections().size() == expected_edges, "关卡图与出口连接数量不同")
	_check(generator.connections() == replica.connections(), "同种子连接不一致")
	var link_count: int = 0
	for spec: MapSpec in generator.map_specs():
		var links: Array[Dictionary] = generator.gate_links(spec.node_id)
		_check(links == replica.gate_links(spec.node_id), "同种子gate_links不一致")
		link_count += links.size()
		for link: Dictionary in links:
			_check_gate_link(generator, spec, link)
	_check(link_count == expected_edges * 2, "图边没有对应双向出口")
	for connection: Dictionary in generator.connections():
		for key: String in ["a", "b", "from", "to", "exit", "entrance"]:
			_check(connection.has(key), "connections缺少字段%s" % key)
		var a: Vector2 = connection["a"]
		var b: Vector2 = connection["b"]
		var source: MapSpec = generator.map_spec(connection["from"])
		var target: MapSpec = generator.map_spec(connection["to"])
		_check(Rect2i(source.origin, source.extent).has_point(Vector2i(a.floor())), "连接出口不在来源边界内")
		_check(Rect2i(target.origin, target.extent).has_point(Vector2i(b.floor())), "连接入口不在目标边界内")
		_check(Vector2i(a.floor()).x == source.origin.x + source.extent.x - 1, "图边a不是东侧边界")
		_check(Vector2i(b.floor()).x == target.origin.x, "图边b不是西侧边界")
		# 列间没有空白断层；部分岔路仍通过黑屏转场连接上下不同的入口。
		_check(source.origin.x + source.extent.x == target.origin.x, "图边所在列之间仍有空白间隙")
		for index: int in range(1, 20):
			var tile := Vector2i(a.lerp(b, float(index) / 20.0).floor())
			if generator.sample_map(tile) != null:
				continue
			_check(generator.sample_route(tile) == Route.Kind.NONE, "地图间隙仍有实体道路 seed=%d tile=%s" % [seed_value, tile])
			_check(not generator.is_walkable(tile), "地图间隙意外可走")
	var boundary_tile := Vector2i(-1000, 1000)
	_check(not generator.is_walkable(boundary_tile), "山林边界意外可通行")
	_check(not Terrain.is_water(generator.sample_terrain(boundary_tile)), "世界外围仍被生成成海")
	_check_reachable_ground(generator, generator.map_spec(0))
	_check_reachable_ground(generator, generator.map_spec(3))
	# 结构最密集、可走地面最紧张的岔路箱庭也要保证完全连通。
	_check_reachable_ground(generator, generator.map_spec(13))
	var chunk: ChunkData = generator.generate_chunk(Vector2i(6, -4))
	var copy: ChunkData = replica.generate_chunk(Vector2i(6, -4))
	_check(chunk.terrain == copy.terrain and chunk.route == copy.route and chunk.biome == copy.biome, "线程独立生成器数据不一致")


func _check_gate_link(generator: WorldGenerator, spec: MapSpec, link: Dictionary) -> void:
	for key: String in ["side", "y", "target", "arrival_side", "arrival_y", "point"]:
		_check(link.has(key), "gate_links缺少字段%s" % key)
		if not link.has(key):
			return
	var side: int = link["side"]
	var gate_y: int = link["y"]
	var point: Vector2i = link["point"]
	_check(side == -1 or side == 1, "gate side不是西-1/东+1")
	_check(link["arrival_side"] == -side, "出口与抵达入口方向不对应")
	var expected := spec.origin + Vector2i(0 if side < 0 else spec.extent.x - 1, gate_y)
	_check(point == expected, "gate point不是世界边界格")
	_check(generator.sample_map(point) == spec, "gate不属于当前区域")
	_check(generator.sample_route(point) != Route.Kind.NONE and generator.is_walkable(point), "区域内gate没有可走道路")
	var reciprocal: bool = false
	for back: Dictionary in generator.gate_links(link["target"]):
		if back["target"] == spec.node_id and back["side"] == link["arrival_side"] and back["y"] == link["arrival_y"] and back["arrival_y"] == gate_y:
			reciprocal = true
	_check(reciprocal, "出口没有匹配的回程link")
	var spawn: Vector2 = generator.entry_position(spec.node_id, side, gate_y)
	var tile: Vector2i = WorldGenerator.world_to_tile(spawn)
	var local: Vector2i = tile - spec.origin
	_check(spec.contains_local(local.x, local.y), "入口出生点落到区域外")
	var inset: int = local.x if side < 0 else spec.extent.x - 1 - local.x
	_check(inset >= 3, "入口出生点离边不足3tile")
	_check(generator.sample_route(tile) != Route.Kind.NONE and generator.is_walkable(tile), "入口出生点没有沿真实内部道路向里")
	_check(inset >= 5 and inset <= 11, "入口出生点没有位于gate沿弯曲道路向里8tile附近")
	for step: int in range(0, 3):
		var inner: Vector2i = point + Vector2i(-side * step, 0)
		_check(generator.sample_route(inner) != Route.Kind.NONE and generator.is_walkable(inner), "地图内部gate道路不连续")


func _check_land_box(generator: WorldGenerator, spec: MapSpec) -> void:
	var samples: int = 0
	var water: int = 0
	var walkable: int = 0
	var walls: int = 0
	_check(spec.clearance(spec.center) > 10.0, "出生点没有落在主庭内部")
	_check(spec.side_centers.size() >= 2, "箱庭缺少可探索侧庭")
	for y: int in range(2, spec.extent.y, 4):
		for x: int in range(2, spec.extent.x, 4):
			var tile: Vector2i = spec.origin + Vector2i(x, y)
			generator._classify(tile.x, tile.y)
			samples += 1
			if Terrain.is_water(generator._last_terrain):
				water += 1
			if Terrain.is_walkable(generator._last_terrain) or generator._last_route != Route.Kind.NONE:
				walkable += 1
			else:
				walls += 1
	var water_ratio: float = float(water) / samples
	var ground_ratio: float = float(walkable) / samples
	_check(water_ratio < 0.10, "水域占比过高 seed=%d node=%d ratio=%.3f" % [generator.world_seed, spec.node_id, water_ratio])
	# 地表结构（营地/遗迹/石阵/补给点）会有意占用少量可走格，最紧张的箱庭真值约 50.5%。
	# 阈值留出该余量；连通性由 _check_reachable_ground 单独保证，不靠这个比例兜底。
	_check(ground_ratio > 0.48, "可探索陆地过少 seed=%d node=%d ratio=%.3f" % [generator.world_seed, spec.node_id, ground_ratio])
	_check(float(walls) / samples > 0.03, "箱庭缺少山林围合边界")
	print("LAND_BOX: seed=%d node=%d biome=%d water=%.1f%% walkable=%.1f%%" % [generator.world_seed, spec.node_id, spec.biome_id, water_ratio * 100.0, ground_ratio * 100.0])


func _check_reachable_ground(generator: WorldGenerator, spec: MapSpec) -> void:
	var cells := PackedByteArray()
	cells.resize(spec.extent.x * spec.extent.y)
	var walkable: int = 0
	for y: int in spec.extent.y:
		for x: int in spec.extent.x:
			var tile: Vector2i = spec.origin + Vector2i(x, y)
			generator._classify(tile.x, tile.y)
			if Terrain.is_walkable(generator._last_terrain) or generator._last_route != Route.Kind.NONE:
				cells[y * spec.extent.x + x] = 1
				walkable += 1
	var queue: Array[Vector2i] = [Vector2i(spec.center)]
	cells[queue[0].y * spec.extent.x + queue[0].x] = 2
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for delta: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + delta
			if not spec.contains_local(next.x, next.y):
				continue
			var index: int = next.y * spec.extent.x + next.x
			if cells[index] == 1:
				cells[index] = 2
				queue.append(next)
	var ratio: float = float(queue.size()) / maxi(1, walkable)
	_check(ratio > 0.95, "陆地存在大面积孤立区域 seed=%d node=%d reachable=%.3f" % [generator.world_seed, spec.node_id, ratio])
	print("REACHABLE: seed=%d node=%d ratio=%.3f" % [generator.world_seed, spec.node_id, ratio])


func _check_path(generator: WorldGenerator, a: Vector2, b: Vector2, phase: float = -1.0) -> void:
	var steps: int = ceili(a.distance_to(b) * 3.0)
	var normal: Vector2 = Vector2((b - a).y, -(b - a).x).normalized()
	for index: int in range(steps + 1):
		var t: float = float(index) / float(maxi(steps, 1))
		var point: Vector2 = a.lerp(b, t)
		if phase >= 0.0:
			point += normal * MapSpec.road_offset(t, phase)
		var tile := Vector2i(point.floor())
		_path_samples += 1
		_check(generator.is_walkable(tile), "道路断口 seed=%d tile=%s" % [generator.world_seed, tile])
		var spec: MapSpec = generator.sample_map(tile)
		var indoor: bool = spec != null and spec.cottage != null and spec.cottage.bounds.has_point(tile - spec.origin)
		if indoor:
			_check(generator.sample_terrain(tile) == Terrain.Kind.STONE and generator.sample_route(tile) == Route.Kind.NONE, "屋内通路应保持木地板 seed=%d tile=%s" % [generator.world_seed, tile])
		else:
			_check(generator.sample_route(tile) != Route.Kind.NONE, "路面断口 seed=%d tile=%s" % [generator.world_seed, tile])


func _map_chunks(spec: MapSpec) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var first: Vector2i = WorldGenerator.tile_to_chunk(spec.origin)
	var last: Vector2i = WorldGenerator.tile_to_chunk(spec.origin + spec.extent - Vector2i.ONE)
	for cy: int in range(first.y, last.y + 1):
		for cx: int in range(first.x, last.x + 1):
			result.append(Vector2i(cx, cy))
	return result


func _settle(manager: ChunkManager) -> void:
	for frame: int in 600:
		await process_frame
		if manager.map_ready():
			var loaded: Array[Vector2i] = manager.loaded_chunks()
			var window: Rect2i = manager._visible_chunk_bounds()
			_check(window.has_area(), "map_ready没有可见窗口")
			for cy: int in range(window.position.y, window.end.y):
				for cx: int in range(window.position.x, window.end.x):
					var coords := Vector2i(cx, cy)
					_check(loaded.has(coords), "当前可见窗口仍有缺失区块%s" % coords)
			return
	_check(false, "当前箱庭未能在限定帧数内加载完成")


func _camera_rect(camera: Camera2D) -> Rect2:
	var size: Vector2 = camera.get_viewport_rect().size / camera.zoom
	return Rect2(camera.get_screen_center_position() - size * 0.5, size)


func _check_viewport_loaded(manager: ChunkManager, camera: Camera2D) -> void:
	var spec: MapSpec = manager.get_map_spec()
	var view: Rect2 = _camera_rect(camera)
	var bounds := Rect2(Vector2(spec.origin) * WorldGenerator.TILE_SIZE, Vector2(spec.extent) * WorldGenerator.TILE_SIZE)
	_check(view.position.x >= bounds.position.x - 1.0 and view.position.y >= bounds.position.y - 1.0 and view.end.x <= bounds.end.x + 1.0 and view.end.y <= bounds.end.y + 1.0, "相机视口超出当前箱庭")
	# 减去微小值，避免恰好贴边的下一区块被误算进视口。
	var first: Vector2i = WorldGenerator.tile_to_chunk(WorldGenerator.world_to_tile(view.position + Vector2.ONE * 0.01))
	var last: Vector2i = WorldGenerator.tile_to_chunk(WorldGenerator.world_to_tile(view.end - Vector2.ONE * 0.01))
	var loaded: Array[Vector2i] = manager.loaded_chunks()
	for cy: int in range(first.y, last.y + 1):
		for cx: int in range(first.x, last.x + 1):
			_check(loaded.has(Vector2i(cx, cy)), "切图当帧当前视口区块尚未同步铺好%s" % Vector2i(cx, cy))


func _check_camera_limits(camera: Camera2D, spec: MapSpec) -> void:
	_check(camera.limit_left == spec.origin.x * 16 and camera.limit_top == spec.origin.y * 16 and camera.limit_right == (spec.origin.x + spec.extent.x) * 16 and camera.limit_bottom == (spec.origin.y + spec.extent.y) * 16, "camera.limit四边未同步当前区域")


func _check_active_map(game: Node2D, manager: ChunkManager, player: PlayerCharacter, camera: Camera2D, id: int) -> void:
	var spec: MapSpec = manager.get_generator().map_spec(id)
	_check(game._current_node == id and manager.get_map_spec() == spec, "切图未同步current/load_map")
	_check(player.active_map == spec and player.terrain_source == manager.get_generator(), "切图未同步player/source/active bounds")
	_check_camera_limits(camera, spec)
	_check_viewport_loaded(manager, camera)
	var allowed: Array[Vector2i] = _map_chunks(spec)
	for coords: Vector2i in manager.loaded_chunks():
		_check(allowed.has(coords), "loaded_chunks混入其它区域区块")
	# 包含其它区域的真实可走位置，保证active_map检查先于地形缓存。
	for other: MapSpec in manager.get_generator().map_specs():
		if other.node_id != id:
			var pos: Vector2 = WorldGenerator.tile_to_world(other.origin + Vector2i(other.center))
			_check(not player.can_stand_at(pos), "Player允许站到其它区域内部")
			break
	for tile: Vector2i in [spec.origin + Vector2i(-1, spec.extent.y / 2), spec.origin + Vector2i(spec.extent.x, spec.extent.y / 2), spec.origin + Vector2i(spec.extent.x / 2, -1), spec.origin + Vector2i(spec.extent.x / 2, spec.extent.y)]:
		_check(not player.can_stand_at(WorldGenerator.tile_to_world(tile)), "Player允许站到当前矩形外")
	_check_layers(manager, spec)


func _check_layers(manager: ChunkManager, spec: MapSpec) -> void:
	var bounds := Rect2i(spec.origin, spec.extent)
	for coords: Vector2i in manager._layers:
		var layer: TileMapLayer = manager._layers[coords]
		_check(layer.is_visible_in_tree(), "当前区域图层不可见")
		for cell: Vector2i in layer.get_used_cells():
			var tile: Vector2i = WorldGenerator.world_to_tile(layer.to_global(layer.map_to_local(cell)))
			_check(bounds.has_point(tile), "当前图层未裁切区域边界tile=%s" % tile)
	# 邻图可以预铺，但只能在隐藏的root下；不依赖root字典的内部命名。
	_check_visible_layers(manager, bounds)


func _check_visible_layers(node: Node, bounds: Rect2i) -> void:
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		if layer.is_visible_in_tree():
			for cell: Vector2i in layer.get_used_cells():
				var tile: Vector2i = WorldGenerator.world_to_tile(layer.to_global(layer.map_to_local(cell)))
				_check(bounds.has_point(tile), "可见邻图泄漏到当前箱庭tile=%s" % tile)
	for child: Node in node.get_children():
		_check_visible_layers(child, bounds)


func _check_minimap(
	minimap: Minimap, generator: WorldGenerator, require_explored: bool
) -> PackedByteArray:
	var started: int = Time.get_ticks_usec()
	var pixels: PackedByteArray = minimap.build_pixels()
	print("MINIMAP: seed=%d build_ms=%.2f, bytes=%d" % [generator.world_seed, float(Time.get_ticks_usec() - started) / 1000.0, pixels.size()])
	_check(pixels.size() == Minimap.TEXTURE_SIZE * Minimap.TEXTURE_SIZE * 3, "小地图像素尺寸错误")
	var view := Rect2i(minimap._map_origin, Vector2i(Minimap.WINDOW_TILES, Minimap.WINDOW_TILES))
	var visible_regions: int = 0
	for spec: MapSpec in generator.map_specs():
		if view.intersects(Rect2i(spec.origin, spec.extent)):
			visible_regions += 1
	_check(visible_regions >= 3, "小地图没有保留周边主干与岔路")
	# 小地图只画已探索区块：不是迷雾的像素必须与世界完全一致，没去过的保持迷雾。
	var matched: int = 0
	for index: int in 400:
		var linear: int = (index * 47) % (Minimap.TEXTURE_SIZE * Minimap.TEXTURE_SIZE)
		var pixel := Vector2i(linear % Minimap.TEXTURE_SIZE, linear / Minimap.TEXTURE_SIZE)
		var tile: Vector2i = minimap._map_origin + pixel * Minimap.TILES_PER_PIXEL
		var offset: int = (pixel.y * Minimap.TEXTURE_SIZE + pixel.x) * 3
		if (
			pixels[offset] == minimap._unknown_rgb[0]
			and pixels[offset + 1] == minimap._unknown_rgb[1]
			and pixels[offset + 2] == minimap._unknown_rgb[2]
		):
			continue
		var rgb: int = minimap._color_rgb(generator.sample_terrain(tile), generator.sample_route(tile))
		_check(pixels[offset] == ((rgb >> 16) & 255) and pixels[offset + 1] == ((rgb >> 8) & 255) and pixels[offset + 2] == (rgb & 255), "小地图与世界颜色不一致")
		matched += 1
	if require_explored:
		_check(matched > 0, "小地图没有画出已探索区块")
		_check(matched < 400, "小地图把没探索过的区块也画了出来")
	return pixels


func _wait_for_fade(game: Node2D) -> void:
	for frame: int in 160:
		await process_frame
		if not game._transitioning:
			return
	_check(false, "箱庭切换黑屏动画未结束")


func _check_gate_transitions(game: Node2D, manager: ChunkManager, player: PlayerCharacter, camera: Camera2D) -> void:
	var generator: WorldGenerator = manager.get_generator()
	var epoch: int = manager._epoch
	# 主干、岔路、汇流均检查，含东西两侧回程。
	for id: int in [0, 2, 3, 4]:
		for link: Dictionary in generator.gate_links(id):
			game._enter_map(id)
			# 出生点离开gate band即可解除防抖，无等待、无淡出计时。
			player.velocity = Vector2.ZERO
			game._process(0.0)
			var gate_position: Vector2 = WorldGenerator.tile_to_world(link["point"])
			player.global_position = gate_position
			player.velocity = Vector2(-float(link["side"]) * 50.0, 0.0)
			game._process(0.0)
			_check(game._current_node == id, "向区域内部移动也触发出口")
			player.velocity = Vector2.ZERO
			game._process(0.0)
			_check(game._current_node == id, "静止在gate也触发出口")
			player.velocity = Vector2(float(link["side"]) * 50.0, 0.0)
			game._process(0.0)
			_check(game._transitioning and game._current_node == id, "黑屏动画开始前不应传送")
			await _wait_for_fade(game)
			player.set_physics_process(false)
			var target_id: int = link["target"]
			_check_active_map(game, manager, player, camera, target_id)
			var expected: Vector2 = generator.entry_position(target_id, link["arrival_side"], link["arrival_y"])
			_check(player.global_position.is_equal_approx(expected), "出口没有立即传送到对应入口spawn")
			_check(player.can_stand_at(player.global_position), "切图入口spawn不可站立")
			_check(manager._epoch == epoch, "同seed切图改变epoch")
			# 真实spawn已向里离开gateband，立刻朝入口移动不会弹回。
			player.velocity = Vector2(float(link["arrival_side"]) * 50.0, 0.0)
			game._process(0.0)
			_check(game._current_node == target_id, "出生入口gate发生立即反弹")
			# 无计时等待，走离入口再回到gate即可回程。
			var target: MapSpec = generator.map_spec(target_id)
			player.global_position = WorldGenerator.tile_to_world(target.origin + Vector2i(target.center))
			player.velocity = Vector2.ZERO
			game._process(0.0)
			var arrival_point := target.origin + Vector2i(0 if int(link["arrival_side"]) < 0 else target.extent.x - 1, int(link["arrival_y"]))
			player.global_position = WorldGenerator.tile_to_world(arrival_point)
			player.velocity = Vector2(float(link["arrival_side"]) * 50.0, 0.0)
			game._process(0.0)
			await _wait_for_fade(game)
			player.set_physics_process(false)
			_check_active_map(game, manager, player, camera, id)
			_check(player.global_position.is_equal_approx(generator.entry_position(id, link["side"], link["y"])), "gate防抖解除后不能立即原路回程")
			player.velocity = Vector2.ZERO


func _check_camera(game: Node2D, manager: ChunkManager, player: PlayerCharacter, camera: Camera2D) -> void:
	var viewport: Vector2 = camera.get_viewport_rect().size / camera.zoom
	for spec: MapSpec in manager.get_generator().map_specs():
		_check(spec.extent.x * 16 > viewport.x and spec.extent.y * 16 > viewport.y, "地图最小宽高不足容纳viewport/zoom")
	for id: int in [0, 3]:
		game._enter_map(id)
		var spec: MapSpec = manager.get_map_spec()
		_check_camera_limits(camera, spec)
		for corner: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i.ONE]:
			var centers: Array[Vector2] = []
			# 更向边缘推进的两个不同playerpos都应得到相同screen center。
			for inset: int in [6, 3]:
				var local := Vector2i(inset if corner.x == 0 else spec.extent.x - 1 - inset, inset if corner.y == 0 else spec.extent.y - 1 - inset)
				player.global_position = WorldGenerator.tile_to_world(spec.origin + local)
				camera.reset_smoothing()
				camera.force_update_scroll()
				manager.load_map(id)
				await process_frame
				_check_viewport_loaded(manager, camera)
				centers.append(camera.get_screen_center_position())
			_check(centers[0].is_equal_approx(centers[1]), "边界继续向前移动时相机中心仍移动")
		await _settle(manager)
		_check_layers(manager, spec)


func _start_workers(game: Node2D, manager: ChunkManager) -> void:
	# 尚未访问的远图确保存在真实生成任务，不注入旧窗口机制的假结果。
	game._enter_map(12)
	manager._process(0.0)
	_check(manager.use_worker_threads and not manager._in_flight.is_empty(), "快速切图/重建测试没有派发worker")


func _check_world_data(manager: ChunkManager) -> void:
	var generator: WorldGenerator = manager.get_generator()
	for coords: Vector2i in manager._cache:
		var data: ChunkData = manager.get_cached_chunk(coords)
		var expected: ChunkData = generator.generate_chunk(coords)
		_check(data.epoch == manager._epoch and data.terrain == expected.terrain and data.route == expected.route and data.biome == expected.biome, "旧种子任务污染新世界缓存")
	manager._generator_mutex.lock()
	var workers: Array[WorldGenerator] = manager._generator_pool.duplicate()
	manager._generator_mutex.unlock()
	for worker: WorldGenerator in workers:
		_check(worker.world_seed == generator.world_seed, "生成器池残留旧world")
	for id: int in manager._regions:
		var region: Dictionary = manager._regions[id]
		_check(region["spec"] == generator.map_spec(id), "区域root残留旧world MapSpec")
		var region_root: Node2D = region["root"]
		_check(region_root.visible == (id == manager.get_map_spec().node_id), "邻图区root可见性错误")


func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(path)
	_check(error == OK, "截图保存失败%s" % path)


func _check_runtime() -> void:
	# 项目内置autoload由正常SceneTree启动加载，不手工注入替身。
	var game: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_process(false)
	var manager: ChunkManager = game.get_node("ChunkManager")
	var player: PlayerCharacter = game.get_node("Player")
	var camera: Camera2D = player.get_node("Camera2D")
	var minimap: Minimap = game.get_node("GameHUD/HUD/Minimap")
	player.set_physics_process(false)
	game.build_world(18473)
	_check_active_map(game, manager, player, camera, 0)
	await _settle(manager)
	var generator: WorldGenerator = manager.get_generator()
	var initial_epoch: int = manager._epoch
	var pixels: PackedByteArray = _check_minimap(minimap, generator, true)
	await _check_gate_transitions(game, manager, player, camera)
	await _check_camera(game, manager, player, camera)
	_start_workers(game, manager)
	for id: int in [2, 3, 4, 2, 0]:
		game._enter_map(id)
		_check(manager._epoch == initial_epoch, "worker期间切图或回头改变epoch")
		_check_active_map(game, manager, player, camera, id)
	await _settle(manager)
	_check_world_data(manager)
	# 新world重建时还有其它地图worker；setup必须回收旧任务与全部旧区域root。
	game._enter_map(14)
	manager._process(0.0)
	_check(not manager._in_flight.is_empty(), "换seed测试没有派发worker")
	game.build_world(97231)
	_check(manager._epoch == initial_epoch + 1, "换种子未更新epoch")
	_check(minimap._source_generator == manager.get_generator() and minimap._seed == 97231, "换种子残留旧小地图生成器")
	_check(minimap._texture != null, "换种子没有同步重建当前小地图")
	_check_active_map(game, manager, player, camera, 0)
	await _settle(manager)
	_check_world_data(manager)
	var fresh: WorldGenerator = manager.get_generator()
	var fresh_pixels: PackedByteArray = _check_minimap(minimap, fresh, false)
	_check(fresh_pixels != pixels and minimap._seed == 97231, "小地图换seed后未更新")
	if "--capture" in OS.get_cmdline_user_args():
		game.build_world(18473)
		var capture_generator: WorldGenerator = manager.get_generator()
		var capture_spec: MapSpec = capture_generator.map_spec(0)
		for candidate: MapSpec in capture_generator.map_specs():
			var biome: int = capture_generator.sample_biome(candidate.origin + Vector2i(candidate.center))
			if biome == Biome.Kind.FOREST or biome == Biome.Kind.GRASSLAND or biome == Biome.Kind.SAVANNA:
				capture_spec = candidate
				break
		game._enter_map(capture_spec.node_id)
		player.global_position = WorldGenerator.tile_to_world(capture_spec.origin + Vector2i(capture_spec.side_centers[0]))
		camera.reset_smoothing()
		camera.force_update_scroll()
		manager.load_map(capture_spec.node_id)
		await _settle(manager)
		var hud: Control = game.get_node("GameHUD/HUD")
		hud.get_node("StatsLabel").hide()
		hud.get_node("ToastLabel").hide()
		hud._refresh()
		await _capture("res://.godot/continuous-world-preview.png")
		player.global_position = WorldGenerator.tile_to_world(capture_spec.origin + Vector2i(3, 3))
		camera.reset_smoothing()
		camera.force_update_scroll()
		manager.load_map(capture_spec.node_id)
		await _capture("res://.godot/continuous-world-boundary.png")
		game._enter_map(0)
		game._process(0.0)
		var link: Dictionary = capture_generator.gate_links(0)[0]
		player.global_position = WorldGenerator.tile_to_world(link["point"])
		player.velocity = Vector2(float(link["side"]) * 50.0, 0.0)
		game._process(0.0)
		player.velocity = Vector2.ZERO
		await _settle(manager)
		await _capture("res://.godot/continuous-world-transition.png")
	game.queue_free()
	await process_frame
	await process_frame
