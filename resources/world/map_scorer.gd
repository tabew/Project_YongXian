class_name MapScorer
extends RefCounted

## 软约束评分：在多份通过硬校验的地图里挑最优的一份。
##
## 每个评分项归一化到 0..1 再乘权重；权重全部来自 MapConfig，可调。

## 各房间类型的难度权重，用于"越靠近 Boss 越难"。
const DIFFICULTY: Dictionary = {
	RoomType.Kind.START: 0.0,
	RoomType.Kind.COMBAT: 1.0,
	RoomType.Kind.EVENT: 0.6,
	RoomType.Kind.REWARD: 0.3,
	RoomType.Kind.SHOP: 0.2,
	RoomType.Kind.REST: 0.1,
	RoomType.Kind.BOSS: 1.0,
}


## 在同一主种子下试若干个布局变体，返回评分最高的一份。
## 世界身份（种子）保持不变，只是换一套布局血肉。
static func build_best(seed_value: int, config: MapConfig = null) -> WorldGenerator:
	var effective: MapConfig = config if config != null else MapConfig.new()
	var best: WorldGenerator = null
	var best_score: float = -INF
	for variant: int in maxi(effective.candidate_count, 1):
		var candidate: WorldGenerator = WorldGenerator.new(seed_value, effective, variant)
		if not MapValidator.validate(candidate).is_empty():
			continue
		var value: float = score(candidate, effective)
		if value > best_score:
			best_score = value
			best = candidate
	if best == null:
		return MapValidator.build_valid(seed_value, effective)
	return best


## 总分（各项加权求和）。
static func score(generator: WorldGenerator, config: MapConfig = null) -> float:
	var parts: Dictionary = breakdown(generator, config)
	var total: float = 0.0
	for key: String in parts.keys():
		total += float(parts[key])
	return total


## 评分明细，供调试输出。
static func breakdown(generator: WorldGenerator, config: MapConfig = null) -> Dictionary:
	var effective: MapConfig = config if config != null else MapConfig.new()
	var run: RoomGraph = generator.run
	var main: PackedInt32Array = run.main_path
	var interior: Array[int] = []
	for index: int in range(1, main.size() - 1):
		interior.append(main[index])

	return {
		"path_ideal": _path_ideal(run, effective) * effective.weight_path_ideal,
		"branches": _branch_fit(run, effective) * effective.weight_branches,
		"shop_distance": _shop_distance(run, effective) * effective.weight_shop_distance,
		"type_variety": _type_variety(run, effective) * effective.weight_type_variety,
		"rest_spacing": _rest_gap_score(run, effective) * effective.weight_rest_spacing,
		"difficulty_ramp": _difficulty_ramp(run, interior) * effective.weight_difficulty_ramp,
	}


## 主路径长度接近理想值。
static func _path_ideal(run: RoomGraph, config: MapConfig) -> float:
	var ideal: int = maxi(config.ideal_path_len(), 1)
	return clampf(1.0 - absf(float(run.main_path.size() - ideal)) / float(ideal), 0.0, 1.0)


## 分支数量接近区间中点。
static func _branch_fit(run: RoomGraph, config: MapConfig) -> float:
	var mid: float = float(config.min_branches + config.max_branches) * 0.5
	if mid <= 0.0:
		return 1.0
	return clampf(1.0 - absf(float(run.branch_nodes.size()) - mid) / mid, 0.0, 1.0)


## 商店离 Boss 越远越好。
static func _shop_distance(run: RoomGraph, config: MapConfig) -> float:
	var shops: PackedInt32Array = run.nodes_of_type(RoomType.Kind.SHOP)
	if shops.is_empty():
		return 0.0
	var span: int = maxi(run.floors.size() - 1, 1)
	var nearest: int = span
	for node_id: int in shops:
		nearest = mini(nearest, run.floors_to_boss(node_id))
	return clampf(float(nearest) / float(span), 0.0, 1.0)


## 主路径上的房间类型多样性。
static func _type_variety(run: RoomGraph, _config: MapConfig) -> float:
	var kinds: Dictionary = {}
	for node_id: int in run.main_path:
		kinds[run.type_of(node_id)] = true
	return clampf(float(kinds.size()) / float(RoomType.COUNT), 0.0, 1.0)



## 后半段比前半段更难。
static func _difficulty_ramp(run: RoomGraph, interior: Array[int]) -> float:
	if interior.size() < 2:
		return 1.0
	var half: int = interior.size() / 2
	var first: float = 0.0
	var second: float = 0.0
	for index: int in interior.size():
		var value: float = float(DIFFICULTY.get(run.type_of(interior[index]), 0.5))
		if index < half:
			first += value
		else:
			second += value
	first /= float(maxi(half, 1))
	second /= float(maxi(interior.size() - half, 1))
	return clampf(0.5 + (second - first), 0.0, 1.0)


## 休息点间隔是否合理（按每 rest_every_floors 层一个）。
static func _rest_gap_score(run: RoomGraph, config: MapConfig) -> float:
	var floors: Array[int] = []
	for node_id: int in run.nodes_of_type(RoomType.Kind.REST):
		floors.append(RunGraph.floor_of(node_id))
	if floors.size() < 2:
		return 1.0
	floors.sort()
	var smallest: int = 2147483647
	for index: int in range(1, floors.size()):
		smallest = mini(smallest, floors[index] - floors[index - 1])
	return clampf(float(smallest) / float(maxi(config.rest_every_floors, 1)), 0.0, 1.0)