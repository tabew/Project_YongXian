class_name MapEventPlanner
extends RefCounted

## 第一版地图事件选点。
##
## 事件房保证生成一个草丛药水事件，普通房间低概率出现；战斗房有概率生成
## 一个地刺。所有点位只做纯数据规划，运行时由 GameWorld 实例化。

const GRASS_POTION: StringName = &"grass_potion"
const SPIKE_TRAP: StringName = &"spike_trap"

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

	if room_kind == RoomType.Kind.EVENT:
		_add_event(result, occupied, GRASS_POTION, generator, spec, rng, safe_points, reachable)
		if rng.randf() < 0.55:
			_add_event(result, occupied, SPIKE_TRAP, generator, spec, rng, safe_points, reachable)
	elif room_kind == RoomType.Kind.COMBAT:
		if rng.randf() < 0.55:
			_add_event(result, occupied, SPIKE_TRAP, generator, spec, rng, safe_points, reachable)
	elif rng.randf() < 0.22:
		_add_event(result, occupied, GRASS_POTION, generator, spec, rng, safe_points, reachable)

	return result


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