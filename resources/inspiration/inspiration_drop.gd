class_name InspirationDrop
extends RefCounted

## 灵感光点的表现参数与动画阶段（纯数据）。
## 关键特性：无范围限制，悬停结束后无条件飞向玩家，穿墙，不受物理阻挡。

## 飞行轨迹。
enum Trajectory {
	STRAIGHT = 0,  ## 直线（小怪）
	ARC = 1,       ## 弧线加速（精英）
	SPIRAL = 2,    ## 螺旋（Boss）
	RIBBON = 3,    ## 光带（事件）
}

## 动画阶段（秒）。
const BURST_END: float = 0.1        ## 阶段1 生成：从敌人位置爆出，带闪光
const SCATTER_END: float = 0.4      ## 阶段2 散开：向随机方向弹射，偏向上方
const HOVER_END: float = 0.8        ## 阶段3 悬停：减速到 0，轻微上下浮动
const FLY_IN_LAST: float = 0.2      ## 阶段5 飞入：加速冲向玩家，缩小消失

## 散开参数。
const SCATTER_SPEED_MIN: float = 3.0   ## 格/秒
const SCATTER_SPEED_MAX: float = 5.0
const SCATTER_DISTANCE_MIN: float = 0.5  ## 格
const SCATTER_DISTANCE_MAX: float = 1.5
const SCATTER_UPWARD_BIAS: float = 0.6   ## 偏向上方的比例

## 飞向玩家：初速 2 → 末速 20 格/秒，先慢后快。
const FLY_SPEED_START: float = 2.0
const FLY_SPEED_END: float = 20.0

## 视觉参数。
const DIAMETER_MIN: float = 4.0   ## 像素
const DIAMETER_MAX: float = 12.0
const TRAIL_SEGMENTS_MIN: int = 3
const TRAIL_SEGMENTS_MAX: int = 8

## 对象池：预分配 200 个光点。
const POOL_SIZE: int = 200
## 同屏光点超过该数量时合并为光团，飞入后再拆分数字。
const MERGE_THRESHOLD: int = 30

## 差异化表现：悬停时长 / 轨迹 / 音效 / 分批飞入。
const VISUALS: Dictionary = {
	InspirationRules.Source.NORMAL: {"hover": 0.2, "trajectory": Trajectory.STRAIGHT, "sfx": &"inspiration_ding", "batched": false},
	InspirationRules.Source.ELITE: {"hover": 0.4, "trajectory": Trajectory.ARC, "sfx": &"inspiration_bell", "batched": true},
	InspirationRules.Source.REGION_BOSS: {"hover": 0.6, "trajectory": Trajectory.SPIRAL, "sfx": &"inspiration_chime", "batched": true},
	InspirationRules.Source.FINAL_BOSS: {"hover": 0.6, "trajectory": Trajectory.SPIRAL, "sfx": &"inspiration_chime", "batched": true},
	InspirationRules.Source.SPECIAL: {"hover": 0.3, "trajectory": Trajectory.ARC, "sfx": &"inspiration_bell", "batched": false},
	InspirationRules.Source.BREAKABLE: {"hover": 0.2, "trajectory": Trajectory.STRAIGHT, "sfx": &"inspiration_ding", "batched": false},
	InspirationRules.Source.EVENT: {"hover": 0.3, "trajectory": Trajectory.RIBBON, "sfx": &"inspiration_bell_soft", "batched": false},
	InspirationRules.Source.CODEX: {"hover": 0.3, "trajectory": Trajectory.RIBBON, "sfx": &"inspiration_bell_soft", "batched": false},
	InspirationRules.Source.FLAWLESS_ROOM: {"hover": 0.3, "trajectory": Trajectory.RIBBON, "sfx": &"inspiration_bell_soft", "batched": false},
	InspirationRules.Source.REPLACEMENT_BURST: {"hover": 0.2, "trajectory": Trajectory.ARC, "sfx": &"inspiration_ding", "batched": false},
}


static func hover_duration(source: int) -> float:
	return float(VISUALS.get(source, {}).get("hover", HOVER_END - SCATTER_END))


static func trajectory_of(source: int) -> int:
	return int(VISUALS.get(source, {}).get("trajectory", Trajectory.STRAIGHT))


static func sfx_of(source: int) -> StringName:
	return StringName(VISUALS.get(source, {}).get("sfx", &"inspiration_ding"))


## 是否为分批飞入（精英/Boss）。
static func is_batched(source: int) -> bool:
	return bool(VISUALS.get(source, {}).get("batched", false))


## 光点数量：数量越大越多点，但不超过单次上限。
static func point_count(amount: int, source: int) -> int:
	if amount <= 0:
		return 0
	if is_batched(source):
		return clampi(amount / 5, 3, 12)
	return clampi(amount, 1, 8)


## 单点数值：总灵感在光点之间尽量平均分配。
static func split_amount(amount: int, points: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if points <= 0:
		return result
	var base: int = amount / points
	var remainder: int = amount % points
	for index: int in points:
		result.append(base + (1 if index < remainder else 0))
	return result
