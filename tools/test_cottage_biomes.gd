extends SceneTree

## godot --headless --path . --script res://tools/test_cottage_biomes.gd
## 有图形界面时添加 -- --capture，保存实际运行画面到 .godot/。
## 不 preload 或静态引用 GameWorld：等项目 autoload 注册完成后再加载运行场景。
const SEEDS: Array[int] = [1, 18473, 97231, 2147483646]
const VARIANTS: Array[int] = [0, 1]
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
## 包括道路、墙、水岸与家具，留出边界变化余量；同时打印实际值供调参。
const MAX_TERRAIN_CHANGE: float = 0.13
const MAX_BLOCKING_SINGLETON_RATIO: float = 0.005
var _checks: int = 0
var _failures: int = 0
var _tile_samples: int = 0
var _chunk_samples: int = 0
var _bfs_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	Engine.max_fps = 120
	if "--runtime-only" in OS.get_cmdline_user_args():
		await _check_runtime()
		print("COTTAGE_RUNTIME: checks=%d failures=%d" % [_checks, _failures])
		quit(0 if _failures == 0 else 1)
		return
	var cottage_layouts: Dictionary = {}
	var biome_assignments: Dictionary = {}
	for seed_value: int in SEEDS:
		for variant: int in VARIANTS:
			_check_world(seed_value, variant, cottage_layouts, biome_assignments)
	_check(cottage_layouts.size() >= 3, "不同种子的小屋布局缺少多样性")
	_check(biome_assignments.size() >= 3, "不同种子的区域群系分配缺少多样性")
	await _check_runtime()
	print("COTTAGE_BIOMES: checks=%d failures=%d tiles=%d chunks=%d bfs=%d cottage_layouts=%d biome_assignments=%d" % [
		_checks, _failures, _tile_samples, _chunk_samples, _bfs_count, cottage_layouts.size(), biome_assignments.size(),
	])
	quit(0 if _failures == 0 else 1)


## 递归读取所有脚本变量，包含未来新增的 MapSpec / CottageLayout 字段。
## 比较值而非 RefCounted 实例身份，不比较 last_used 等区块运行时字段。
func _snapshot(value: Variant) -> Variant:
	if value is Object:
		var result: Dictionary = {}
		for property: Dictionary in value.get_property_list():
			if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
				result[property["name"]] = _snapshot(value.get(property["name"]))
		return result
	if value is Array:
		var result: Array = []
		for element: Variant in value:
			result.append(_snapshot(element))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _snapshot(value[key])
		return result
	return value


func _check_world(seed_value: int, variant: int, layouts: Dictionary, assignments: Dictionary) -> void:
	var generator := WorldGenerator.new(seed_value, null, variant)
	var replica := WorldGenerator.new(seed_value, null, variant)
	var problems: PackedStringArray = MapValidator.validate(generator)
	_check(problems.is_empty(), "地图硬校验失败 seed=%d variant=%d: %s" % [seed_value, variant, ", ".join(problems)])
	_check(generator.connections() == replica.connections(), "同种子/变体连接不一致")
	var start_id: int = generator.run.start_node()
	_check(start_id == 0, "初始区域应为 START 0")
	var content := MapContent.build(generator)
	var rainforest_combat: bool = false
	var biome_ids := PackedInt32Array()
	var checked_other: int = 0
	for spec: MapSpec in generator.map_specs():
		var context: String = "seed=%d variant=%d node=%d" % [seed_value, variant, spec.node_id]
		var other: MapSpec = replica.map_spec(spec.node_id)
		_check(_snapshot(spec) == _snapshot(other), "整张MapSpec同种子/变体不一致 " + context)
		_check(spec.build_roads() == other.build_roads(), "道路同种子/变体不一致 " + context)
		biome_ids.append(spec.biome_id)
		var kind: int = generator.run.type_of(spec.node_id)
		if kind == RoomType.Kind.COMBAT or kind == RoomType.Kind.BOSS:
			rainforest_combat = rainforest_combat or spec.biome_id == Biome.Kind.TROPICAL_RAINFOREST
		if spec.node_id == start_id:
			_check(content.budget_of(spec.node_id, MapContent.ENEMY) == 0, "初始小屋敌人预算必须为0 " + context)
			_check_cottage(generator, spec)
			if variant == 0 and spec.cottage != null:
				layouts[hash(_snapshot(spec.cottage))] = true
		else:
			_check(spec.cottage == null, "非初始区域不应生成小屋 " + context)
		var cells: Dictionary = _check_chunks(generator, replica, spec, context)
		_check_public_biome(generator, spec, context)
		# 四seed，每seed初图与两个真实存在的其他区域，共12次整图四连通BFS。
		if variant == 0 and (spec.node_id == start_id or checked_other < 2):
			_check_fragmentation(generator, spec, cells, context)
			if spec.node_id != start_id:
				checked_other += 1
	_check(rainforest_combat, "缺少给怪物可用的热带雨林战斗/Boss区域 seed=%d variant=%d" % [seed_value, variant])
	if variant == 0:
		assignments[hash(biome_ids)] = true
		_check(checked_other >= 2, "BFS没有覆盖至少两个非初始区域")


func _check_cottage(generator: WorldGenerator, spec: MapSpec) -> void:
	var context: String = "seed=%d variant=%d" % [generator.world_seed, generator.variant]
	_check(spec.biome_id == Biome.Kind.FOREST, "START必须为森林主题 " + context)
	_check(spec.shape_name() == "起始小屋", "START轮廓名称未更新 " + context)
	_check(spec.ponds.is_empty() and spec.river_width == 0.0, "START不应生成水域 " + context)
	var cottage: Variant = spec.cottage
	_check(cottage != null, "START缺少CottageLayout " + context)
	if cottage == null:
		return
	var bounds: Rect2i = cottage.bounds
	var spawn: Vector2i = cottage.spawn_tile
	var door: Vector2i = cottage.door_tile
	var porch: Vector2i = cottage.porch_tile
	_check(bounds.size.x >= 18 and bounds.size.x <= 24 and bounds.size.y >= 14 and bounds.size.y <= 18, "小屋尺寸超出18–24×14–18 " + context)
	_check(Rect2i(Vector2i.ZERO, spec.extent).encloses(bounds), "小屋超出区域边界 " + context)
	_check(bounds.grow(-1).has_point(spawn) and spawn == bounds.get_center(), "spawn不在屋内中心 " + context)
	_check(door.x == bounds.end.x - 1 and door.y > bounds.position.y and door.y < bounds.end.y - 1, "门不在右墙 " + context)
	_check(porch == door + Vector2i(3, 0) and not bounds.has_point(porch), "porch不在门右侧屋外3格 " + context)
	_check(generator.start_world_position().is_equal_approx(WorldGenerator.tile_to_world(spec.origin + spawn)), "初始世界出生点不在屋内spawn " + context)
	_check(cottage.terrain_at(spawn) == Terrain.Kind.STONE and generator.is_walkable(spec.origin + spawn), "屋内spawn必须为可走石地板 " + context)
	_check(cottage.terrain_at(bounds.position - Vector2i.ONE) == -1, "屋外terrain_at应返回-1 " + context)
	var furniture: Array = cottage.furniture
	_check(not furniture.is_empty(), "小屋没有家具 " + context)
	var furniture_ok: bool = true
	for item: Dictionary in furniture:
		if not item.has("kind") or not item.has("rect") or not item["rect"] is Rect2i:
			furniture_ok = false
			continue
		var rect: Rect2i = item["rect"]
		furniture_ok = furniture_ok and rect.has_area() and bounds.grow(-1).encloses(rect)
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				var tile := Vector2i(x, y)
				furniture_ok = furniture_ok and cottage.terrain_at(tile) == Terrain.Kind.MOUNTAIN and not generator.is_walkable(spec.origin + tile) and not String(cottage.label_at(tile)).is_empty()
	_check(furniture_ok, "家具rect/名称/阻挡不符合约定 " + context)
	var walls_ok: bool = true
	var floor_ok: bool = true
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var tile := Vector2i(x, y)
			var terrain: int = cottage.terrain_at(tile)
			var on_wall: bool = x == bounds.position.x or x == bounds.end.x - 1 or y == bounds.position.y or y == bounds.end.y - 1
			# 允许以door_tile为中心的三格门洞，其他墙格必须保持阻挡。
			var in_doorway: bool = x == door.x and absi(y - door.y) <= 1
			if on_wall and not in_doorway:
				walls_ok = walls_ok and terrain == Terrain.Kind.MOUNTAIN and generator.sample_terrain(spec.origin + tile) == terrain and not generator.is_walkable(spec.origin + tile)
			elif terrain == Terrain.Kind.STONE:
				floor_ok = floor_ok and generator.sample_terrain(spec.origin + tile) == terrain and generator.is_walkable(spec.origin + tile)
			else:
				floor_ok = floor_ok and terrain == Terrain.Kind.MOUNTAIN
	_check(walls_ok, "木墙被道路冲开或意外可走 " + context)
	_check(floor_ok, "小屋地板采样或通行不一致 " + context)
	var doorway_ok: bool = cottage.terrain_at(door) == Terrain.Kind.STONE
	for x: int in range(door.x - 1, porch.x + 1):
		doorway_ok = doorway_ok and generator.is_walkable(spec.origin + Vector2i(x, door.y))
	_check(doorway_ok, "门内至porch没有贯通 " + context)
	var roads: PackedFloat32Array = spec.build_roads()
	var indoor_segments: int = 0
	var roads_ok: bool = roads.size() % 5 == 0
	var porch_center: Vector2 = Vector2(porch) + Vector2.ONE * 0.5
	for base: int in range(0, roads.size(), 5):
		var a := Vector2(roads[base], roads[base + 1])
		var b := Vector2(roads[base + 2], roads[base + 3])
		if Rect2(bounds).has_point(a) or Rect2(bounds).has_point(b):
			indoor_segments += 1
			roads_ok = roads_ok and a.is_equal_approx(Vector2(spawn) + Vector2.ONE * 0.5) and b.is_equal_approx(porch_center) and roads[base + 4] == -1.0
		# 直接通门/侧庭的支路必须由屋外porch开始，侧庭之间的回路不受此约束。
		var connects_gate: bool = is_equal_approx(a.x, 0.5) or is_equal_approx(b.x, 0.5) or is_equal_approx(a.x, spec.extent.x - 0.5) or is_equal_approx(b.x, spec.extent.x - 0.5)
		var connects_side: bool = spec.side_centers.has(b)
		if connects_gate or (connects_side and not spec.side_centers.has(a)):
			roads_ok = roads_ok and (a.is_equal_approx(porch_center) or b.is_equal_approx(porch_center))
	_check(roads_ok and indoor_segments == 1, "小屋道路必须仅spawn→porch直线穿门，其余支路从porch连接 " + context)


## 生成每个覆盖区块；一次拷贝区域矩形中的全部格子供统计与BFS复用。
func _check_chunks(generator: WorldGenerator, replica: WorldGenerator, spec: MapSpec, context: String) -> Dictionary:
	var terrain := PackedByteArray()
	var walkable := PackedByteArray()
	terrain.resize(spec.extent.x * spec.extent.y)
	walkable.resize(terrain.size())
	var first: Vector2i = WorldGenerator.tile_to_chunk(spec.origin)
	var last: Vector2i = WorldGenerator.tile_to_chunk(spec.origin + spec.extent - Vector2i.ONE)
	var deterministic: bool = true
	var single_biome: bool = true
	var no_start_water: bool = true
	for cy: int in range(first.y, last.y + 1):
		for cx: int in range(first.x, last.x + 1):
			var coords := Vector2i(cx, cy)
			var data: ChunkData = generator.generate_chunk(coords)
			var copy: ChunkData = replica.generate_chunk(coords)
			_chunk_samples += 1
			deterministic = deterministic and data.terrain == copy.terrain and data.biome == copy.biome and data.route == copy.route
			var begin: Vector2i = (coords * WorldGenerator.CHUNK_SIZE - spec.origin).max(Vector2i.ZERO)
			var end: Vector2i = ((coords + Vector2i.ONE) * WorldGenerator.CHUNK_SIZE - spec.origin).min(spec.extent)
			for y: int in range(begin.y, end.y):
				for x: int in range(begin.x, end.x):
					var chunk_local: Vector2i = spec.origin + Vector2i(x, y) - coords * WorldGenerator.CHUNK_SIZE
					var source: int = chunk_local.y * WorldGenerator.CHUNK_SIZE + chunk_local.x
					var index: int = y * spec.extent.x + x
					terrain[index] = data.terrain[source]
					walkable[index] = 1 if Terrain.is_walkable(data.terrain[source]) or data.route[source] != Route.Kind.NONE else 0
					single_biome = single_biome and data.biome[source] == spec.biome_id
					if spec.cottage != null:
						no_start_water = no_start_water and not Terrain.is_water(data.terrain[source])
					_tile_samples += 1
	_check(deterministic, "整图区块地形/群系/道路不确定 " + context)
	_check(single_biome, "矩形内存在其他群系（含边缘、小屋、池塘） " + context)
	_check(no_start_water, "初始区域仍有水格 " + context)
	return {"terrain": terrain, "walkable": walkable}


func _check_public_biome(generator: WorldGenerator, spec: MapSpec, context: String) -> void:
	var correct: bool = true
	# 公共sample_biome再检查边界、内部网格、水域中心及房内，防止区块与采样分歧。
	for y: int in spec.extent.y:
		correct = correct and generator.sample_biome(spec.origin + Vector2i(0, y)) == spec.biome_id and generator.sample_biome(spec.origin + Vector2i(spec.extent.x - 1, y)) == spec.biome_id
	for x: int in spec.extent.x:
		correct = correct and generator.sample_biome(spec.origin + Vector2i(x, 0)) == spec.biome_id and generator.sample_biome(spec.origin + Vector2i(x, spec.extent.y - 1)) == spec.biome_id
	for y: int in range(1, spec.extent.y - 1, 5):
		for x: int in range(1, spec.extent.x - 1, 5):
			correct = correct and generator.sample_biome(spec.origin + Vector2i(x, y)) == spec.biome_id
	for base: int in range(0, spec.ponds.size(), 4):
		correct = correct and generator.sample_biome(spec.origin + Vector2i(int(spec.ponds[base]), int(spec.ponds[base + 1]))) == spec.biome_id
	if spec.cottage != null:
		correct = correct and generator.sample_biome(spec.origin + spec.cottage.spawn_tile) == spec.biome_id
	_check(correct, "sample_biome违反区域单一群系 " + context)


func _flood(cells: PackedByteArray, width: int, height: int, start: int, target: int, mark: int) -> int:
	var queue := PackedInt32Array([start])
	cells[start] = mark
	var head: int = 0
	while head < queue.size():
		var index: int = queue[head]
		head += 1
		var point := Vector2i(index % width, index / width)
		for delta: Vector2i in DIRECTIONS:
			var next: Vector2i = point + delta
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			var next_index: int = next.y * width + next.x
			if cells[next_index] == target:
				cells[next_index] = mark
				queue.append(next_index)
	return queue.size()


func _check_fragmentation(generator: WorldGenerator, spec: MapSpec, data: Dictionary, context: String) -> void:
	_bfs_count += 1
	var terrain: PackedByteArray = data["terrain"]
	var cells: PackedByteArray = data["walkable"].duplicate()
	var width: int = spec.extent.x
	var height: int = spec.extent.y
	var ground_count: int = 0
	var changes: int = 0
	var edges: int = 0
	for y: int in height:
		for x: int in width:
			var index: int = y * width + x
			ground_count += int(cells[index])
			if x + 1 < width:
				edges += 1
				changes += 1 if terrain[index] != terrain[index + 1] else 0
			if y + 1 < height:
				edges += 1
				changes += 1 if terrain[index] != terrain[index + width] else 0
	var spawn: Vector2i = WorldGenerator.world_to_tile(generator.entry_position(spec.node_id)) - spec.origin
	var spawn_index: int = spawn.y * width + spawn.x
	var reachable: int = 0
	if Rect2i(Vector2i.ZERO, spec.extent).has_point(spawn) and cells[spawn_index] == 1:
		reachable = _flood(cells, width, height, spawn_index, 1, 2)
	else:
		_check(false, "BFS起点不可走 " + context)
	var destinations_ok: bool = true
	for link: Dictionary in generator.gate_links(spec.node_id):
		var local: Vector2i = link["point"] - spec.origin
		destinations_ok = destinations_ok and cells[local.y * width + local.x] == 2
	for center: Vector2 in spec.side_centers:
		var local := Vector2i(center.floor())
		destinations_ok = destinations_ok and cells[local.y * width + local.x] == 2
	if spec.cottage != null:
		for local: Vector2i in [spec.cottage.door_tile, spec.cottage.porch_tile]:
			destinations_ok = destinations_ok and cells[local.y * width + local.x] == 2
	_check(destinations_ok, "spawn无法到达有效gate/side_center/门/porch " + context)
	var ground_clusters: int = 1 if reachable > 0 else 0
	var largest_ground: int = reachable
	var blocking_clusters: int = 0
	var blocking_singletons: int = 0
	for index: int in cells.size():
		if cells[index] == 1:
			ground_clusters += 1
			largest_ground = maxi(largest_ground, _flood(cells, width, height, index, 1, 3))
		elif cells[index] == 0:
			blocking_clusters += 1
			if _flood(cells, width, height, index, 0, 4) == 1:
				blocking_singletons += 1
	var reach_ratio: float = float(reachable) / maxi(ground_count, 1)
	var main_ratio: float = float(largest_ground) / maxi(ground_count, 1)
	var change_ratio: float = float(changes) / maxi(edges, 1)
	var singleton_ratio: float = float(blocking_singletons) / cells.size()
	_check(reach_ratio >= 0.95 and main_ratio >= 0.95, "可走主连通块/出生连通块少于95%% %s reachable=%.4f main=%.4f" % [context, reach_ratio, main_ratio])
	_check(change_ratio <= MAX_TERRAIN_CHANGE, "地形邻格变更过于频繁 %s ratio=%.4f" % [context, change_ratio])
	_check(singleton_ratio <= MAX_BLOCKING_SINGLETON_RATIO, "单格阻挡碎片过多 %s count=%d ratio=%.5f" % [context, blocking_singletons, singleton_ratio])
	print("FRAGMENTATION: %s biome=%s tiles=%d terrain_change=%.4f reachable=%.4f ground_clusters=%d blocking_clusters=%d blocking_singletons=%d (%.5f)" % [
		context, Biome.name_of(spec.biome_id), cells.size(), change_ratio, reach_ratio, ground_clusters, blocking_clusters, blocking_singletons, singleton_ratio,
	])


func _camera_limits(camera: Camera2D, spec: MapSpec) -> void:
	_check(camera.limit_left == spec.origin.x * WorldGenerator.TILE_SIZE and camera.limit_top == spec.origin.y * WorldGenerator.TILE_SIZE and camera.limit_right == (spec.origin.x + spec.extent.x) * WorldGenerator.TILE_SIZE and camera.limit_bottom == (spec.origin.y + spec.extent.y) * WorldGenerator.TILE_SIZE, "相机limits未同步当前区域")


func _settle(manager: Node) -> void:
	for _frame: int in 600:
		await process_frame
		if manager.map_ready():
			return
	_check(false, "当前区域600帧内未加载完成")


func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "截图图像为空 " + path)
	if image == null or image.is_empty():
		return
	var error: Error = image.save_png(path)
	_check(error == OK and FileAccess.file_exists(path), "截图保存失败 error=%d %s" % [error, path])


## 切图释放怪物时，全局感知队列可能仍保存它的旧引用。
func _check_freed_perception_queue() -> void:
	var service: Node = root.get_node_or_null("PerceptionManager")
	_check(service != null, "共享感知服务未注册")
	if service == null:
		return
	var previous_budget: int = service.get("_budget_used")
	service.set("_budget_used", service.get("max_evaluations_per_frame"))
	var pending := BaseMonster.new()
	_check(not service.request_evaluation(pending), "预算满时怪物感知应排队")
	pending.free()
	service.set("_budget_used", 0)
	service.call("_process", 0.0)
	_check(service.get("_queue").is_empty(), "切图释放的旧怪物仍留在感知队列")
	service.set("_budget_used", previous_budget)


func _check_runtime() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 18473)
	# 必须 deferred load，避免 GameWorld 对 autoload 的引用提前编译。
	var scene: PackedScene = load("res://scenes/game/game_world.tscn")
	var game: Node2D = scene.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	var manager: Node = game.get_node("ChunkManager")
	var player: Node2D = game.get_node("Player")
	var camera: Camera2D = player.get_node("Camera2D")
	player.set_physics_process(false)
	game.get_node("MonsterSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	var generator: WorldGenerator = manager.get_generator()
	var start: MapSpec = generator.map_spec(0)
	_check(start.cottage != null, "运行时初图缺少小屋")
	if start.cottage == null:
		game.queue_free()
		await process_frame
		return
	var local_player: Vector2i = WorldGenerator.world_to_tile(player.global_position) - start.origin
	_check(local_player == start.cottage.spawn_tile and start.cottage.bounds.grow(-1).has_point(local_player) and player.can_stand_at(player.global_position), "运行时玩家初始位置不在可走屋内spawn")
	var wall_tile: Vector2i = start.origin + start.cottage.bounds.position
	_check(not player.can_stand_at(WorldGenerator.tile_to_world(wall_tile)), "运行时玩家可穿过木墙")
	if not start.cottage.furniture.is_empty():
		var furniture_rect: Rect2i = start.cottage.furniture[0]["rect"]
		_check(not player.can_stand_at(WorldGenerator.tile_to_world(start.origin + furniture_rect.get_center())), "运行时玩家可穿过家具")
	var view: CanvasItem = game.get_node_or_null("CottageView") as CanvasItem
	_check(view != null and view.is_visible_in_tree(), "初图CottageView应可见")
	_camera_limits(camera, start)
	if "--capture" in OS.get_cmdline_user_args():
		game.get_node("GameHUD/HUD").get("stats_label").hide()
		await _settle(manager)
		await _capture("res://.godot/cottage-preview.png")
	_check_freed_perception_queue()
	var original_layout: Variant = _snapshot(start.cottage)
	var original_world: Array = []
	for spec: MapSpec in generator.map_specs():
		original_world.append(_snapshot(spec))
	var bag: Node = game.get_node("GameHUD/BagUi")
	var alchemy: Node = game.get_node("GameHUD/Alchemy")
	var controller: Variant = player.get("weapon_controller")
	_check(controller.equipped_weapon != null, "新版快捷栏开局选中武器未装备")
	var initial_weapon: Variant = controller.equipped_weapon
	player.inventory.select_handy_slot(1)
	_check(controller.equipped_weapon != null and controller.equipped_weapon != initial_weapon, "切换物品栏未自动装备另一把武器")
	var equipped: Variant = controller.equipped_weapon
	player.take_damage(3)
	var health: int = player.get("health")
	game._enter_map(2)
	await process_frame
	_check(view != null and not view.is_visible_in_tree(), "切到区域2后CottageView未隐藏")
	_camera_limits(camera, manager.get_map_spec())
	_check(player.get("health") == health and controller.equipped_weapon == equipped, "切图未保留生命与装备")
	_check(game.get_node("GameHUD/BagUi") == bag and game.get_node("GameHUD/Alchemy") == alchemy, "切图未保留背包/炼金实例")
	game._enter_map(0)
	await process_frame
	_check(view != null and view.is_visible_in_tree(), "返回区域0后CottageView未显示")
	_check(player.get("health") == health and controller.equipped_weapon == equipped, "回初图未保留生命与装备")
	_camera_limits(camera, manager.get_map_spec())
	if "--capture" in OS.get_cmdline_user_args():
		var selected: MapSpec = null
		for spec: MapSpec in generator.map_specs():
			if spec.node_id != 0 and spec.biome_id == Biome.Kind.TROPICAL_RAINFOREST:
				selected = spec
				break
		_check(selected != null, "截图未找到非初始热带雨林区域")
		if selected != null:
			game._enter_map(selected.node_id)
			await _settle(manager)
			await _capture("res://.godot/region-biome-preview.png")
	game.build_world(97231)
	await process_frame
	var fresh: WorldGenerator = manager.get_generator()
	var fresh_world: Array = []
	for spec: MapSpec in fresh.map_specs():
		fresh_world.append(_snapshot(spec))
	var fresh_start: MapSpec = fresh.map_spec(0)
	_check(fresh.world_seed == 97231 and fresh_world != original_world, "换seed重建未改变地图内容")
	_check(fresh_start.cottage != null and _snapshot(fresh_start.cottage) != original_layout, "换seed重建未改变小屋布局")
	# 装备保留看“同一把武器”而非同一个实例：局内成长会在重建世界时拿基础定义重新叠卡生成武器副本，
	# 实例必然换新，但玩家手上仍是同一把。
	_check(
		player.get("health") == player.get("max_health") and controller.equipped_weapon != null and controller.equipped_weapon.id == equipped.id,
		"换世界生命重置/装备保留行为改变"
	)
	_check(game.get_node("GameHUD/BagUi") == bag and game.get_node("GameHUD/Alchemy") == alchemy, "换世界未保留背包/炼金实例")
	_check(fresh_start.cottage != null and WorldGenerator.world_to_tile(player.global_position) - fresh_start.origin == fresh_start.cottage.spawn_tile, "换世界未重新出生于小屋")
	var fresh_view: CanvasItem = game.get_node_or_null("CottageView") as CanvasItem
	_check(fresh_view != null and fresh_view.is_visible_in_tree(), "换世界新小屋未显示")
	_camera_limits(camera, fresh_start)
	game.queue_free()
	await process_frame
	await process_frame
