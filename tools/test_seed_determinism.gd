extends SceneTree

## 种子系统验收：同一 seed 两次生成完全一致，不同 seed 明显不同。
## godot --headless --path . --script res://tools/test_seed_determinism.gd
## 输出 GOLDEN 行用于重构前后的逐位回归比对。

const SEEDS: Array[int] = [1, 18473, 97231, 2147483646]
## 覆盖首层主干、次层岔路与末层主干，包含区块数据。
const SAMPLE_NODES: Array[int] = [0, 3, 14]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var fingerprints: Dictionary = {}
	for seed_value: int in SEEDS:
		var a: WorldGenerator = WorldGenerator.new(seed_value)
		var b: WorldGenerator = WorldGenerator.new(seed_value)
		_check(describe(a) == describe(b), "同种子两次生成不一致 seed=%d" % seed_value)
		var printed: String = fingerprint(a)
		fingerprints[seed_value] = printed
		print("GOLDEN seed=%d %s" % [seed_value, printed])
	for index: int in SEEDS.size():
		for other: int in range(index + 1, SEEDS.size()):
			_check(
				fingerprints[SEEDS[index]] != fingerprints[SEEDS[other]],
				"不同种子生成结果相同 seed=%d/%d" % [SEEDS[index], SEEDS[other]]
			)
	print("SEED_DETERMINISM: failures=%d seeds=%d" % [_failures, SEEDS.size()])
	quit(0 if _failures == 0 else 1)


func describe(generator: WorldGenerator) -> String:
	var parts: PackedStringArray = []
	for spec: MapSpec in generator.map_specs():
		parts.append("%d|%s|%s|%s|%d|%s|%s" % [
			spec.node_id, spec.origin, spec.extent, spec.shape,
			spec.boundary_kind, spec.west_gates, spec.east_gates,
		])
		parts.append("%s|%s|%s|%s" % [spec.chambers, spec.chamber_corners, spec.ponds, spec.river_width])
	parts.append(str(generator.connections()))
	for node_id: int in SAMPLE_NODES:
		parts.append(chunks(generator, node_id))
	return "\n".join(parts)


func chunks(generator: WorldGenerator, node_id: int) -> String:
	var spec: MapSpec = generator.map_spec(node_id)
	var parts: PackedStringArray = []
	var first: Vector2i = WorldGenerator.tile_to_chunk(spec.origin)
	var last: Vector2i = WorldGenerator.tile_to_chunk(spec.origin + spec.extent - Vector2i.ONE)
	for cy: int in range(first.y, last.y + 1):
		for cx: int in range(first.x, last.x + 1):
			var data: ChunkData = generator.generate_chunk(Vector2i(cx, cy))
			parts.append("%d,%d:%d" % [cx, cy, hash([data.terrain, data.biome, data.route])])
	return "%d[%s]" % [node_id, "|".join(parts)]


func fingerprint(generator: WorldGenerator) -> String:
	var parts: PackedStringArray = []
	for spec: MapSpec in generator.map_specs():
		parts.append("%d|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
			spec.node_id, spec.origin, spec.extent, spec.axes, spec.shape,
			spec.boundary_kind, spec.west_gates, spec.east_gates, spec.chambers, spec.ponds,
		])
	parts.append(str(generator.connections()))
	for node_id: int in SAMPLE_NODES:
		parts.append(chunks(generator, node_id))
	return "digest=%d" % hash("\n".join(parts))

