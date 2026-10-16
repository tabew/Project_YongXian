class_name GrassContext
extends RefCounted

## 一张箱庭的草丛排除区：结构占地、宝箱与掉落、小屋、出入口安全区、材料点。
## 只存瓦片矩形与点位，不含节点，可在任何线程构造。

## 出入口 / 门前留出多大范围不长草。
const SAFE_RADIUS: int = 3

var blocked: Array[Rect2i] = []
var safe_points: Array[Vector2i] = []
## 已被地面材料占用的格子（瓦片坐标 -> true）。
var occupied: Dictionary = {}


static func create(generator: WorldGenerator, spec: MapSpec, occupied_tiles: Dictionary) -> GrassContext:
	var context := GrassContext.new()
	context.occupied = occupied_tiles
	var population: Dictionary = generator.population_for(spec.node_id)
	for entry: Dictionary in population.get("structures", []):
		context.blocked.append(entry["rect"] as Rect2i)
	for entry: Dictionary in population.get("chests", []):
		context.blocked.append(Rect2i(entry["tile"] as Vector2i - Vector2i.ONE, Vector2i(3, 3)))
	for entry: Dictionary in population.get("drops", []):
		context.blocked.append(Rect2i(entry["tile"] as Vector2i - Vector2i.ONE, Vector2i(3, 3)))
	if spec.cottage != null:
		# 小屋内是木地板，门廊也不长草。
		context.blocked.append(
			Rect2i(spec.origin + spec.cottage.bounds.position, spec.cottage.bounds.size).grow(2)
		)
		context.safe_points.append(spec.origin + spec.cottage.door_tile)
		context.safe_points.append(spec.origin + spec.cottage.porch_tile)
	context.safe_points.append(WorldGenerator.world_to_tile(generator.entry_position(spec.node_id)))
	for link: Dictionary in generator.gate_links(spec.node_id):
		context.safe_points.append(link["point"] as Vector2i)
		context.safe_points.append(
			WorldGenerator.world_to_tile(
				generator.entry_position(spec.node_id, int(link["side"]), int(link["y"]))
			)
		)
	return context


## 这一格能不能长草（地形与路由由调用方按 ChunkData 判定）。
func allows(tile: Vector2i) -> bool:
	if occupied.has(tile):
		return false
	for rect: Rect2i in blocked:
		if rect.has_point(tile):
			return false
	for point: Vector2i in safe_points:
		var delta: Vector2i = tile - point
		if maxi(absi(delta.x), absi(delta.y)) <= SAFE_RADIUS:
			return false
	return true
