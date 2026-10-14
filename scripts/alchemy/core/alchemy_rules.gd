class_name AlchemyRules
extends RefCounted

## 炼金系统的唯一数值真源：倍率表、基础时长、热量常量与核心公式。
## 全部是静态纯函数，不依赖场景树，单元测试可以直接断言公式结果。

## 词条等级 I~V 的倍率。
const LEVEL_MULTIPLIERS: Array[float] = [1.0, 1.3, 1.6, 2.0, 2.5]
## 同词条层数 1~5 的叠加倍率；5 层以上不再增加。
const STACK_MULTIPLIERS: Array[float] = [1.0, 1.5, 1.75, 1.85, 1.9]
const MAX_TRAIT_LEVEL: int = 5
const MAX_STACK_INDEX: int = 4

## 效果基础时长（秒）。
const BASE_DURATION: float = 12.0

## 词条池上限：最小可玩原型 6，正式 8~10。
const POOL_LIMIT_PROTOTYPE: int = 6
const POOL_LIMIT_FULL: int = 10

## 素材槽。
const DEFAULT_MATERIAL_SLOTS: int = 2
const MAX_MATERIAL_SLOTS: int = 4

## 基础吸附半径（格）；「磁」词条按等级在此基础上扩大拉拽范围。
const BASE_ADSORB_RADIUS_TILES: float = 3.0

## 热量。
const HEAT_MIN: float = 0.0
const HEAT_MAX: float = 100.0
const HEAT_PER_BREW: float = 20.0
const HEAT_PER_SAME_STACK: float = 5.0
const HEAT_PER_INTERRUPT: float = 10.0
## 过载惩罚。
const OVERLOAD_WEAPON_DISABLE: float = 8.0
const OVERLOAD_LOCKOUT: float = 3.0
const OVERLOAD_BLAST_RADIUS: float = 3.0
const OVERLOAD_BLAST_DAMAGE: float = 30.0
const OVERLOAD_SELF_DAMAGE: float = 15.0
## 过载时随机一种材料损失一半。
const OVERLOAD_MATERIAL_LOSS_RATIO: float = 0.5

## 热量冷却速度（点/秒）：非战斗快速、战斗中缓慢、击杀加速。
const HEAT_COOLDOWN_IDLE: float = 12.0
const HEAT_COOLDOWN_COMBAT: float = 3.0
const HEAT_COOLDOWN_KILL_BONUS: float = 8.0

## 替换爆发：旧效果以该比例强度爆发一次。
const REPLACEMENT_BURST_RATIO: float = 0.5
## 替换爆发的范围（格）与基准伤害；实际伤害 = 基准 × 爆发强度。
const REPLACEMENT_BURST_RADIUS_TILES: float = 2.0
const REPLACEMENT_BURST_BASE_DAMAGE: float = 10.0

## 品质修正：普通 / 稀有 / 史诗 / 传说 / Boss。
const QUALITY_MULTIPLIERS: Array[float] = [1.0, 1.15, 1.3, 1.5, 1.7]
## Boss 材料的品质档位（只由 Boss 掉落）。
const BOSS_QUALITY: int = 4

## 按 E 的长按判定阈值（秒）。
const LONG_PRESS_SECONDS: float = 0.35
## 短按 E 复用配方后的动作硬直（秒）；遗物「快速之手」免除。
const SHORT_PRESS_STUN: float = 0.12
## 受击打断后的炼金冷却（秒）。
const INTERRUPT_COOLDOWN: float = 1.0
## 慢动作时间缩放。
const SLOW_MOTION_SCALE: float = 0.25
const SLOW_MOTION_SCALE_RELIC: float = 0.15

## 召唤物（召唤词条 / 骨 V 骷髅 / 灵魂 V 游魂 / 活体 V 分身共用同一套单位）。
## 伤害按武器基础伤害 × 比例折算，避免召唤物伤害随词条等级线性膨胀。
const SUMMON_DAMAGE_RATIO: float = 0.30
## 召唤物攻击间隔（秒）与出手距离（格）。
const SUMMON_ATTACK_INTERVAL: float = 0.6
const SUMMON_ATTACK_RANGE_TILES: float = 0.9
## 召唤物索敌半径（格）与移动速度（像素/秒）。
const SUMMON_SEARCH_RADIUS_TILES: float = 4.0
const SUMMON_MOVE_SPEED: float = 130.0
## 召唤物消散自爆：范围（格）与伤害比例。
const SUMMON_EXPLODE_RADIUS_TILES: float = 1.5
const SUMMON_EXPLODE_DAMAGE_RATIO: float = 0.6
## 骨 V「可召唤骷髅」与灵魂 V「可爆炸」的触发概率与寿命。
const SKELETON_CHANCE: float = 0.15
const SKELETON_DURATION: float = 8.0
const SOUL_BURST_CHANCE: float = 0.25
const SOUL_BURST_DURATION: float = 8.0

## 修正系数下限，避免负修正把时长或伤害压成负数。
const MIN_DURATION_FACTOR: float = 0.05
const MIN_DAMAGE_FACTOR: float = 0.05

static func clamp_level(level: int) -> int:
	return clampi(level, 1, MAX_TRAIT_LEVEL)

static func level_multiplier(level: int) -> float:
	return LEVEL_MULTIPLIERS[clamp_level(level) - 1]

static func stack_multiplier(stacks: int) -> float:
	return STACK_MULTIPLIERS[clampi(stacks - 1, 0, MAX_STACK_INDEX)]

static func quality_multiplier(quality: int) -> float:
	return QUALITY_MULTIPLIERS[clampi(quality, 0, QUALITY_MULTIPLIERS.size() - 1)]

## 最终时长 = 12s × (1+持续) × (1+稳定) × (1+活体) × (1+诅咒) × 品质修正。
static func final_duration(duration_modifier: float, stability_modifier: float, living_modifier: float, curse_modifier: float, quality: int) -> float:
	var factor: float = (1.0 + duration_modifier) * (1.0 + stability_modifier) * (1.0 + living_modifier) * (1.0 + curse_modifier)
	return BASE_DURATION * maxf(factor, MIN_DURATION_FACTOR) * quality_multiplier(quality)

## 最终伤害 = 武器基础伤害 × 等级倍率 × 叠加倍率 × 持续时间修正 × 反应倍率 × 品质修正。
static func final_damage(base_damage: float, level: int, stacks: int, duration_modifier: float, reaction_multiplier: float, quality: int) -> float:
	var factor: float = level_multiplier(level) * stack_multiplier(stacks)
	factor *= maxf(1.0 + duration_modifier, MIN_DAMAGE_FACTOR)
	factor *= maxf(reaction_multiplier, 0.0)
	factor *= quality_multiplier(quality)
	return maxf(base_damage, 0.0) * factor

## 热量增加 = 20 + 连续叠加次数×5 + 过载词条加成 × 诅咒倍率。
static func heat_gain(consecutive_stacks: int, overload_bonus: float, curse_multiplier: float) -> float:
	return HEAT_PER_BREW + float(maxi(consecutive_stacks, 0)) * HEAT_PER_SAME_STACK + maxf(overload_bonus, 0.0) * maxf(curse_multiplier, 0.0)
