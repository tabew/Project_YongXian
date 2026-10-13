class_name MapConfig
extends Resource

## 一局地图骨架的可调参数。
##
## 全部有默认值，不配置也能跑；默认值与改造前的固定 8 层 14 区域完全一致，
## 所以不传配置时地图与旧版本逐位相同。策划可保存成 .tres 后挂到 WorldGenerator。

## 层数（等于主路径长度）。
@export_range(3, 32, 1) var floor_count: int = 8
## 哪些层带岔路；留空则自动取首尾层之外的中间层。
@export var branch_floors: Array[int] = []

## 主路径长度约束。
@export_range(3, 32, 1) var min_path_len: int = 6
@export_range(3, 32, 1) var max_path_len: int = 10
## 岔路数量约束。
@export_range(0, 32, 1) var min_branches: int = 4
@export_range(0, 32, 1) var max_branches: int = 8

## 关键房间数量。
@export_range(1, 8, 1) var shop_count: int = 1
@export_range(1, 8, 1) var min_rewards: int = 1
@export_range(1, 8, 1) var max_rewards: int = 2
## 休息点：每多少层一个（按层数决定）。
@export_range(1, 16, 1) var rest_every_floors: int = 3
@export_range(0, 8, 1) var min_rests: int = 1
## 关键房间与 Boss 之间至少间隔的层数。
@export_range(0, 8, 1) var boss_key_buffer: int = 1

## 节奏模板：主路径（不含起点与 Boss）的类型序列，可覆盖。
@export var rhythm_templates: Array = []

## 岔路房间的类型权重（战斗 / 奖励）。
@export_range(0.0, 1.0, 0.01) var branch_reward_chance: float = 0.45

## 硬校验失败时的重生成次数上限。
@export_range(0, 200, 1) var max_retries: int = 20
## 软评分挑选的候选数量。
@export_range(1, 200, 1) var candidate_count: int = 12

## 软评分权重。
@export_range(0.0, 10.0, 0.05) var weight_path_ideal: float = 1.0
@export_range(0.0, 10.0, 0.05) var weight_branches: float = 0.6
@export_range(0.0, 10.0, 0.05) var weight_shop_distance: float = 0.8
@export_range(0.0, 10.0, 0.05) var weight_type_variety: float = 0.5
@export_range(0.0, 10.0, 0.05) var weight_rest_spacing: float = 0.5
@export_range(0.0, 10.0, 0.05) var weight_difficulty_ramp: float = 0.7

## 默认节奏模板；长度与 floor_count 不一致时会自动伸缩。
const DEFAULT_RHYTHM_TEMPLATES: Array = [
	[RoomType.Kind.COMBAT, RoomType.Kind.COMBAT, RoomType.Kind.COMBAT, RoomType.Kind.REWARD,
		RoomType.Kind.COMBAT, RoomType.Kind.COMBAT, RoomType.Kind.SHOP, RoomType.Kind.COMBAT,
		RoomType.Kind.REWARD, RoomType.Kind.COMBAT],
	[RoomType.Kind.COMBAT, RoomType.Kind.COMBAT, RoomType.Kind.REWARD, RoomType.Kind.COMBAT,
		RoomType.Kind.EVENT, RoomType.Kind.COMBAT, RoomType.Kind.SHOP, RoomType.Kind.COMBAT,
		RoomType.Kind.COMBAT],
	[RoomType.Kind.COMBAT, RoomType.Kind.REWARD, RoomType.Kind.COMBAT, RoomType.Kind.COMBAT,
		RoomType.Kind.SHOP, RoomType.Kind.COMBAT, RoomType.Kind.REWARD, RoomType.Kind.COMBAT],
	[RoomType.Kind.COMBAT, RoomType.Kind.COMBAT, RoomType.Kind.REST, RoomType.Kind.COMBAT,
		RoomType.Kind.REWARD, RoomType.Kind.COMBAT, RoomType.Kind.SHOP, RoomType.Kind.COMBAT],
]


## 岔路层：留空时取首尾层之外的中间层（与旧实现一致）。
func resolved_branch_floors() -> Array[int]:
	if not branch_floors.is_empty():
		return branch_floors.duplicate()
	var result: Array[int] = []
	for floor_index: int in range(1, maxi(floor_count - 1, 1)):
		result.append(floor_index)
	return result


func resolved_rhythm_templates() -> Array:
	return rhythm_templates if not rhythm_templates.is_empty() else DEFAULT_RHYTHM_TEMPLATES


## 理想主路径长度，用于软评分。
func ideal_path_len() -> int:
	return int(roundf(float(min_path_len + max_path_len) * 0.5))


func describe() -> String:
	return "层=%d 岔路=%d 路径=[%d,%d] 分支=[%d,%d]" % [
		floor_count, resolved_branch_floors().size(),
		min_path_len, max_path_len, min_branches, max_branches,
	]
