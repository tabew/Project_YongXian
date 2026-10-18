class_name WorldGenerator
extends RefCounted

## 传统 RPG 陆地箱庭：随机庭院、山谷和林间空地，以山壁 / 密林围合。
## 主干与岔路按列贴合、通过带黑幕的出入口切换；水域只作为少量河流与池塘。
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

## 世界级河流：跨箱庭连续的水系，穿过屏障处形成水峡（仍是阻挡）。
## 斜向贯穿世界（同一世界所有河流平行），河面宽 6~9 格。
const RIVER_HALF_WIDTH: float = 3.3
const RIVER_BANK_WIDTH: float = 3.0
## 河流主轴与世界的夹角范围（度）。
const RIVER_ANGLE_MIN: float = 26.0
const RIVER_ANGLE_MAX: float = 62.0
## 两条河之间的最小垂直间距（格）。
const RIVER_SPACING: float = 34.0
## 折线采样步长（格）与空间索引网格（格）。
const RIVER_STEP: float = 5.0
const RIVER_CELL: int = 32
## 区内每隔多少格留一段可涉水浅滩，保证河不会把箱庭切成两半。
const RIVER_FORD_SPAN: float = 28.0
const RIVER_FORD_HALF: float = 2.0
## 河流横向摆幅上限：只许蜿蜒，不许绕回自身围出封闭水域。
const RIVER_MEANDER: float = 7.0

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
var _flow := FastNoiseLite.new()

# 每线程一个实例，所以这些缓存天然是线程局部的
var _map_cache: Dictionary = {}
var _road_cache: Dictionary = {}
var _specs: Array[MapSpec] = []
var _connections: Array[Dictionary] = []
var _map_bins: Dictionary = {}
var _gate_cache: Dictionary = {}
var _populations: Dictionary = {}
var _population_blockers: Dictionary = {}
## 世界级河流：折线段 x1,y1,x2,y2,half 与空间索引。
var _river_segments: PackedFloat32Array = PackedFloat32Array()
var _river_cells: Dictionary = {}
var _river_length: PackedFloat32Array = PackedFloat32Array()
## 各列贴合，世界地图上不再留空白断层。
const REGION_GAP: int = 0

# _classify 的输出缓冲，避免为每个格子分配对象
var _last_terrain: int = Terrain.Kind.DEEP_WATER
var _last_biome: int = Biome.Kind.DEEP_OCEAN
var _last_route: int = Route.Kind.NONE
var _last_map: MapSpec = null
var _last_gate: int = -1
## 河流查询的两个输出：水深（>0 在水里）与沿河里程。
var _last_river_depth: float = -INF
var _last_river_along: float = -1.0
## 同一物理帧的只读采样共用结果；各线程持有自己的生成器实例。
var _query_frame: int = -1
var _query_tiles: Dictionary = {}


func _init(seed_value: int = 0, map_config: MapConfig = null, variant_index: int = 0, population_data: Dictionary = {}) -> void:
	world_seed = seed_value if seed_value != 0 else random_seed()
	config = map_config if map_config != null else MapConfig.new()
	variant = variant_index
	rng = MapRng.new(world_seed)
	run = RoomGraph.plan(world_seed, config, variant)
	_build_layout()
	_configure_noise()
	_build_rivers()
	# 先在基础地形上规划所有兴趣点，再统一启用碰撞覆盖，避免规划顺序影响布局。
	if population_data.is_empty():
		for spec: MapSpec in _specs:
			_populations[spec.node_id] = WorldPopulation.plan(self, spec)
	else:
		# 区块线程复用主生成器已完成的只读规划，不重复抽样整局兴趣点。
		_populations = population_data
	for population: Dictionary in _populations.values():
		_population_blockers.merge(population["blocked"])
	_query_tiles.clear()


func _configure_noise() -> void:
	_temperature.noise_type = FastNoiseLite.TYPE_PERLIN
	_temperature.seed = rng.noise_seed(0)
	_temperature.frequency = 0.0035
	_temperature.fractal_octaves = 2

	_humidity.noise_type = FastNoiseLite.TYPE_PERLIN
	_humidity.seed = rng.noise_seed(1)
	_humidity.frequency = 0.0042
	_humidity.fractal_octaves = 2

	_variation.noise_type = FastNoiseLite.TYPE_PERLIN
	_variation.seed = rng.noise_seed(2)
	# 细节尺度拉大：一个噪声簇占几十格，避免彩色小碎片铺满箱庭。
	_variation.frequency = 0.007
	_variation.fractal_octaves = 1

	_groves.noise_type = FastNoiseLite.TYPE_PERLIN
	_groves.seed = rng.noise_seed(3)
	_groves.frequency = 0.006
	_groves.fractal_octaves = 1
	_ridges.noise_type = FastNoiseLite.TYPE_PERLIN
	_ridges.seed = rng.noise_seed(4)
	_ridges.frequency = 0.007
	_ridges.fractal_octaves = 1
	_edges.noise_type = FastNoiseLite.TYPE_PERLIN
	_edges.seed = rng.noise_seed(5)
	_edges.frequency = 0.010
	_edges.fractal_octaves = 1
	# 河流蜿蜒用独立随机源，避免改动它与既有地形/生物群系抽样互相影响。
	_flow.noise_type = FastNoiseLite.TYPE_PERLIN
	_flow.seed = rng.noise_seed(6)
	_flow.frequency = 0.012
	_flow.fractal_octaves = 2


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


func population_for(map_node_id: int) -> Dictionary:
	return _populations.get(map_node_id, {})


func population_snapshot() -> Dictionary:
	return _populations


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
	var column_y: int = 0
	for floor_index: int in run.floors.size():
		var ids: PackedInt32Array = run.floors[floor_index]
		var order: PackedInt32Array = ids.duplicate()
		# 双房列主线在上；第三列分支-主线-新增分支从上到下。
		if ids.size() == 3:
			order = PackedInt32Array([ids[1], ids[0], ids[2]])
		var height: int = 0
		for id: int in order:
			var spec: MapSpec = map_spec(id)
			spec.fit_column_width(floor_widths[floor_index])
			height += spec.extent.y
		if floor_index > 0:
			column_y = clampi(column_y + layout_rng.randi_range(-4, 4), -12, 12)
		var top: int = column_y - height / 2
		for id: int in order:
			var spec: MapSpec = map_spec(id)
			spec.origin = Vector2i(cursor_x, top)
			top += spec.extent.y
		cursor_x += floor_widths[floor_index] + REGION_GAP

	# 连接仍沿用原有双向出口；共享边优先把两端落在相同世界高度。
	for spec: MapSpec in _specs:
		for exit_index: int in run.exit_count(spec.node_id):
			var target: MapSpec = map_spec(run.target_of(spec.node_id, exit_index))
			var margin: int = MapSpec.GATE_HALF_HEIGHT + 4
			var overlap_top: int = maxi(spec.origin.y, target.origin.y) + margin
			var overlap_bottom: int = mini(spec.origin.y + spec.extent.y, target.origin.y + target.extent.y) - margin - 1
			var gateway_y: int = (overlap_top + overlap_bottom) / 2 if overlap_top <= overlap_bottom else target.origin.y + int(target.center.y)
			var source_y: int = clampi(gateway_y - spec.origin.y, margin, spec.extent.y - margin - 1)
			var target_y: int = clampi(spec.origin.y + source_y - target.origin.y, margin, target.extent.y - margin - 1)
			# 汇流时错开相邻西门，避免同一组门触发错误的返回边。
			for existing_y: int in target.west_gates:
				if absi(target_y - existing_y) < margin * 2:
					target_y = clampi(existing_y + margin * 2, margin, target.extent.y - margin - 1)
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
	_reserve_snow_combat()
	for spec: MapSpec in _specs:
		spec.boundary_kind = RegionBiomes.boundary_for(spec.biome_id)
		spec.ensure_swamp_water()


## 主线上安排兔子战斗区域；不挤占雨林、沼泽或安全房间。
func _reserve_snow_combat() -> void:
	var chosen_biome: int = Biome.Kind.SNOWY_PLAINS
	if not config.combat_biomes.has(chosen_biome):
		chosen_biome = Biome.Kind.TUNDRA
	if not config.combat_biomes.has(chosen_biome):
		return
	var target: MapSpec = null
	var protected_main: MapSpec = null
	for spec: MapSpec in _specs:
		if run.type_of(spec.node_id) != RoomType.Kind.COMBAT or not run.is_main_path(spec.node_id):
			continue
		if RunGraph.floor_of(spec.node_id) >= run.floors.size() - 2:
			continue
		if spec.biome_id in [Biome.Kind.SNOWY_PLAINS, Biome.Kind.TUNDRA]:
			return
		if spec.biome_id in [Biome.Kind.TROPICAL_RAINFOREST, Biome.Kind.SWAMP]:
			if protected_main == null:
				protected_main = spec
		elif target == null:
			target = spec
	if target != null:
		target.biome_id = chosen_biome
		return
	var branch: MapSpec = null
	for spec: MapSpec in _specs:
		if run.type_of(spec.node_id) != RoomType.Kind.COMBAT or run.is_main_path(spec.node_id):
			continue
		if spec.biome_id in [Biome.Kind.SNOWY_PLAINS, Biome.Kind.TUNDRA]:
			branch = spec
			break
		if branch == null and spec.biome_id not in [Biome.Kind.TROPICAL_RAINFOREST, Biome.Kind.SWAMP]:
			branch = spec
	if branch == null:
		return
	if protected_main == null:
		branch.biome_id = chosen_biome
		return
	var preserved_biome: int = protected_main.biome_id
	protected_main.biome_id = branch.biome_id if branch.biome_id in [Biome.Kind.SNOWY_PLAINS, Biome.Kind.TUNDRA] else chosen_biome
	branch.biome_id = preserved_biome


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
		var delta: Vector2 = b - a
		var normal: Vector2 = Vector2(delta.y, -delta.x).normalized()
		var t: float = clampf((target_x - a.x) / dx, 0.0, 1.0)
		# 道路摆动会让落点横向偏移，迭代几次把 x 拉回“向里八格”附近。
		for _pass_index: int in 4:
			var sample: Vector2 = a.lerp(b, t) + normal * MapSpec.road_offset(t, roads[base + 4])
			t = clampf(t + (target_x - sample.x) / dx, 0.0, 1.0)
		var point: Vector2 = a.lerp(b, t) + normal * MapSpec.road_offset(t, roads[base + 4])
		return tile_to_world(spec.origin + Vector2i(point.floor()))
	return tile_to_world(spec.origin + Vector2i(spec.center))


# ------------------------------------------------------------ 世界级河流

## 规划跨箱庭的河流：同一世界里所有河流沿同一个斜向平行流淌（不交叉，
## 避免围出封闭水域），从世界一侧流入、贯穿若干区域后从另一侧流出。
## 避开门口、落点与起始小屋；穿屏障处是水峡（仍阻挡），区内每隔一段留浅滩保证连通。
func _build_rivers() -> void:
	_river_segments.clear()
	_river_cells.clear()
	_river_length.clear()
	if _specs.is_empty():
		return
	var bounds := Rect2(Vector2(_specs[0].origin), Vector2(_specs[0].extent))
	for spec: MapSpec in _specs:
		bounds = bounds.merge(Rect2(Vector2(spec.origin), Vector2(spec.extent)))
	var protected: Array[Vector2] = _protected_water_points()
	var flow_rng: RandomNumberGenerator = rng.rng(MapRng.Stream.DECOR, MapRng.mix(0x52495652, variant))
	var angle: float = deg_to_rad(flow_rng.randf_range(RIVER_ANGLE_MIN, RIVER_ANGLE_MAX))
	var direction := Vector2(cos(angle), sin(angle))
	if flow_rng.randf() < 0.5:
		direction = Vector2(-direction.x, direction.y)
	var perpendicular := Vector2(-direction.y, direction.x)
	var span: float = absf(bounds.size.x * perpendicular.x) + absf(bounds.size.y * perpendicular.y)
	var count: int = flow_rng.randi_range(1, 3)
	var used: Array[float] = []
	for river_index: int in count:
		for attempt: int in 14:
			var lateral: float = span * (float(river_index) / 3.0 - 0.2)
			lateral += flow_rng.randf_range(-span * 0.10, span * 0.10)
			if not _lateral_is_free(lateral, used, RIVER_SPACING):
				continue
			var path: PackedVector2Array = _trace_river(bounds, direction, perpendicular, lateral)
			if path.size() < 3:
				continue
			if not _river_clear_of(path, protected):
				continue
			_register_river(
				path,
				flow_rng.randf_range(RIVER_HALF_WIDTH * 0.85, RIVER_HALF_WIDTH * 1.35)
			)
			used.append(lateral)
			break


## 两条河之间至少隔开一段距离，否则会在并行处夹出细长水域。
func _lateral_is_free(lateral: float, used: Array[float], minimum: float) -> bool:
	for other: float in used:
		if absf(other - lateral) < minimum:
			return false
	return true


## 不能落水的关键点：所有出入口、落点与起始小屋附近。
func _protected_water_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for spec: MapSpec in _specs:
		if spec.cottage != null:
			points.append(Vector2(spec.origin) + spec.center)
		for connection: Dictionary in _connections:
			if connection["from"] == spec.node_id or connection["to"] == spec.node_id:
				points.append(connection["a"] as Vector2)
				points.append(connection["b"] as Vector2)
	return points


## 沿斜向主轴贯穿世界，用噪声做横向蜿蜒；摆幅被夹住，只弯不绕。
## lateral 是主轴相对世界中心的垂直偏移，同世界的河流共用方向，因此互不交叉。
func _trace_river(
	bounds: Rect2, direction: Vector2, perpendicular: Vector2, lateral: float
) -> PackedVector2Array:
	var path := PackedVector2Array()
	var origin: Vector2 = bounds.get_center() + perpendicular * lateral
	# 先把起点推到世界矩形内部（沿主轴向前推进），否则一上来就判出界，
	# 整条河会被 size<3 的检查丢掉。
	var point: Vector2 = origin - direction * (bounds.size.length() * 0.6)
	var guard: int = 0
	while not bounds.has_point(point) and guard < 400:
		point += direction * RIVER_STEP
		guard += 1
	var steps: int = int(bounds.size.length() * 1.4 / RIVER_STEP) + 8
	for step: int in steps:
		path.append(point)
		var sway: float = _flow.get_noise_2d(point.x, point.y)
		var bend: float = _flow.get_noise_2d(point.y * 0.7 + 137.0, point.x * 0.7 - 61.0)
		point += direction * RIVER_STEP + perpendicular * (sway * 3.4 + bend * 1.1)
		# 把横向偏移夹在主轴附近：河可以弯，但不会拐回来围出封闭水域。
		var offset: float = (point - origin).dot(perpendicular)
		var clamped: float = clampf(offset, -RIVER_MEANDER, RIVER_MEANDER)
		if not is_equal_approx(clamped, offset):
			point -= perpendicular * (offset - clamped)
		if not bounds.grow(RIVER_STEP).has_point(point):
			break
	path.append(point)
	return path


## 河流离关键点至少 12 格，避免淹掉门口和落点；起始小屋所在的箱庭整体不落河。
func _river_clear_of(path: PackedVector2Array, protected: Array[Vector2]) -> bool:
	for point: Vector2 in path:
		var tile := Vector2i(floori(point.x), floori(point.y))
		var spec: MapSpec = _spec_at(tile)
		if spec != null and spec.cottage != null:
			return false
		for other: Vector2 in protected:
			if point.distance_to(other) < 12.0:
				return false
	return true


## 把折线登记成带半宽的线段，并按 32 格一格的网格建索引，逐格查询只看得见邻近几段。
func _register_river(path: PackedVector2Array, half_width: float) -> void:
	var along: float = 0.0
	for index: int in range(1, path.size()):
		var a: Vector2 = path[index - 1]
		var b: Vector2 = path[index]
		var length: float = a.distance_to(b)
		if length < 0.001:
			continue
		var segment_index: int = _river_segments.size() / 5
		_river_segments.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, half_width]))
		_river_length.append(along)
		along += length
		var reach: float = half_width + RIVER_BANK_WIDTH + 1.0
		var first := Vector2i(floori((minf(a.x, b.x) - reach) / float(RIVER_CELL)), floori((minf(a.y, b.y) - reach) / float(RIVER_CELL)))
		var last := Vector2i(floori((maxf(a.x, b.x) + reach) / float(RIVER_CELL)), floori((maxf(a.y, b.y) + reach) / float(RIVER_CELL)))
		for cell_y: int in range(first.y, last.y + 1):
			for cell_x: int in range(first.x, last.x + 1):
				var cell := Vector2i(cell_x, cell_y)
				if not _river_cells.has(cell):
					_river_cells[cell] = PackedInt32Array()
				var bucket: PackedInt32Array = _river_cells[cell]
				bucket.append(segment_index)
				_river_cells[cell] = bucket


## 查询这一格的水深（>0 在水里）与沿河里程（-1 表示不在河里）。
func _river_sample(tile_x: int, tile_y: int) -> void:
	_last_river_depth = -INF
	_last_river_along = -1.0
	if _river_segments.is_empty():
		return
	var cell := Vector2i(floori(float(tile_x) / float(RIVER_CELL)), floori(float(tile_y) / float(RIVER_CELL)))
	if not _river_cells.has(cell):
		return
	var point := Vector2(float(tile_x) + 0.5, float(tile_y) + 0.5)
	for segment_index: int in _river_cells[cell]:
		var base: int = segment_index * 5
		var half: float = _river_segments[base + 4]
		var distance: float = MapSpec.segment_distance(
			point,
			Vector2(_river_segments[base], _river_segments[base + 1]),
			Vector2(_river_segments[base + 2], _river_segments[base + 3])
		)
		var depth: float = half - distance
		if depth > _last_river_depth:
			_last_river_depth = depth
			_last_river_along = _river_length[segment_index]


## 区内每 RIVER_FORD_SPAN 格留一小段浅滩，河不会把箱庭切成两半。
func _is_river_ford(along: float) -> bool:
	if along < 0.0:
		return false
	var phase: float = fmod(along, RIVER_FORD_SPAN)
	return phase <= RIVER_FORD_HALF or phase >= RIVER_FORD_SPAN - RIVER_FORD_HALF


## 一张地图的路段（带缓存）。
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
	if _population_blockers.has(tile):
		_last_terrain = Terrain.Kind.MOUNTAIN
		return
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

	# 池塘是箱庭内的局部水面；道路遇水生成桥。
	if spec != null and room_depth > 5.0 and point.distance_to(spec.center) > 10.0:
		var water: float = spec.water_depth(point)
		if water > 0.0:
			_last_terrain = Terrain.Kind.WATER
			if _last_route != Route.Kind.NONE:
				_last_route = Route.Kind.BRIDGE
		elif water > -WATER_BANK_WIDTH and nearest_road >= 7.0:
			_last_terrain = Terrain.Kind.SAND if spec.biome_id == Biome.Kind.DESERT else _ground_cover(spec.biome_id)
	# 世界级河流：跨箱庭连续，穿屏障处是水峡（仍是阻挡）；区内每隔一段留浅滩保证连通。
	_apply_river(tile_x, tile_y, spec, room_depth)
	_check_gate(local.x, local.y, spec)


## 把世界级河流盖到这一格上：水域、河岸与浅滩三种情况。
func _apply_river(tile_x: int, tile_y: int, spec: MapSpec, room_depth: float) -> void:
	_river_sample(tile_x, tile_y)
	if _last_river_depth <= -RIVER_BANK_WIDTH:
		return
	if _last_river_depth > 0.0:
		# 只有深入区内、且不在山脚过渡带里的河段才留浅滩；
		# 屏障里的水峡必须保持阻断，否则箱庭之间会被打通。
		# 浅滩允许贴近山脚过渡带，否则贴边的窄条会没有可涉水处而断路。
		# 但路面不能变成浅滩：有路的地方保持桥面，否则道路上会出现断口。
		if room_depth > 2.5 and _last_route == Route.Kind.NONE and _is_river_ford(_last_river_along):
			_last_terrain = Terrain.Kind.SAND
			return
		_last_terrain = Terrain.Kind.WATER
		if _last_route != Route.Kind.NONE:
			_last_route = Route.Kind.BRIDGE
		return
	# 岸带：只在没被道路占用、也不是池塘水面的地方铺沙或地表。
	if _last_route != Route.Kind.NONE or Terrain.is_water(_last_terrain):
		return
	if spec != null and spec.biome_id == Biome.Kind.DESERT:
		_last_terrain = Terrain.Kind.SAND
	elif spec != null:
		_last_terrain = _ground_cover(spec.biome_id)


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
