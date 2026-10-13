extends SceneTree

## 软约束评分验收：明细项齐全、权重生效、best-of-N 不劣于首份且可复现。
## godot --headless --path . --script res://tools/test_map_scorer.gd

const SEEDS: Array[int] = [1, 7, 18473, 97231, 24681357]

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
	var config := MapConfig.new()
	var weights: Dictionary = {
		"path_ideal": config.weight_path_ideal,
		"branches": config.weight_branches,
		"shop_distance": config.weight_shop_distance,
		"type_variety": config.weight_type_variety,
		"rest_spacing": config.weight_rest_spacing,
		"difficulty_ramp": config.weight_difficulty_ramp,
	}
	var scores: Dictionary = {}
	for seed_value: int in SEEDS:
		var generator: WorldGenerator = WorldGenerator.new(seed_value)
		var parts: Dictionary = MapScorer.breakdown(generator, config)
		_check(parts.size() == weights.size(), "评分明细项数量不对 seed=%d" % seed_value)
		var total: float = 0.0
		for key: String in weights.keys():
			_check(parts.has(key), "缺少评分项 %s" % key)
			var value: float = float(parts[key])
			_check(value >= -0.0001 and value <= float(weights[key]) + 0.0001,
				"评分项 %s 越界 seed=%d value=%f" % [key, seed_value, value])
			total += value
		_check(absf(total - MapScorer.score(generator, config)) < 0.0001, "总分与明细不一致 seed=%d" % seed_value)
		scores[seed_value] = MapScorer.score(generator, config)

		# best-of-N 至少不劣于第一份候选，且可复现。
		var best: WorldGenerator = MapScorer.build_best(seed_value, config)
		_check(best != null and MapValidator.validate(best).is_empty(), "best-of-N 返回了不合格地图 seed=%d" % seed_value)
		_check(MapScorer.score(best, config) >= MapScorer.score(generator, config) - 0.0001,
			"best-of-N 比首份候选更差 seed=%d" % seed_value)
		var again: WorldGenerator = MapScorer.build_best(seed_value, config)
		_check(again.world_seed == best.world_seed, "best-of-N 不可复现 seed=%d" % seed_value)

	var distinct: Dictionary = {}
	for seed_value: int in scores.keys():
		distinct[snappedf(scores[seed_value], 0.0001)] = true
	_check(distinct.size() > 1, "不同种子评分完全相同")
	print("MAP_SCORER: checks=%d failures=%d scores=%s" % [_checks, _failures, scores])
	quit(0 if _failures == 0 else 1)