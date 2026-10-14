class_name AlchemyLivingSplit
extends RefCounted

## 活体武器分裂：活体词条到 V 级后，武器击杀累积到阈值就分裂出临时分身。
##
## 纯逻辑：只负责「攒击杀 → 决定分裂数量 / 时长 / 伤害比例」，
## 真正生成分身的节点由战斗层订阅 split_ready 信号处理。

signal split_ready(count: int)
signal changed

## 触发一次分裂需要的击杀数。
const KILLS_PER_SPLIT: int = 3
## 同时存在的分身上限。
const MAX_SPLITS: int = 3
## 分身基础时长（秒）与每级增量。
const SPLIT_DURATION_BASE: float = 3.0
const SPLIT_DURATION_PER_LEVEL: float = 1.0
## 分身伤害相对武器基础伤害的比例。
const SPLIT_DAMAGE_RATIO_BASE: float = 0.35
const SPLIT_DAMAGE_RATIO_PER_LEVEL: float = 0.05

## 当前累积的击杀数。
var kill_progress: int = 0
## 已攒够但还没被战斗层取走的分身数。
var _pending: int = 0


## 组合是否具备分裂能力：活体词条到 V 级（split 标志）。
static func can_split(combo: BrewCombo) -> bool:
	return _living_trait(combo) != null and _living_trait(combo).has_flag(&"split")


static func _living_trait(combo: BrewCombo) -> TraitInstance:
	if combo == null:
		return null
	for trait_instance: TraitInstance in combo.traits:
		if trait_instance.id == &"living":
			return trait_instance
	return null


## 一次分裂产生的分身数量：随层数增加，上限 MAX_SPLITS。
static func split_count(combo: BrewCombo) -> int:
	var trait_instance: TraitInstance = _living_trait(combo)
	if trait_instance == null or not trait_instance.has_flag(&"split"):
		return 0
	return clampi(1 + trait_instance.stacks - 1, 1, MAX_SPLITS)


## 分身存活时长（秒）。
static func split_duration(combo: BrewCombo) -> float:
	var trait_instance: TraitInstance = _living_trait(combo)
	if trait_instance == null or not trait_instance.has_flag(&"split"):
		return 0.0
	return SPLIT_DURATION_BASE + SPLIT_DURATION_PER_LEVEL * float(trait_instance.level)


## 分身伤害相对武器基础伤害的比例。
static func split_damage_ratio(combo: BrewCombo) -> float:
	var trait_instance: TraitInstance = _living_trait(combo)
	if trait_instance == null or not trait_instance.has_flag(&"split"):
		return 0.0
	return SPLIT_DAMAGE_RATIO_BASE + SPLIT_DAMAGE_RATIO_PER_LEVEL * float(trait_instance.level)


## 活体 IV 起击杀回血；返回回复量（0 表示不回血）。
static func kill_heal(combo: BrewCombo) -> float:
	var trait_instance: TraitInstance = _living_trait(combo)
	if trait_instance == null or not trait_instance.has_flag(&"kill_heal"):
		return 0.0
	return 1.0 + 0.5 * float(trait_instance.level)


## 记录一次击杀；返回本次新攒出的分身数（可能为 0）。
func note_kill(combo: BrewCombo) -> int:
	if not can_split(combo):
		kill_progress = 0
		return 0
	kill_progress += 1
	var spawned: int = 0
	while kill_progress >= KILLS_PER_SPLIT:
		kill_progress -= KILLS_PER_SPLIT
		_pending += split_count(combo)
		spawned += 1
	if _pending > 0:
		var count: int = _pending
		_pending = 0
		split_ready.emit(count)
		changed.emit()
		return count
	return 0


## 还差几次击杀触发分裂。
func kills_until_split() -> int:
	return maxi(KILLS_PER_SPLIT - kill_progress, 0)


func reset() -> void:
	kill_progress = 0
	_pending = 0
	changed.emit()
