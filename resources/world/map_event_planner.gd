class_name MapEventPlanner
extends RefCounted

## 第一版地图事件选点。
##
## 每个非起点/Boss房间至少布置一个事件，事件房和战斗房更密集：
## 事件房多个可交互事件 + 陷阱，战斗房多个陷阱，其余房间 1-2 个事件。
## 事件和陷阱都从池中按种子抽取，所有点位只做纯数据规划。

const GRASS_POTION: StringName = &"grass_potion"
const ALCHEMY_SPIRIT: StringName = &"alchemy_spirit"
const SUSPICIOUS_POTION: StringName = &"suspicious_potion"
const POISON_MUSHROOM: StringName = &"poison_mushroom"
const TRAPPED_CHEST: StringName = &"trapped_chest"
const SPIKE_TRAP: StringName = &"spike_trap"
const BEAR_TRAP: StringName = &"bear_trap"
const TRIPWIRE: StringName = &"tripwire"

const EVENT_POOL: Array[StringName] = [
	GRASS_POTION,
	ALCHEMY_SPIRIT,
	SUSPICIOUS_POTION,
	POISON_MUSHROOM,
	TRAPPED_CHEST,
]
const TRAP_POOL: Array[StringName] = [
	SPIKE_TRAP,
	BEAR_TRAP,
	TRIPWIRE,
]

const EVENT_SALT: int = 0x45564E54
const MARGIN: int = 6
const SAFE_DISTANCE: int = 7
const NO_TILE: Vector2i = Vector2i(2147483647, 2147483647)


static func plan(
	generator: WorldGenerator,
	spec: MapSpec,
	reserved: Array[Rect2i]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if generator == null or spec == null or generator.run == null:
		return result
	var room_kind: int = generator.run.type_of(spec.node_id)
	if room_kind == RoomType.Kind.START or room_kind == RoomType.Kind.BOSS:
		return result

	var rng: RandomNumberGenerator = generator.rng.rng(
		MapRng.Stream.EVENT,
		MapRng.mix(EVENT_SALT, spec.node_id + generator.variant * 97)
	)
	var occupied: Array[Rect2i] = []
	occupied.assign(reserved)
	var safe_points: Array[Vector2i] = _safe_points(generator, spec)
	var reachable: Dictionary = _reachable_tiles(generator, spec)

	var event_count: int = 1
	var trap_count: int = 0
	match room_kind:
		RoomType.Kind.EVENT:
			event_count = 3
			trap_count = 1
		RoomType.Kind.COMBAT:
			event_count = 1 if rng.randf() < 0.5 else 0
			trap_count = 3
		RoomType.Kind.REWARD:
			event_count = 2
		RoomType.Kind.SHOP, RoomType.Kind.REST:
			event_count = 1
		_:
			event_count = 1

	# 再给普通房间一点随机增量，让同一张图不会永远只有固定数量。
	if rng.randf() < 0.45:
		event_count += 1
	if room_kind in [RoomType.Kind.EVENT, RoomType.Kind.COMBAT] and rng.randf() < 0.6:
		trap_count += 1

	# 小地图也要留出空间，最多 5 个事件点；优先保留可交互事件。
	var cap: int = clampi(int(spec.extent.x * spec.extent.y / 5000), 3, 5)
	event_count = mini(event_count, cap)
	trap_count = mini(trap_count, maxi(cap - event_count, 0))

	for _index: int in event_count:
		_add_event(result, occupied, _pick(EVENT_POOL, rng), generator, spec, rng, safe_points, reachable)
	for _index: int in trap_count:
		_add_event(result, occupied, _pick(TRAP_POOL, rng), generator, spec, rng, safe_points, reachable)

	return result


static func _pick(pool: Array[StringName], rng: RandomNumberGenerator) -> StringName:
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _add_event(
	result: Array[Dictionary],
	occupied: Array[Rect2i],
	event_id: StringName,
	generator: WorldGenerator,
	spec: MapSpec,
	rng: RandomNumberGenerator,
	safe_points: Array[Vector2i],
	reachable: Dictionary
) -> void:
	var tile: Vector2i = _find_tile(generator, spec, rng, occupied, safe_points, reachable)
	if tile == NO_TILE:
		return
	var footprint := Rect2i(tile - Vector2i.ONE, Vector2i(3, 3))
	occupied.append(footprint.grow(2))
	result.append({
		"event_id": event_id,
		"tile": tile,
		"seed": rng.randi_range(1, 2147483646),
	})


static func _find_tile(
	generator: WorldGenerator,
	spec: MapSpec,
	rng: RandomNumberGenerator,
	occupied: Array[Rect2i],
	safe_points: Array[Vector2i],
	reachable: Dictionary
) -> Vector2i:
	for _attempt: int in 180:
		var local := Vector2i(
			rng.randi_range(MARGIN, spec.extent.x - MARGIN - 1),
			rng.randi_range(MARGIN, spec.extent.y - MARGIN - 1)
		)
		var tile: Vector2i = spec.origin + local
		if not reachable.has(tile):
			continue
		if not generator.is_walkable(tile):
			continue
		if Terrain.is_water(generator.sample_terrain(tile)):
			continue
		if generator.sample_route(tile) != Route.Kind.NONE:
			continue
		var footprint := Rect2i(tile - Vector2i.ONE, Vector2i(3, 3))
		if not Rect2i(spec.origin, spec.extent).encloses(footprint):
			continue
		var blocked: bool = false
		for rect: Rect2i in occupied:
			if footprint.intersects(rect):
				blocked = true
				break
		if blocked:
			continue
		for point: Vector2i in safe_points:
			if footprint.grow(SAFE_DISTANCE).has_point(point):
				blocked = true
				break
		if blocked:
			continue
		return tile
	return NO_TILE


static func _safe_points(generator: WorldGenerator, spec: MapSpec) -> Array[Vector2i]:
	var result: Array[Vector2i] = [
		WorldGenerator.world_to_tile(generator.entry_position(spec.node_id))
	]
	for link: Dictionary in generator.gate_links(spec.node_id):
		result.append(WorldGenerator.world_to_tile(generator.entry_position(
			spec.node_id,
			int(link["side"]),
			int(link["y"])
		)))
	return result


## 事件必须落在从入口可达的陆地区域，避免被地形围死。
static func _reachable_tiles(generator: WorldGenerator, spec: MapSpec) -> Dictionary:
	var start: Vector2i = WorldGenerator.world_to_tile(generator.entry_position(spec.node_id))
	var visited: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var index: int = 0
	while index < queue.size():
		var tile: Vector2i = queue[index]
		index += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = tile + direction
			var local: Vector2i = next - spec.origin
			if visited.has(next):
				continue
			if not spec.contains_local(local.x, local.y):
				continue
			if not generator.is_walkable(next):
				continue
			visited[next] = true
			queue.append(next)
	return visited