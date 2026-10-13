extends SceneTree

## 硬约束校验与重生成验收：批量地图 100%% 通过硬校验，重试/兜底不崩。
## godot --headless --path . --script res://tools/test_map_validation.gd

const BATCH: int = 100

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
	var template_counts: Dictionary = {}
	var type_counts: Dictionary = {}
	var path_lengths: Dictionary = {}
	var passed: int = 0
	for index: int in BATCH:
		var seed_value: int = 1000 + index
		var generator: WorldGenerator = WorldGenerator.new(seed_value)
		var problems: PackedStringArray = MapValidator.validate(generator)
		if problems.is_empty():
			passed += 1
		else:
			push_error("地图未通过硬校验 seed=%d %s" % [seed_value, ", ".join(problems)])
		for spec: MapSpec in generator.map_specs():
			template_counts[spec.template_id] = int(template_counts.get(spec.template_id, 0)) + 1
			var kind: int = generator.run.type_of(spec.node_id)
			type_counts[RoomType.name_of(kind)] = int(type_counts.get(RoomType.name_of(kind), 0)) + 1
		path_lengths[generator.run.main_path.size()] = int(path_lengths.get(generator.run.main_path.size(), 0)) + 1
	_check(passed == BATCH, "批量硬校验通过率 %d/%d" % [passed, BATCH])

	# 生成入口 build_valid：合格种子原样返回，且可复现。
	for seed_value: int in [1, 18473, 97231]:
		var built: WorldGenerator = MapValidator.build_valid(seed_value)
		_check(built != null and built.world_seed == seed_value, "合格种子被改写 seed=%d" % seed_value)
		var again: WorldGenerator = MapValidator.build_valid(seed_value)
		_check(again.world_seed == built.world_seed, "build_valid 不可复现 seed=%d" % seed_value)

	# 重试与兜底：不可能满足的约束必须终止并给出兜底地图，而不是崩溃。
	var strict := MapConfig.new()
	strict.min_path_len = 99
	strict.max_retries = 3
	var fallback: WorldGenerator = MapValidator.build_valid(2024, strict)
	_check(fallback != null, "达到重试上限时没有返回兜底地图")
	_check(not MapValidator.validate(fallback).is_empty(), "不可能满足的约束却报告通过")

	print("MAP_VALIDATION: checks=%d failures=%d batch_passed=%d/%d" % [_checks, _failures, passed, BATCH])
	print("MAP_VALIDATION_TEMPLATES: %s" % template_counts)
	print("MAP_VALIDATION_TYPES: %s" % type_counts)
	print("MAP_VALIDATION_PATHS: %s" % path_lengths)
	quit(0 if _failures == 0 else 1)