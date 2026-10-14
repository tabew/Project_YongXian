class_name WorldGenerator
extends RefCounted

## 传统 RPG 陆地箱庭：随机庭院、山谷和林间空地，以山壁 / 密林围合。
## 主干与岔路通过出入口瞬间切换，周围仍是陆地，水域只作为少量河流与池塘。
## 同种子同坐标的布局、地形与道路确定一致，工作线程使用独立生成器。

const CHUNK_SIZE: int = 32
const TILE_SIZE: int = 16

## 保留既有生成器的开阔出生点查询接口。
const SPAWN_CHECK_RADIUS: int = 3
const SPAWN_OPEN_RATIO: float = 0.72
const SPAWN_NOT_FOUND: Vector2i = Vector2i(2147483647, 2147483647)

const MOUNTAIN_LEVEL: float = 0.56
const ALPINE_LEVEL: float = 0.76
const ALTITUDE_COOLING: float = 0.34
const CLIMATE_CONTRAST: float = 1.90

## 箱庭边缘的山脚过渡，以及河湖的岸边宽度。
const WALL_FOOT_WIDTH: float = 3.0
const WATER_BANK_WIDTH: float = 1.4

var world_seed: int = 0
## 同一主种子下的布局变体；不改变世界身份，只改变房间图与模板的抽样。
var variant: int = 0
var run: RoomGraph = null
## 骨架参数；留空用默认值。
var config: MapConfig = null
## 本世界的统一随机源；所有地图随机都从这里派生。
var rng: MapRng = null

var _temperature := FastNoiseLite.new()
var _humidity := FastNoiseLite.new()
var _variation := FastNoiseLite.new()
var _groves := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _edges := FastNoiseLite.new()

# 每线程一个实例，所以这些缓存天然是线程局部的
var _map_cache: Dictionary = {}
var _road_cache: Dictionary = {}
var _specs: Array[MapSpec] = []
var _connections: Array[Dictionary] = []
var _map_bins: Dictionary = {}
var _gate_cache: Dictionary = {}
const REGION_GAP: int = 12

# _classify 的输出缓冲，避免为每个格子分配对象
var _last_terrain: int = Terrain.Kind.DEEP_WATER
var _last_biome: int = Biome.Kind.DEEP_OCEAN
var _last_route: int = Route.Kind.NONE
var _last_map: MapSpec = null
var _last_gate: int = -1
## 同一物理帧的只读采样共用结果；各线程持有自己的生成器实例。
var _query_frame: int = -1
var _query_tiles: Dictionary = {}


func _init(seed_value: int = 0, map_config: MapConfig = null, variant_index: int = 0) -> void:
	world_seed = seed_value if seed_value != 0 else random_seed()
	config = map_config if map_config != null else MapConfig.new()
	variant = variant_index
	rng = MapRng.new(world_seed)
	run = RoomGraph.plan(world_seed, config, variant)
	_build_layout()
	_configure_noise()


func _configure_noise() -> void:
	_temperature.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_temperature.seed = rng.noise_seed(0)
	_temperature.frequency = 0.0035
	_temperature.fractal_octaves = 2

	_humidity.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_humidity.seed = rng.noise_seed(1)
	_humidity.frequency = 0.0042
	_humidity.fractal_octaves = 2

	_variation.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_variation.seed = rng.noise_seed(2)
	# 细节尺度拉大：一个噪声簇占几十格，避免彩色小碎片铺满箱庭。
	_variation.frequency = 0.007
	_variation.fractal_octaves = 1

	_groves.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_groves.seed = rng.noise_seed(3)
	_groves.frequency = 0.009
	_groves.fractal_octaves = 2
	_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridges.seed = rng.noise_seed(4)
	_ridges.frequency = 0.013
	_ridges.fractal_octaves = 2
	_edges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_edges.seed = rng.noise_seed(5)
	_edges.frequency = 0.018
	_edges.fractal_octaves = 2


static func random_seed() -> int:
	return MapRng.random_seed()


# ------------------------------------------------------------ 坐标换算

static func world_to_tile(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(TILE_SIZE)),
		floori(world_position.y / float(TILE_SIZE))
	)


static func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(
		(float(tile.x) + 0.5) * TILE_SIZE,
		(float(tile.y) + 0.5) * TILE_SIZE
	)


static func tile_to_chunk(tile: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile.x) / float(CHUNK_SIZE)),
		floori(float(tile.y) / float(CHUNK_SIZE))
	)


# ------------------------------------------------------------ 箱庭布局与出口关系

func map_spec(map_node_id: int) -> MapSpec:
	return _map_cache.get(map_node_id)


func map_specs() -> Array[MapSpec]:
	return _specs.duplicate()


## 供地图连通性检查与世界总览使用。坐标为世界格子中心。
func connections() -> Array[Dictionary]:
	return _connections.duplicate(true)


func _build_layout() -> void:
	var used_extents: Dictionary = {}
	var floor_widths: PackedInt32Array = PackedInt32Array()
	var layout_rng: RandomNumberGenerator = rng.layout_rng()
	for floor_ids: PackedInt32Array in run.floors:
		var width: int = 0
		for id: int in floor_ids:
			var spec: MapSpec = MapSpec.create(world_seed, id, run.has_entrance(id), run.exit_count(id), run.type_of(id), variant)
			while used_extents.has(spec.extent):
				# 只扩展包围范围；主庭中心和已经生成的庭室保持一致。
				spec.extent.x += 1
				spec.axes.x = float(spec.extent.x) * 0.4
			used_extents[spec.extent] = true
			spec.size = maxi(spec.extent.x, spec.extent.y)
			spec.west_gates.clear()
			spec.west_gate_y = -1
			_map_cache[id] = spec
			_specs.append(spec)
			width = maxi(width, spec.extent.x)
		floor_widths.append(width)

	_assign_region_biomes()
	var cursor_x: int = 0
	var main_y: int = 0
	for floor_index: int in run.floors.size():
		var main: MapSpec = map_spec(run.floors[floor_index][0])
		if floor_index > 0:
			main_y = clampi(main_y + layout_rng.randi_range(-28, 28), -64, 64)
		main.origin = Vector2i(cursor_x, main_y - int(main.center.y))
		for id: int in run.floors[floor_index]:
			if id == main.node_id:
				continue
			var branch: MapSpec = map_spec(id)
			var separation: int = layout_rng.randi_range(6, 14)
			var y: int = main.origin.y - branch.extent.y - separation
			if layout_rng.randf() < 0.5:
				y = main.origin.y + main.extent.y + separation
			branch.origin = Vector2i(cursor_x + layout_rng.randi_range(0, floor_widths[floor_index] - branch.extent.x), y)
		cursor_x += floor_widths[floor_index] + layout_rng.randi_range(6, REGION_GAP)

	# 出口靠向小地图里的目标方向，两端只保存瞬切关系，不生成中间道路。
	for spec: MapSpec in _specs:
		for exit_index: int in run.exit_count(spec.node_id):
			var target: MapSpec = map_spec(run.target_of(spec.node_id, exit_index))
			var source_y: int = int(spec.center.y)
			if RunGraph.variant_of(target.node_id) == RunGraph.BRANCH_VARIANT:
				source_y = int(spec.extent.y * (0.25 if target.origin.y < spec.origin.y else 0.75))
			var target_y: int = int(target.center.y)
			if RunGraph.variant_of(spec.node_id) == RunGraph.BRANCH_VARIANT:
				target_y = int(target.extent.y * (0.25 if spec.origin.y < target.origin.y else 0.75))
			spec.east_gates[exit_index] = source_y
			target.west_gates.append(target_y)
			target.west_gate_y = target.west_gates[0]
			var a: Vector2 = Vector2(spec.origin) + Vector2(float(spec.extent.x) - 0.5, float(source_y) + 0.5)
			var b: Vector2 = Vector2(target.origin) + Vector2(0.5, float(target_y) + 0.5)
			_connections.append({"a": a, "b": b, "from": spec.node_id, "to": target.node_id, "exit": exit_index, "entrance": target.west_gates.size() - 1})

	for spec: MapSpec in _specs:
		_index_bounds(_map_bins, Rect2(Vector2(spec.origin), Vector2(spec.extent)), spec)


## 群系是区域属性，树林、河岸和屋内都保留该箱庭的主题身份。
func _assign_region_biomes() -> void:
	var themes: PackedInt32Array = RegionBiomes.sequence(world_seed, variant)
	var rainforest: MapSpec = null
	var combat: MapSpec = null
	var has_rainforest_combat: bool = false
	for spec: MapSpec in _specs:
		var kind: int = run.type_of(spec.node_id)
		spec.biome_id = Biome.Kind.FOREST if kind == RoomType.Kind.START else themes[posmod(spec.node_id - 2, themes.size())]
		if spec.biome_id == Biome.Kind.TROPICAL_RAINFOREST and rainforest == null:
			rainforest = spec
		if kind == RoomType.Kind.COMBAT or kind == RoomType.Kind.BOSS:
			if not config.combat_biomes.is_empty() and not config.combat_biomes.has(spec.biome_id):
				spec.biome_id = config.combat_biomes[posmod(spec.node_id - 2, config.combat_biomes.size())]
			if combat == null:
				combat = spec
			if spec.biome_id == Biome.Kind.TROPICAL_RAINFOREST:
				has_rainforest_combat = true
	# 允许雨林时保留至少一个雨林战斗区域；其他怪物池不强制加入不支持的群系。
	var allows_rainforest: bool = config.combat_biomes.is_empty() or config.combat_biomes.has(Biome.Kind.TROPICAL_RAINFOREST)
	if allows_rainforest and not has_rainforest_combat and combat != null:
		if rainforest != null:
			rainforest.biome_id = combat.biome_id
		combat.biome_id = Biome.Kind.TROPICAL_RAINFOREST
	# 正式怪物池包含鳄鱼时保留沼泽战斗区域；起点和非战斗房型不改。
	if config.combat_biomes.has(Biome.Kind.SWAMP):
		var has_swamp_combat: bool = false
		var swamp_target: MapSpec = null
		for spec: MapSpec in _specs:
			if run.type_of(spec.node_id) in [RoomType.Kind.COMBAT, RoomType.Kind.BOSS]:
				has_swamp_combat = has_swamp_combat or spec.biome_id == Biome.Kind.SWAMP
				if spec.biome_id != Biome.Kind.TROPICAL_RAINFOREST:
					swamp_target = spec
		if not has_swamp_combat and swamp_target != null:
			swamp_target.biome_id = Biome.Kind.SWAMP
	for spec: MapSpec in _specs:
		spec.boundary_kind = RegionBiomes.boundary_for(spec.biome_id)
		spec.ensure_swamp_water()


func _index_bounds(bins: Dictionary, bounds: Rect2, item: Variant) -> void:
	var first: Vector2i = tile_to_chunk(Vector2i(floori(bounds.position.x), floori(bounds.position.y)))
	var last: Vector2i = tile_to_chunk(Vector2i(ceili(bounds.end.x), ceili(bounds.end.y)))
	for cy: int in range(first.y, last.y + 1):
		for cx: int in range(first.x, last.x + 1):
			var key := Vector2i(cx, cy)
			if not bins.has(key):
				bins[key] = []
			bins[key].append(item)


func _spec_at(tile: Vector2i) -> MapSpec:
	var candidates: Array = _map_bins.get(tile_to_chunk(tile), [])
	for spec: MapSpec in candidates:
		var local: Vector2i = tile - spec.origin
		if spec.contains_local(local.x, local.y):
			return spec
	return null


## 出口和入口都是瞬切点，多前驱区域分别保留各自的回程出口。
func gate_links(map_node_id: int) -> Array[Dictionary]:
	if _gate_cache.has(map_node_id):
		return _gate_cache[map_node_id]
	var links: Array[Dictionary] = []
	for connection: Dictionary in _connections:
		if connection["from"] == map_node_id:
			var source: MapSpec = map_spec(map_node_id)
			var target: MapSpec = map_spec(connection["to"])
			var y: int = source.east_gates[connection["exit"]]
			links.append({"side": 1, "y": y, "target": target.node_id,
				"arrival_side": -1, "arrival_y": target.west_gates[connection["entrance"]],
				"point": source.origin + Vector2i(source.extent.x - 1, y)})
		elif connection["to"] == map_node_id:
			var source: MapSpec = map_spec(connection["from"])
			var target: MapSpec = map_spec(map_node_id)
			var y: int = target.west_gates[connection["entrance"]]
			links.append({"side": -1, "y": y, "target": source.node_id,
				"arrival_side": 1, "arrival_y": source.east_gates[connection["exit"]],
				"point": target.origin + Vector2i(0, y)})
	_gate_cache[map_node_id] = links
	return links


## 落点沿目标箱庭实际道路向里缩八格，保证可走且不会立刻触发回程。
func entry_position(map_node_id: int, side: int = 0, gate_y: int = -1) -> Vector2:
	var spec: MapSpec = map_spec(map_node_id)
	if side == 0 or gate_y < 0:
		return tile_to_world(spec.origin + Vector2i(spec.center))
	var roads: PackedFloat32Array = _map_roads(map_node_id)
	var gate := Vector2(0.5 if side < 0 else float(spec.extent.x) - 0.5, float(gate_y) + 0.5)
	for base: int in range(0, roads.size(), 5):
		var a := Vector2(roads[base], roads[base + 1])
		var b := Vector2(roads[base + 2], roads[base + 3])
		if a.distance_to(gate) > 0.01 and b.distance_to(gate) > 0.01:
			continue
		var dx: float = b.x - a.x
		if absf(dx) < 0.001:
			continue
		var target_x: float = 8.5 if side < 0 else float(spec.extent.x) - 8.5
		var t: float = clampf((target_x - a.x) / dx, 0.0, 1.0)
		var delta: Vector2 = b - a
		var normal: Vector2 = Vector2(delta.y, -delta.x).normalized()
		var point: Vector2 = a.lerp(b, t) + normal * MapSpec.road_offset(t, roads[base + 4])
		return tile_to_world(spec.origin + Vector2i(point.floor()))
	return tile_to_world(spec.origin + Vector2i(spec.center))


## 这张地图的路段（带缓存）。
func _map_roads(map_node_id: int) -> PackedFloat32Array:
	if _road_cache.has(map_node_id):
		return _road_cache[map_node_id]
	var data: PackedFloat32Array = map_spec(map_node_id).build_roads()
	if _road_cache.size() >= 256:
		_road_cache.clear()
	_road_cache[map_node_id] = data
	return data


## 一局开始时的落脚点：第一张地图的主庭中心（路一定穿过中心，所以这里必定可走）。
## 从指定位置寻找开阔道路；箱庭外找不到时回到初始箱庭主庭。
func find_spawn(origin: Vector2i = Vector2i.ZERO, max_radius: int = 320) -> Vector2i:
	var on_road: Vector2i = _search_spawn(origin, max_radius, true)
	if on_road != SPAWN_NOT_FOUND:
		return on_road
	var anywhere: Vector2i = _search_spawn(origin, max_radius, false)
	if anywhere != SPAWN_NOT_FOUND:
		return anywhere
	return world_to_tile(start_world_position())


func _search_spawn(origin: Vector2i, max_radius: int, require_road: bool) -> Vector2i:
	if is_open_area(origin, require_road):
		return origin
	var radius: int = 6
	while radius <= max_radius:
		var steps: int = maxi(8, radius / 4)
		for step: int in steps:
			var angle: float = TAU * float(step) / float(steps)
			var candidate := Vector2i(origin.x + int(roundf(cos(angle) * float(radius))), origin.y + int(roundf(sin(angle) * float(radius))))
			if is_open_area(candidate, require_road):
				return candidate
		radius += 6
	return SPAWN_NOT_FOUND


func is_open_area(tile: Vector2i, require_road: bool = false) -> bool:
	_classify(tile.x, tile.y)
	if not Terrain.is_walkable(_last_terrain) and _last_route == Route.Kind.NONE:
		return false
	if require_road and _last_route == Route.Kind.NONE:
		return false
	var walkable: int = 0
	var total: int = 0
	for dy: int in range(-SPAWN_CHECK_RADIUS, SPAWN_CHECK_RADIUS + 1):
		for dx: int in range(-SPAWN_CHECK_RADIUS, SPAWN_CHECK_RADIUS + 1):
			total += 1
			if is_walkable(tile + Vector2i(dx, dy)):
				walkable += 1
	return float(walkable) / float(total) >= SPAWN_OPEN_RATIO


func start_world_position() -> Vector2:
	var spec: MapSpec = map_spec(run.start_node())
	return tile_to_world(Vector2i(
		spec.origin.x + int(spec.center.x),
		spec.origin.y + int(spec.center.y)
	))


## 兼容旧接口的入口定位；完整多入口切换使用 gate_links 与 entry_position。
func gate_entry_position(map_node_id: int, gate: int) -> Vector2:
	var spec: MapSpec = map_spec(map_node_id)
	if gate <= 0:
		return entry_position(map_node_id, -1, spec.west_gate_y)
	var east_index: int = gate - 1
	if east_index >= spec.east_gates.size():
		return entry_position(map_node_id)
	return entry_position(map_node_id, 1, spec.east_gates[east_index])


# ------------------------------------------------------------ 生成

## 生成一个区块。可以在工作线程里调用。
func generate_chunk(chunk_coords: Vector2i, epoch: int = 0) -> ChunkData:
	var data := ChunkData.create(chunk_coords, CHUNK_SIZE)
	data.epoch = epoch

	var origin_x: int = chunk_coords.x * CHUNK_SIZE
	var origin_y: int = chunk_coords.y * CHUNK_SIZE

	var index: int = 0
	for local_y: int in CHUNK_SIZE:
		for local_x: int in CHUNK_SIZE:
			_classify(origin_x + local_x, origin_y + local_y)
			data.terrain[index] = _last_terrain
			data.biome[index] = _last_biome
			data.route[index] = _last_route
			index += 1

	data.last_used = Time.get_ticks_msec()
	return data


func sample_terrain(tile: Vector2i) -> int:
	return _query_terrain_route(tile) & 255


func sample_biome(tile: Vector2i) -> int:
	# 群系是整张箱庭属性，查群系无需重新采样地形噪声和道路。
	var spec: MapSpec = _spec_at(tile)
	return spec.biome_id if spec != null else Biome.Kind.MOUNTAIN


func sample_route(tile: Vector2i) -> int:
	return (_query_terrain_route(tile) >> 8) & 255


## 这一格是哪张地图的；地图之外返回 null。
func sample_map(tile: Vector2i) -> MapSpec:
	return _spec_at(tile)


## 这一格是不是路口：-1 不是，0 西侧入口，1 起是东侧第 n 个出口。
func sample_gate(tile: Vector2i) -> int:
	_classify(tile.x, tile.y)
	return _last_gate


## 玩家能否站上这一格：地形本身可通行，或者这里是路。
## 箱庭外不可通行；跨区由 GameWorld 在出口触发瞬间切换。
func is_walkable(tile: Vector2i) -> bool:
	var packed: int = _query_terrain_route(tile)
	return Terrain.is_walkable(packed & 255) or ((packed >> 8) & 255) != Route.Kind.NONE


func _query_terrain_route(tile: Vector2i) -> int:
	var frame: int = Engine.get_physics_frames()
	if frame != _query_frame:
		_query_frame = frame
		_query_tiles.clear()
	if _query_tiles.has(tile):
		return _query_tiles[tile]
	_classify(tile.x, tile.y)
	var packed: int = _last_terrain | (_last_route << 8)
	if _query_tiles.size() >= 8192:
		_query_tiles.clear()
	_query_tiles[tile] = packed
	return packed


## 单个格子的完整判定：一次算完所在地图、地形、群系、路网与路口。
func _classify(tile_x: int, tile_y: int) -> void:
	var tile := Vector2i(tile_x, tile_y)
	var spec: MapSpec = _spec_at(tile)
	_last_gate = -1
	_last_map = spec
	_last_route = Route.Kind.NONE
	# 箱庭之间不生成实体道路，区域外不可通行，主视图也不会绘制此处。
	if spec == null:
		_last_terrain = Terrain.Kind.MOUNTAIN
		_last_biome = Biome.Kind.MOUNTAIN
		return
	_last_biome = spec.biome_id
	var local: Vector2i = tile - spec.origin
	# 木墙和家具先于道路判定，保证小屋只有门洞能进出。
	if spec.cottage != null:
		var cottage_terrain: int = spec.cottage.terrain_at(local)
		if cottage_terrain >= 0:
			_last_terrain = cottage_terrain
			return
	var world_point := Vector2(float(tile_x) + 0.5, float(tile_y) + 0.5)
	var point: Vector2 = world_point - Vector2(spec.origin)
	var road_distance: float = _road_distance(point, spec)
	var edge_noise: float = _edges.get_noise_2d(float(tile_x), float(tile_y))
	var room_depth: float = spec.clearance(point) + edge_noise * 1.5
	var passage_depth: float = spec.pass_half_width - road_distance
	var open_depth: float = maxf(room_depth, passage_depth)
	var grove: float = _groves.get_noise_2d(float(tile_x), float(tile_y))
	var variation: float = (_variation.get_noise_2d(float(tile_x), float(tile_y)) + 1.0) * 0.5

	# 箱庭外仍是连贯的陆地；山壁和密林构成边界，出口开在自然山口。
	if open_depth <= 0.0:
		_last_terrain = spec.boundary_kind
		return

	_last_terrain = RegionBiomes.terrain_for(spec.biome_id, variation, grove)

	var nearest_road: float = road_distance
	if nearest_road < MapSpec.ROAD_HALF_WIDTH:
		_last_route = Route.Kind.DIRT
		if spec.shape == 4 and spec.cottage == null:
			_last_route = Route.Kind.STONE
	# 道路旁留出空地，区域内也能离开道路探索，而非只能沿一条细线走。
	if nearest_road < 7.0 and not Terrain.is_walkable(_last_terrain):
		_last_terrain = _ground_cover(_last_biome)
	if open_depth < WALL_FOOT_WIDTH and not Terrain.is_water(_last_terrain):
		_last_terrain = _ground_cover(_last_biome)

	# 水域是局部河流 / 池塘，控制在箱庭内部；道路遇水生成桥。
	if spec != null and room_depth > 5.0 and point.distance_to(spec.center) > 10.0:
		var water: float = spec.water_depth(point)
		if water > 0.0:
			_last_terrain = Terrain.Kind.WATER
			if _last_route != Route.Kind.NONE:
				_last_route = Route.Kind.BRIDGE
		elif water > -WATER_BANK_WIDTH and nearest_road >= 7.0:
			_last_terrain = Terrain.Kind.SAND if spec.biome_id == Biome.Kind.DESERT else _ground_cover(spec.biome_id)
	_check_gate(local.x, local.y, spec)


func _ground_cover(biome: int) -> int:
	return RegionBiomes.ground_for(biome)


func _open_land_terrain(biome: int, variation: float, _temperature_value: float, grove: float) -> int:
	# 保留旧查询签名，地形规则与新单群系路径一致。
	return RegionBiomes.terrain_for(biome, variation, grove)


## 兼容的边缘路口标记；完整双向切换由 gate_links 提供每个入口的目标。
func _check_gate(local_x: int, local_y: int, spec: MapSpec) -> void:
	if local_x == 0 and spec.west_gate_y >= 0:
		if absi(local_y - spec.west_gate_y) <= MapSpec.GATE_HALF_HEIGHT:
			_last_gate = 0
			return

	if local_x == spec.extent.x - 1:
		for index: int in spec.east_gates.size():
			if absi(local_y - spec.east_gates[index]) <= MapSpec.GATE_HALF_HEIGHT:
				_last_gate = index + 1
				return


# ------------------------------------------------------------ 道路

## 这个点到这张地图里最近一条路的距离（考虑沿路的正弦摆动）。
func _road_distance(point: Vector2, spec: MapSpec) -> float:
	var data: PackedFloat32Array = _map_roads(spec.node_id)
	var best: float = 1.0e9
	var pad: float = spec.pass_half_width + MapSpec.ROAD_WOBBLE + WALL_FOOT_WIDTH
	var segment_count: int = data.size() / 5

	for segment: int in segment_count:
		var base: int = segment * 5
		var ax: float = data[base]
		var ay: float = data[base + 1]
		var bx: float = data[base + 2]
		var by: float = data[base + 3]

		if point.x < minf(ax, bx) - pad or point.x > maxf(ax, bx) + pad:
			continue
		if point.y < minf(ay, by) - pad or point.y > maxf(ay, by) + pad:
			continue

		best = minf(best, MapSpec.segment_distance(
			point, Vector2(ax, ay), Vector2(bx, by), data[base + 4]
		))

	return best


# ------------------------------------------------------------ 群系

## 以 0.5 为中心做对比度拉伸，gain > 1 会把值推向两端。
static func _sharpen(value: float, gain: float) -> float:
	return clampf((value - 0.5) * gain + 0.5, 0.0, 1.0)


## 地面群系由山脊、温度和湿度决定；箱庭围墙与局部河湖另行处理。
static func _pick_biome(altitude: float, temperature: float, humidity: float) -> int:
	if altitude > ALPINE_LEVEL:
		return Biome.Kind.ALPINE
	if altitude > MOUNTAIN_LEVEL:
		return Biome.Kind.MOUNTAIN

	if temperature < 0.18:
		return Biome.Kind.SNOWY_PLAINS
	if temperature < 0.34:
		return Biome.Kind.TUNDRA if humidity < 0.45 else Biome.Kind.TAIGA
	if temperature < 0.54:
		if humidity < 0.35:
			return Biome.Kind.GRASSLAND
		return Biome.Kind.FOREST if humidity < 0.76 else Biome.Kind.SWAMP
	if temperature < 0.70:
		if humidity < 0.30:
			return Biome.Kind.SAVANNA
		if humidity < 0.55:
			return Biome.Kind.GRASSLAND
		return Biome.Kind.FOREST if humidity < 0.86 else Biome.Kind.SWAMP
	if humidity < 0.42:
		return Biome.Kind.DESERT
	return Biome.Kind.SAVANNA if humidity < 0.62 else Biome.Kind.TROPICAL_RAINFOREST


static func _pick_terrain(biome: int, variation: float, temperature: float) -> int:
	if biome == Biome.Kind.OCEAN:
		if temperature < 0.22 and variation >= Biome.SPLIT_A:
			return Terrain.Kind.ICE
		return Terrain.Kind.WATER

	if variation >= Biome.SPLIT_B:
		return Biome.TERTIARY[biome]
	if variation >= Biome.SPLIT_A:
		return Biome.SECONDARY[biome]
	return Biome.PRIMARY[biome]
