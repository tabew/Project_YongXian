class_name WorldPopulation
extends RefCounted

## 地表兴趣点的纯数据规划。独立随机流保证不影响地形、刷怪和战斗。
const KINDS: Array[StringName] = [&"camp", &"ruins", &"alchemy", &"supplies", &"garden"]
## 炼金台：野外唯一的炼金交互点，每张箱庭保证至少一台。
const ALCHEMY_KIND: StringName = &"alchemy"
## 结构之间留出的最小间隔（格）。之前是 3，结构容易挤在一起。
const STRUCTURE_GAP: int = 6
const SALT: int = 0x504F5055


##某个群系的战利品池：地面材料 + 炸弹
static func _loot_pool(spec: MapSpec) -> Array:
	var pool: Array = GroundMaterials.items_for(spec.biome_id).duplicate()

	if not pool.has(5):
		pool.append(5)
	return pool


static func plan(generator: WorldGenerator, spec: MapSpec) -> Dictionary:
	var structures: Array[Dictionary] = []
	var chests: Array[Dictionary] = []
	var drops: Array[Dictionary] = []
	var blocked: Dictionary = {}
	var reserved: Array[Rect2i] = []
	var decor_rng: RandomNumberGenerator = generator.rng.rng(MapRng.Stream.DECOR, MapRng.mix(SALT, spec.node_id + generator.variant * 97))
	var loot_rng: RandomNumberGenerator = generator.rng.rng(MapRng.Stream.LOOT, MapRng.mix(SALT, spec.node_id + generator.variant * 97))
	var safe_points: Array[Vector2i] = [WorldGenerator.world_to_tile(generator.entry_position(spec.node_id))]
	for link: Dictionary in generator.gate_links(spec.node_id):
		safe_points.append(link["point"])
		safe_points.append(WorldGenerator.world_to_tile(generator.entry_position(spec.node_id, link["side"], link["y"])))
	if spec.cottage != null:
		reserved.append(Rect2i(spec.origin + spec.cottage.bounds.position, spec.cottage.bounds.size).grow(5))
	var count: int = clampi(spec.extent.x * spec.extent.y / 2400, 6, 16)
	var rotation: int = decor_rng.randi_range(0, KINDS.size() - 1)
	for attempt: int in 900:
		if structures.size() >= count:
			break
		# 第一台炼金台优先贴着主路放（沿路走一段就能碰到），其余结构轮转种类。
		var want_alchemy: bool = structures.is_empty()
		var kind: StringName = (
			ALCHEMY_KIND if want_alchemy
			else KINDS[(structures.size() + rotation) % KINDS.size()]
		)
		var tile: Vector2i = Vector2i.ZERO
		if want_alchemy and attempt < 40:
			tile = _roadside_candidate(generator, spec, decor_rng, 8)
		if tile == Vector2i.ZERO:
			tile = _candidate(spec, decor_rng, 8)
		var footprint := Rect2i(tile - Vector2i(4, 3), Vector2i(9, 7))
		if not _site_is_clear(generator, spec, footprint.grow(1), reserved, safe_points):
			continue
		var solid: Array[Vector2i] = _solid_offsets(kind)
		for offset: Vector2i in solid:
			blocked[tile + offset] = true
		structures.append({"kind": kind, "tile": tile, "rect": footprint, "variant": decor_rng.randi_range(0, 2)})
		reserved.append(footprint.grow(STRUCTURE_GAP))
	var chest_count: int = loot_rng.randi_range(2, 4)
	if generator.run.type_of(spec.node_id) == RoomType.Kind.REWARD:
		chest_count += 2
	for attempt: int in 600:
		if chests.size() >= chest_count:
			break
		var tile: Vector2i = _candidate(spec, loot_rng, 5)
		var footprint := Rect2i(tile - Vector2i.ONE, Vector2i(3, 3))
		if not _site_is_clear(generator, spec, footprint, reserved, safe_points):
			continue
		var rare: bool = loot_rng.randf() < 0.25
		var loot: Array[Dictionary] = []
		var pool: Array = _loot_pool(spec)
		# 四个方向全在已验证的空地内，落地物资互不重叠。
		var offsets: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]
		for index: int in (4 if rare else 3):
			loot.append({"tile": tile + offsets[index], "item_id": pool[loot_rng.randi_range(0, pool.size() - 1)], "amount": loot_rng.randi_range(2, 5) if rare else loot_rng.randi_range(1, 3)})
		chests.append({"tile": tile, "rare": rare, "loot": loot})
		reserved.append(footprint.grow(2))
	var drop_count: int = clampi(spec.extent.x * spec.extent.y / 1800, 10, 24)
	var drop_pool: Array = GroundMaterials.items_for(spec.biome_id)

	for attempt: int in 600:
		if drops.size() >= drop_count:
			break
		var tile: Vector2i = _candidate(spec, loot_rng, 5)
		var footprint := Rect2i(tile - Vector2i.ONE, Vector2i(3, 3))
		if not _site_is_clear(generator, spec, footprint, reserved, safe_points):
			continue
		# 用当前群系的地面材料
		drops.append({"tile": tile, "item_id": drop_pool[loot_rng.randi_range(0, drop_pool.size() - 1)], "amount": loot_rng.randi_range(1, 3)})
		reserved.append(footprint.grow(1))
	return {"structures": structures, "chests": chests, "drops": drops, "blocked": blocked, "reserved": reserved}


static func _candidate(spec: MapSpec, source: RandomNumberGenerator, margin: int) -> Vector2i:
	return spec.origin + Vector2i(source.randi_range(margin, spec.extent.x - margin - 1), source.randi_range(margin, spec.extent.y - margin - 1))


static func _site_is_clear(generator: WorldGenerator, spec: MapSpec, rect: Rect2i, reserved: Array[Rect2i], safe_points: Array[Vector2i]) -> bool:
	if not Rect2i(spec.origin, spec.extent).encloses(rect):
		return false
	for existing: Rect2i in reserved:
		if rect.intersects(existing):
			return false
	for point: Vector2i in safe_points:
		if rect.grow(8).has_point(point):
			return false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var tile := Vector2i(x, y)
			if not generator.is_walkable(tile) or Terrain.is_water(generator.sample_terrain(tile)) or generator.sample_route(tile) != Route.Kind.NONE:
				return false
	return true


static func _solid_offsets(kind: StringName) -> Array[Vector2i]:
	match kind:
		&"camp":
			return [Vector2i(-3, -2), Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(-3, -1), Vector2i(-2, -1), Vector2i(-1, -1)]
		&"ruins":
			return [Vector2i(-3, -2), Vector2i(3, -2), Vector2i(-3, 2), Vector2i(3, 2)]
		&"alchemy":
			# 台面占中间三格，四周留出站位给玩家按 E。
			return [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
		&"supplies":
			return [Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(2, 1)]
	return []


## 贴着主路找一个站点位置：沿路取点后向侧面挪几格，让结构落在路边。
## 找不到返回 Vector2i.ZERO，调用方退回普通选址。
static func _roadside_candidate(
	generator: WorldGenerator, spec: MapSpec, source: RandomNumberGenerator, margin: int
) -> Vector2i:
	var bounds := Rect2i(spec.origin, spec.extent).grow(-margin)
	for probe: int in 40:
		var road_tile: Vector2i = _candidate(spec, source, margin)
		if generator.sample_route(road_tile) == Route.Kind.NONE:
			continue
		for offset: Vector2i in [
			Vector2i(5, 0), Vector2i(-5, 0), Vector2i(0, 5), Vector2i(0, -5),
			Vector2i(6, 1), Vector2i(-6, -1), Vector2i(-1, 6), Vector2i(1, -6)
		]:
			var site: Vector2i = road_tile + offset
			if bounds.has_point(site):
				return site
	return Vector2i.ZERO
