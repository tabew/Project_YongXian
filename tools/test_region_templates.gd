extends SceneTree

## 区域模板与拼接验收：按类型选模板、区域不重叠、门朝向对齐、降级可用。
## godot --headless --path . --script res://tools/test_region_templates.gd

const SEEDS: Array[int] = [1, 7, 18473, 97231, 24681357, 2147483646]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	for seed_value: int in SEEDS:
		_check_world(seed_value)
	_check_fallback()
	print("REGION_TEMPLATE_TEST: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_world(seed_value: int) -> void:
	var generator: WorldGenerator = WorldGenerator.new(seed_value)
	var specs: Array[MapSpec] = generator.map_specs()
	var by_id: Dictionary = {}
	for spec: MapSpec in specs:
		by_id[spec.node_id] = spec
		# 模板按房间类型选择：每种类型对应一个默认模板。
		var expected: StringName = _template_for(generator.run.type_of(spec.node_id))
		_check(spec.template_id == expected,
			"模板与房间类型不匹配 seed=%d node=%d 得到=%s 期望=%s" % [seed_value, spec.node_id, spec.template_id, expected])
		# 尺寸必须落在所选模板的范围内。
		var template: RegionTemplate = _find_template(expected)
		_check(spec.extent.x >= template.min_extent and spec.extent.x <= template.max_extent
			and spec.extent.y >= template.min_extent and spec.extent.y <= template.max_extent,
			"区域尺寸超出模板范围 seed=%d node=%d extent=%s" % [seed_value, spec.node_id, spec.extent])

	# 区域不重叠。
	for i: int in specs.size():
		for j: int in range(i + 1, specs.size()):
			var a := Rect2i(specs[i].origin, specs[i].extent)
			var b := Rect2i(specs[j].origin, specs[j].extent)
			_check(not a.intersects(b), "区域重叠 seed=%d %d/%d" % [seed_value, specs[i].node_id, specs[j].node_id])

	# 门朝向对齐：出口在东边界，入口在西边界，且方向一致。
	for connection: Dictionary in generator.connections():
		var source: MapSpec = by_id[connection["from"]]
		var target: MapSpec = by_id[connection["to"]]
		var a := Vector2i((connection["a"] as Vector2).floor())
		var b := Vector2i((connection["b"] as Vector2).floor())
		_check(a.x == source.origin.x + source.extent.x - 1, "出口不在东边界 seed=%d" % seed_value)
		_check(b.x == target.origin.x, "入口不在西边界 seed=%d" % seed_value)
		_check(source.east_gates[connection["exit"]] == a.y - source.origin.y, "出口 y 不一致 seed=%d" % seed_value)
		_check(target.west_gates[connection["entrance"]] == b.y - target.origin.y, "入口 y 不一致 seed=%d" % seed_value)


func _check_fallback() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var template: RegionTemplate = RegionTemplates.pick(999, 0, -1, rng)
	_check(template.id == &"fallback", "无匹配模板时没有降级到 fallback")
	var limited := RegionTemplate.create(&"west_only", 112, 224, 1.0)
	limited.door_sides = RegionTemplate.DOOR_WEST
	var pool: Array = [limited]
	_check(RegionTemplates.pick(RoomType.Kind.COMBAT, RegionTemplate.DOOR_EAST, -1, rng, pool).id == &"fallback",
		"门朝向不匹配时没有降级")
	_check(RegionTemplates.pick(RoomType.Kind.COMBAT, RegionTemplate.DOOR_WEST, -1, rng, pool).id == &"west_only",
		"门朝向匹配时没有选中模板")


func _template_for(kind: int) -> StringName:
	match kind:
		RoomType.Kind.START:
			return &"start"
		RoomType.Kind.COMBAT:
			return &"combat"
		RoomType.Kind.REWARD:
			return &"reward"
		RoomType.Kind.SHOP:
			return &"shop"
		RoomType.Kind.REST:
			return &"rest"
		RoomType.Kind.EVENT:
			return &"event"
		RoomType.Kind.BOSS:
			return &"boss"
	return &"fallback"


func _find_template(id_value: StringName) -> RegionTemplate:
	for entry: RegionTemplate in RegionTemplates.defaults():
		if entry.id == id_value:
			return entry
	return RegionTemplates.fallback()