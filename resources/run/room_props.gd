class_name RoomProps
extends RefCounted

## 房间道具规划：把 RoomData 里的场景元素与可破坏物落成世界里的具体点位。
## 纯逻辑、不建节点，实例化与交互由 GameWorld 负责，便于单测与工作线程调用。
##
## 两类道具承担不同的材料角色：
## - 场景元素（火盆 / 毒池 / 铁栏…）：长按 E 吸附，吸附后进入冷却再长回来，是可再生来源。
## - 可破坏物（木箱 / 矿脉…）：打碎后掉对应材料，是消耗型来源。

enum Kind { ELEMENT = 0, BREAKABLE = 1 }

## 点位之间的最小间距（格）：道具不能挤在一起，也不能堵住道路。
const MIN_SPACING: float = 5.0
## 距离入口 / 出口的安全半径（格）：门口不放道具。
const SAFE_RADIUS: int = 4
## 单房间的道具上限；按房间面积缩放后取更小值。
const MAX_ELEMENTS: int = 6
const MAX_BREAKABLES: int = 4
## 每 900 格面积放一个元素 / 一个可破坏物。
const AREA_PER_ELEMENT: float = 900.0
const AREA_PER_BREAKABLE: float = 1500.0
## 候选点位网格边长（格）：先生成稀疏网格再打乱，保证分布均匀。
const CANDIDATE_STRIDE: int = 3
const STREAM_SALT: int = 0x50524F50
## 没有可放点位时的返回值。
const INVALID_TILE: Vector2i = Vector2i(-2147483648, -2147483648)


## 规划一个房间的道具点位；同 (世界种子, 变体, 房间编号) 结果固定。
## 返回 [{"kind", "id", "tile", "material_id", "amount", "traits"}]。
static func plan(generator: WorldGenerator, spec: MapSpec, room: RoomData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if generator == null or spec == null or room == null:
		return result
	var source: RandomNumberGenerator = MapRng.new(generator.world_seed).rng(
		MapRng.Stream.LOOT, MapRng.mix(spec.node_id, MapRng.mix(generator.variant, STREAM_SALT))
	)
	var candidates: Array[Vector2i] = _candidate_tiles(spec, source)
	var blocked: Array[Vector2i] = _blocked_tiles(generator, spec)
	var order: Array[Dictionary] = _placement_order(room, spec)
	for entry: Dictionary in order:
		var tile: Vector2i = _pick_tile(generator, spec, candidates, result, blocked)
		if tile == INVALID_TILE:
			break
		var placed: Dictionary = _describe(entry, tile, source)
		if placed.is_empty():
			continue
		result.append(placed)
	return result


## 一个房间该放哪些道具：按房间面积定配额，再按配置表顺序取前若干个。
## 元素与可破坏物交替排列，避免同类全部堆在房间同一侧。
static func _placement_order(room: RoomData, spec: MapSpec) -> Array[Dictionary]:
	var area: float = float(spec.extent.x * spec.extent.y)
	var element_quota: int = clampi(roundi(area / AREA_PER_ELEMENT), 1, MAX_ELEMENTS)
	var breakable_quota: int = clampi(roundi(area / AREA_PER_BREAKABLE), 0, MAX_BREAKABLES)
	var elements: Array[StringName] = _take(room.scene_elements, element_quota)
	var breakables: Array[StringName] = _take(room.breakables, breakable_quota)
	var order: Array[Dictionary] = []
	var count: int = maxi(elements.size(), breakables.size())
	for index: int in count:
		if index < elements.size():
			order.append({"kind": Kind.ELEMENT, "id": elements[index]})
		if index < breakables.size():
			order.append({"kind": Kind.BREAKABLE, "id": breakables[index]})
	return order


## 取前 limit 个；limit <= 0 时返回空。
static func _take(ids: Array[StringName], limit: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for index: int in mini(limit, ids.size()):
		result.append(ids[index])
	return result


## 补全一条点位的全部运行时数据；配置缺失时返回空字典表示跳过。
static func _describe(entry: Dictionary, tile: Vector2i, source: RandomNumberGenerator) -> Dictionary:
	var id: StringName = entry["id"]
	var kind: int = int(entry["kind"])
	var material_id: int = -1
	var traits: Array = []
	if kind == Kind.ELEMENT:
		if not SceneElementCatalog.has_element(id):
			return {}
		material_id = SceneElementCatalog.material_of(id)
		traits = SceneElementCatalog.traits_of(id)
	else:
		if not BreakableCatalog.has_breakable(id):
			return {}
		material_id = BreakableCatalog.material_of(id)
	if material_id < 0:
		return {}
	return {
		"kind": kind,
		"id": id,
		"tile": tile,
		"material_id": material_id,
		"amount": 1 if kind == Kind.ELEMENT else AlchemyMaterialSources.amount_for(material_id, source),
		"traits": traits,
	}


## 候选点位：按固定步长铺满箱庭再显式打乱，保证同种子分布一致。
static func _candidate_tiles(spec: MapSpec, source: RandomNumberGenerator) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var margin: int = SAFE_RADIUS + 1
	var x: int = margin
	while x < spec.extent.x - margin:
		var y: int = margin
		while y < spec.extent.y - margin:
			result.append(spec.origin + Vector2i(x, y))
			y += CANDIDATE_STRIDE
		x += CANDIDATE_STRIDE
	# 显式 Fisher-Yates，避免 Array.shuffle 使用全局随机流。
	for index: int in range(result.size() - 1, 0, -1):
		var other: int = source.randi_range(0, index)
		var saved: Vector2i = result[index]
		result[index] = result[other]
		result[other] = saved
	return result


## 必须避开的点位：入口、每个出口与对应的落点，门口不放道具。
static func _blocked_tiles(generator: WorldGenerator, spec: MapSpec) -> Array[Vector2i]:
	var blocked: Array[Vector2i] = [WorldGenerator.world_to_tile(generator.entry_position(spec.node_id))]
	for link: Dictionary in generator.gate_links(spec.node_id):
		blocked.append(link["point"])
		blocked.append(WorldGenerator.world_to_tile(
			generator.entry_position(spec.node_id, link["side"], link["y"])
		))
	return blocked


## 从候选里挑第一个合法点位；候选按打乱顺序遍历，天然形成随机分布。
static func _pick_tile(
	generator: WorldGenerator,
	spec: MapSpec,
	candidates: Array[Vector2i],
	placed: Array[Dictionary],
	blocked: Array[Vector2i]
) -> Vector2i:
	for tile: Vector2i in candidates:
		if _can_place(generator, spec, tile, placed, blocked):
			return tile
	return INVALID_TILE


## 可放置判定：在箱庭内、可走、非水、离门口够远、离已放道具够远。
static func _can_place(
	generator: WorldGenerator,
	spec: MapSpec,
	tile: Vector2i,
	placed: Array[Dictionary],
	blocked: Array[Vector2i]
) -> bool:
	var local: Vector2i = tile - spec.origin
	if not spec.contains_local(local.x, local.y) or not generator.is_walkable(tile):
		return false
	if Terrain.is_water(generator.sample_terrain(tile)):
		return false
	if spec.cottage != null and spec.cottage.bounds.has_point(local):
		return false
	for point: Vector2i in blocked:
		var delta: Vector2i = tile - point
		if maxi(absi(delta.x), absi(delta.y)) <= SAFE_RADIUS:
			return false
	for entry: Dictionary in placed:
		if Vector2(tile - (entry["tile"] as Vector2i)).length_squared() < MIN_SPACING * MIN_SPACING:
			return false
	return true
