class_name GroundMaterials
extends RefCounted

## 仅规划点位；实例化、E 键交互与各地图拾取状态由 GameWorld 管理。
const GRID_SIZE: int = 16
const MIN_SPACING: int = 6
const MIN_COUNT: int = 20
const MAX_COUNT: int = 70
const SAFE_RADIUS: int = 3
const STREAM_SALT: int = 0x47524F55
##可以被投掷出去的材料（石块一类）：沙晶/冰晶/铁矿/岩盐/雷石
const THROWABLE_IDS: Array[int] = [14, 28, 30, 31, 36]

##每个群系在野外能捡到的材料（2~3 种，与材料表一致）；海域没有可站的陆地，退回海岸材料
const BIOME_ITEMS: Dictionary = {
	Biome.Kind.BEACH: [11, 12],
	Biome.Kind.DESERT: [13, 14],
	Biome.Kind.SAVANNA: [15, 16],
	Biome.Kind.GRASSLAND: [10, 17, 18],
	Biome.Kind.FOREST: [19, 20],
	Biome.Kind.TROPICAL_RAINFOREST: [21, 22, 34],
	Biome.Kind.SWAMP: [23, 35, 37],
	Biome.Kind.TAIGA: [24, 25],
	Biome.Kind.TUNDRA: [26, 27],
	Biome.Kind.SNOWY_PLAINS: [28, 29],
	Biome.Kind.MOUNTAIN: [30, 31, 36],
	Biome.Kind.ALPINE: [32, 33],
}


##这个群系的可捡材料列表；海域没有陆地，退回海岸材料
static func items_for(biome: int) -> Array:
	if BIOME_ITEMS.has(biome):
		return BIOME_ITEMS[biome]
	return BIOME_ITEMS[Biome.Kind.BEACH]


##是不是可以投掷的材料
static func is_throwable(item_id: int) -> bool:
	return THROWABLE_IDS.has(item_id)


##稀有度权重：普通 6、罕见 2、稀有 1，越稀有的材料在地面越少见。
const RARITY_WEIGHT: Array[int] = [6, 2, 1]


##按群系随机挑一种，按稀有度加权。
static func _pick_item(source: RandomNumberGenerator, biome: int) -> int:
	var pool: Array = items_for(biome)
	var total: float = 0.0
	for item_id: int in pool:
		total += float(RARITY_WEIGHT[_rarity_of(item_id)])
	if total <= 0.0:
		return int(pool[0])
	var roll: float = source.randf() * total
	var cumulative: float = 0.0
	for item_id: int in pool:
		cumulative += float(RARITY_WEIGHT[_rarity_of(item_id)])
		if roll < cumulative:
			return int(item_id)
	return int(pool[pool.size() - 1])


## 材料稀有度（与材料表一致，也和各个 .tres 里的 rarity 字段对应）。
## 这里用常量表而不是查 ItemListGlobal：后者是自动加载单例，
## 纯脚本测试里取不到会让整个生成器编译失败。
const RARITY: Dictionary = {
	14: 1, 20: 1, 22: 1, 25: 1, 28: 1, 30: 1, 36: 1,   # 罕见
	32: 2, 37: 2,                                        # 稀有
}


##材料的稀有度（0 普通 / 1 罕见 / 2 稀有）。
static func _rarity_of(item_id: int) -> int:
	return clampi(int(RARITY.get(item_id, 0)), 0, RARITY_WEIGHT.size() - 1)


static func plan(generator: WorldGenerator, spec: MapSpec) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if generator == null or spec == null:
		return result
	var salt: int = MapRng.mix(spec.node_id, MapRng.mix(generator.variant, STREAM_SALT))
	var source: RandomNumberGenerator = MapRng.new(generator.world_seed).rng(MapRng.Stream.LOOT, salt)
	var occupied: Dictionary = {}
	var exclusions: Array[Vector2i] = [WorldGenerator.world_to_tile(generator.entry_position(spec.node_id))]
	for link: Dictionary in generator.gate_links(spec.node_id):
		exclusions.append(link["point"])
		# 入口抵达位置也留出空间，避免玩家瞬切后踩在材料上。
		exclusions.append(WorldGenerator.world_to_tile(generator.entry_position(spec.node_id, link["side"], link["y"])))
	if spec.cottage != null:
		exclusions.append(spec.origin + spec.cottage.door_tile)
		_add_starter(generator, spec, result, occupied, exclusions)
	var target: int = clampi(roundi(float(spec.extent.x * spec.extent.y) / 650.0) + source.randi_range(-3, 3), MIN_COUNT, MAX_COUNT)
	var cells: Array[Vector2i] = []
	var first: Vector2i = _grid_cell(spec.origin)
	var last: Vector2i = _grid_cell(spec.origin + spec.extent - Vector2i.ONE)
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			cells.append(Vector2i(x, y))
	# 显式 Fisher-Yates，避免 Array.shuffle 使用全局随机流。
	for index: int in range(cells.size() - 1, 0, -1):
		var other: int = source.randi_range(0, index)
		var saved: Vector2i = cells[index]
		cells[index] = cells[other]
		cells[other] = saved
	for cell: Vector2i in cells:
		if result.size() >= target:
			break
		if occupied.has(cell):
			continue
		for attempt: int in 24:
			var tile: Vector2i = cell * GRID_SIZE + Vector2i(source.randi_range(1, GRID_SIZE - 2), source.randi_range(1, GRID_SIZE - 2))
			if not _can_place(generator, spec, tile, result, exclusions):
				continue
			var item_id: int = _pick_item(source, spec.biome_id)
			_append(result, occupied, tile, item_id, 1)
			break
	# 很小或密林占比高的地图，穷举尚未占用网格内的格子兜底，仍不突破密度限制。
	if result.size() < MIN_COUNT:
		for cell: Vector2i in cells:
			if result.size() >= MIN_COUNT:
				break
			if occupied.has(cell):
				continue
			var placed: bool = false
			for y: int in GRID_SIZE:
				for x: int in GRID_SIZE:
					var tile: Vector2i = cell * GRID_SIZE + Vector2i(x, y)
					if _can_place(generator, spec, tile, result, exclusions):
						var item_id: int = _pick_item(source, spec.biome_id)
						_append(result, occupied, tile, item_id, 1)
						placed = true
						break
				if placed:
					break
	# 每张图都能捡到该群系的两种材料：缺哪种就把一条不属于必得清单的记录换掉
	var pool: Array = items_for(spec.biome_id)

	for required_id: int in pool:
		var found: bool = false

		for entry: Dictionary in result:
			found = found or entry["item_id"] == required_id
		if found or result.is_empty():
			continue
		for replace_index: int in result.size():
			if not pool.has(result[replace_index]["item_id"]):
				result[replace_index]["item_id"] = required_id
				break
	return result


static func _add_starter(generator: WorldGenerator, spec: MapSpec, result: Array[Dictionary], occupied: Dictionary, exclusions: Array[Vector2i]) -> void:
	var porch: Vector2i = spec.origin + spec.cottage.porch_tile
	# 初图平台世界 y=0，南北两组点分属不同16格网格，且均在平台右侧。
	var starter_items: Array = items_for(spec.biome_id)

	for index: int in starter_items.size():
		var item_id: int = int(starter_items[index])
		var direction: int = -1 if index == 0 else 1
		var candidates: Array[Vector2i] = [Vector2i(4, direction * 3), Vector2i(6, direction * 4), Vector2i(5, direction * 5)]
		for y: int in range(1, 8):
			for x: int in range(3, 9):
				if x * x + y * y >= 16 and x * x + y * y <= 64:
					candidates.append(Vector2i(x, y * direction))
		for offset: Vector2i in candidates:
			var tile: Vector2i = porch + offset
			if occupied.has(_grid_cell(tile)) or not _can_place(generator, spec, tile, result, exclusions):
				continue
			if not generator.is_walkable(tile + Vector2i.RIGHT):
				continue
			_append(result, occupied, tile, item_id, 1)
			break


static func _can_place(generator: WorldGenerator, spec: MapSpec, tile: Vector2i, result: Array[Dictionary], exclusions: Array[Vector2i]) -> bool:
	var local: Vector2i = tile - spec.origin
	if not spec.contains_local(local.x, local.y) or not generator.is_walkable(tile):
		return false
	if Terrain.is_water(generator.sample_terrain(tile)):
		return false
	if spec.cottage != null and spec.cottage.bounds.has_point(local):
		return false
	for reserved: Rect2i in generator.population_for(spec.node_id).get("reserved", []):
		if reserved.has_point(tile):
			return false
	for point: Vector2i in exclusions:
		var delta: Vector2i = tile - point
		if maxi(absi(delta.x), absi(delta.y)) <= SAFE_RADIUS:
			return false
	for entry: Dictionary in result:
		var other: Vector2i = entry["tile"]
		if Vector2(tile - other).length_squared() < MIN_SPACING * MIN_SPACING:
			return false
	return true


static func _append(result: Array[Dictionary], occupied: Dictionary, tile: Vector2i, item_id: int, amount: int) -> void:
	result.append({"tile": tile, "item_id": item_id, "amount": amount})
	occupied[_grid_cell(tile)] = true


static func _grid_cell(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / GRID_SIZE), floori(float(tile.y) / GRID_SIZE))
