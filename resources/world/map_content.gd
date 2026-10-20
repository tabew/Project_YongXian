class_name MapContent
extends RefCounted

## 内容填充层：房间类型决定内容池，各系统用自己的子随机源，互不干扰。
##
## 结构（房间图）不变，这里只产出"每个区域该放什么、放多少"的数据，
## 具体实例化仍由现有系统负责（刷怪走 MonsterSpawner，物品走掉落系统）。

## 内容类型。
const ENEMY: StringName = &"enemy"
const LOOT: StringName = &"loot"
const SHOP: StringName = &"shop"
const HEAL: StringName = &"heal"
const EVENT: StringName = &"event"
const BOSS: StringName = &"boss"
const DECOR: StringName = &"decor"

var generator_seed: int = 0
## node_id -> Array[Dictionary]（每项 {kind, budget, seed}）
var entries: Dictionary = {}


static func build(generator: WorldGenerator) -> MapContent:
	var content := MapContent.new()
	content.generator_seed = generator.world_seed
	for spec: MapSpec in generator.map_specs():
		content.entries[spec.node_id] = content._plan(generator, spec)
	return content


func content_of(node_id: int) -> Array:
	return entries.get(node_id, [])


## 某个区域里某类内容的总预算。
func budget_of(node_id: int, kind: StringName) -> int:
	var total: int = 0
	for entry: Dictionary in content_of(node_id):
		if entry["kind"] == kind:
			total += int(entry["budget"])
	return total


func _plan(generator: WorldGenerator, spec: MapSpec) -> Array:
	var kind: int = generator.run.type_of(spec.node_id)
	var span: int = maxi(generator.run.floors.size() - 1, 1)
	var difficulty: float = clampf(float(RunGraph.floor_of(spec.node_id)) / float(span), 0.0, 1.0)
	var result: Array = []
	if RunGraph.floor_of(spec.node_id) > 0 and kind not in [RoomType.Kind.EVENT, RoomType.Kind.BOSS]:
		result.append(_entry(ENEMY, 3 + roundi(difficulty * 4.0), MapRng.Stream.ENEMY, spec.node_id))
	match kind:
		RoomType.Kind.START:
			result.append(_entry(DECOR, 6, MapRng.Stream.DECOR, spec.node_id))
		RoomType.Kind.COMBAT:
			result.append(_entry(DECOR, 4, MapRng.Stream.DECOR, spec.node_id))
		RoomType.Kind.REWARD:
			result.append(_entry(LOOT, 2 + roundi(difficulty * 2.0), MapRng.Stream.LOOT, spec.node_id))
		RoomType.Kind.SHOP:
			result.append(_entry(SHOP, 1, MapRng.Stream.LOOT, spec.node_id))
		RoomType.Kind.REST:
			result.append(_entry(HEAL, 1, MapRng.Stream.LOOT, spec.node_id))
		RoomType.Kind.EVENT:
			result.append(_entry(EVENT, 1, MapRng.Stream.DECOR, spec.node_id))
			result.append(_entry(LOOT, 1, MapRng.Stream.LOOT, spec.node_id))
		RoomType.Kind.BOSS:
			result.append(_entry(BOSS, 1, MapRng.Stream.ENEMY, spec.node_id))
	return result


## 预算的轻微随机波动来自对应子随机源；同种子同区域结果一致。
func _entry(kind: StringName, base_budget: int, stream_kind: int, node_id: int) -> Dictionary:
	var rng: RandomNumberGenerator = MapRng.new(generator_seed).rng(stream_kind, node_id)
	var jitter: int = rng.randi_range(0, 1) if base_budget > 1 else 0
	return {"kind": kind, "budget": base_budget + jitter, "seed": rng.seed}


## 在区域里挑 count 个可通行格子，供内容落点使用。
static func pick_tiles(
	generator: WorldGenerator,
	node_id: int,
	count: int,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var spec: MapSpec = generator.map_spec(node_id)
	if spec == null or spec.extent.x < 6 or spec.extent.y < 6:
		return result
	for _attempt: int in count * 24:
		if result.size() >= count:
			break
		var local := Vector2i(
			rng.randi_range(2, spec.extent.x - 3),
			rng.randi_range(2, spec.extent.y - 3)
		)
		var tile: Vector2i = spec.origin + local
		if generator.is_walkable(tile) and not result.has(tile):
			result.append(tile)
	return result


func describe() -> String:
	var lines: PackedStringArray = []
	for node_id: int in entries.keys():
		var parts: PackedStringArray = []
		for entry: Dictionary in content_of(node_id):
			parts.append("%s×%d" % [entry["kind"], entry["budget"]])
		lines.append("  区域 %d：%s" % [node_id, "，".join(parts)])
	return "\n".join(lines)