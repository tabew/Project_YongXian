class_name GroundMaterials
extends RefCounted

## 仅规划点位；实例化、E 键交互与各地图拾取状态由 GameWorld 管理。
const STONE_ID: int = 2
const STICK_ID: int = 3
const GRID_SIZE: int = 16
const MIN_SPACING: int = 6
const MIN_COUNT: int = 20
const MAX_COUNT: int = 70
const SAFE_RADIUS: int = 3
const STREAM_SALT: int = 0x47524F55
## 石头 / 木棍在抽样表里的总权重；炼金材料按各自权重并入同一张表。
const GROUND_WEIGHT: float = 12.0


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
	var pool: Array[Dictionary] = _material_pool(spec)
	for cell: Vector2i in cells:
		if result.size() >= target:
			break
		if occupied.has(cell):
			continue
		for attempt: int in 24:
			var tile: Vector2i = cell * GRID_SIZE + Vector2i(source.randi_range(1, GRID_SIZE - 2), source.randi_range(1, GRID_SIZE - 2))
			if not _can_place(generator, spec, tile, result, exclusions):
				continue
			_append_pick(result, occupied, tile, source, pool)
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
						_append_pick(result, occupied, tile, source, pool)
						placed = true
						break
				if placed:
					break
	# 每图均可获得石头与木棍（保证「投石」与基础采集），并至少刷出一种本群系的正式炼金材料。
	_ensure_required(result, pool, source)
	return result


## 抽样表：石头 / 木棍保持原有群系比例，再并入本群系（或 Boss 房）的正式炼金材料。
static func _material_pool(spec: MapSpec) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var stone_share: float = _stone_ratio(spec.biome_id)
	pool.append({"id": STONE_ID, "weight": stone_share * GROUND_WEIGHT})
	pool.append({"id": STICK_ID, "weight": (1.0 - stone_share) * GROUND_WEIGHT})
	for entry: Dictionary in AlchemyMaterialSources.pool_for(spec):
		pool.append({"id": int(entry["id"]), "weight": maxf(float(entry.get("weight", 1.0)), 0.0)})
	return pool


## 按权重抽一种材料；数量由品质决定（普通 1~3、稀有 1~2、更高 1）。
static func _pick(source: RandomNumberGenerator, pool: Array[Dictionary]) -> Dictionary:
	var total: float = 0.0
	for entry: Dictionary in pool:
		total += maxf(float(entry.get("weight", 0.0)), 0.0)
	if pool.is_empty() or total <= 0.0:
		return {"id": STONE_ID, "amount": 1}
	var roll: float = source.randf() * total
	for entry: Dictionary in pool:
		roll -= maxf(float(entry.get("weight", 0.0)), 0.0)
		if roll <= 0.0:
			var material_id: int = int(entry["id"])
			return {"id": material_id, "amount": AlchemyMaterialSources.amount_for(material_id, source)}
	var last: int = int(pool[pool.size() - 1]["id"])
	return {"id": last, "amount": AlchemyMaterialSources.amount_for(last, source)}


static func _append_pick(result: Array[Dictionary], occupied: Dictionary, tile: Vector2i, source: RandomNumberGenerator, pool: Array[Dictionary]) -> void:
	var pick: Dictionary = _pick(source, pool)
	_append(result, occupied, tile, int(pick["id"]), int(pick["amount"]))


static func _contains_id(result: Array[Dictionary], item_id: int) -> bool:
	for entry: Dictionary in result:
		if int(entry["item_id"]) == item_id:
			return true
	return false


## 兜底：保证石头 / 木棍各至少一条，并至少刷出一条本群系的正式炼金材料。
static func _ensure_required(result: Array[Dictionary], pool: Array[Dictionary], source: RandomNumberGenerator) -> void:
	if result.is_empty():
		return
	var wanted: Array[int] = []
	if not _contains_id(result, STONE_ID):
		wanted.append(STONE_ID)
	if not _contains_id(result, STICK_ID):
		wanted.append(STICK_ID)
	var biome_ids: Array[int] = []
	for entry: Dictionary in pool:
		var material_id: int = int(entry["id"])
		if material_id != STONE_ID and material_id != STICK_ID and not biome_ids.has(material_id):
			biome_ids.append(material_id)
	if not biome_ids.is_empty() and not _contains_any(result, biome_ids):
		wanted.append(biome_ids[0])
	# 每次占用不同的槽位，避免后一条兜底把前一条刚补上的必备材料又换掉。
	var used: Array[int] = []
	for item_id: int in wanted:
		var index: int = _free_index(result, used)
		if index < 0:
			return
		used.append(index)
		result[index]["item_id"] = item_id
		result[index]["amount"] = AlchemyMaterialSources.amount_for(item_id, source)


static func _contains_any(result: Array[Dictionary], item_ids: Array[int]) -> bool:
	for entry: Dictionary in result:
		if item_ids.has(int(entry["item_id"])):
			return true
	return false


## 找一个可覆盖的槽位：优先末尾的非石头 / 木棍，且本次未被占用。
static func _free_index(result: Array[Dictionary], used: Array[int]) -> int:
	for index: int in range(result.size() - 1, -1, -1):
		if used.has(index):
			continue
		var current: int = int(result[index]["item_id"])
		if current == STONE_ID or current == STICK_ID:
			continue
		return index
	for index: int in range(result.size() - 1, -1, -1):
		if not used.has(index):
			return index
	return -1


static func _add_starter(generator: WorldGenerator, spec: MapSpec, result: Array[Dictionary], occupied: Dictionary, exclusions: Array[Vector2i]) -> void:
	var porch: Vector2i = spec.origin + spec.cottage.porch_tile
	# 初图平台世界 y=0，南北两组点分属不同16格网格，且均在平台右侧。
	for item_id: int in [STONE_ID, STICK_ID]:
		var direction: int = -1 if item_id == STONE_ID else 1
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


static func _stone_ratio(biome: int) -> float:
	match biome:
		Biome.Kind.DESERT, Biome.Kind.MOUNTAIN, Biome.Kind.TUNDRA, Biome.Kind.SNOWY_PLAINS, Biome.Kind.ALPINE:
			return 0.72
		Biome.Kind.FOREST, Biome.Kind.TAIGA, Biome.Kind.TROPICAL_RAINFOREST, Biome.Kind.SWAMP:
			return 0.35
	return 0.50
