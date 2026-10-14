class_name HeatSystem
extends RefCounted

## 热量系统：积累、冷却、过载惩罚。
## 只算数值与状态；红闪 / 耳鸣 / 黑烟等表现由表现层订阅 overloaded 信号。

signal heat_changed(heat: float)
signal overloaded(report: Dictionary)
signal lock_changed(locked: bool)

var heat: float = 0.0
## 连续叠相同组合的次数，每次额外加热量，不设上限。
var consecutive_stacks: int = 0
var overload_count: int = 0
## 过载后的炼金锁定剩余时间。
var lock_remaining: float = 0.0
## 过载后的武器失效剩余时间。
var weapon_disabled_remaining: float = 0.0
## 升级 / 遗物带来的修正：热量积累倍率（热量减缓）、冷却倍率（热量冷却）、
## 过载惩罚时长倍率（过热缩短）。默认 1.0，由 AlchemyStation 按进度写入。
var gain_multiplier: float = 1.0
var cooldown_multiplier: float = 1.0
var overload_duration_multiplier: float = 1.0

func can_brew() -> bool:
	return lock_remaining <= 0.0 and heat < AlchemyRules.HEAT_MAX

func is_weapon_disabled() -> bool:
	return weapon_disabled_remaining > 0.0

func is_locked() -> bool:
	return lock_remaining > 0.0

## 每次炼金：20 + 连续叠加次数×5 + 过载词条加成×诅咒倍率。
func add_brew(overload_bonus: float, curse_multiplier: float) -> float:
	var gain: float = AlchemyRules.heat_gain(consecutive_stacks, overload_bonus, curse_multiplier)
	gain *= maxf(gain_multiplier, 0.0)
	add_heat(gain)
	return gain

## 受击打断：额外 +10 热量。
func add_interrupt() -> float:
	var gain: float = AlchemyRules.HEAT_PER_INTERRUPT * maxf(gain_multiplier, 0.0)
	add_heat(gain)
	return gain

func add_heat(amount: float) -> void:
	heat = clampf(heat + amount, AlchemyRules.HEAT_MIN, AlchemyRules.HEAT_MAX)
	heat_changed.emit(heat)
	if heat >= AlchemyRules.HEAT_MAX:
		trigger_overload()

## 连击计数：相同组合叠加时递增，换新组合时清零。
func note_same_combo() -> void:
	consecutive_stacks += 1

func reset_streak() -> void:
	consecutive_stacks = 0

## 热量满 100 触发过载；返回给表现层 / 战斗层用的惩罚清单。
func trigger_overload() -> Dictionary:
	overload_count += 1
	consecutive_stacks = 0
	heat = AlchemyRules.HEAT_MIN
	var scale: float = clampf(overload_duration_multiplier, 0.0, 1.0)
	lock_remaining = AlchemyRules.OVERLOAD_LOCKOUT * scale
	weapon_disabled_remaining = AlchemyRules.OVERLOAD_WEAPON_DISABLE * scale
	var report: Dictionary = {
		"weapon_disable": weapon_disabled_remaining,
		"lockout": lock_remaining,
		"blast_radius": AlchemyRules.OVERLOAD_BLAST_RADIUS,
		"blast_damage": AlchemyRules.OVERLOAD_BLAST_DAMAGE,
		"self_damage": AlchemyRules.OVERLOAD_SELF_DAMAGE,
		"material_loss_ratio": AlchemyRules.OVERLOAD_MATERIAL_LOSS_RATIO,
	}
	heat_changed.emit(heat)
	lock_changed.emit(true)
	overloaded.emit(report)
	return report

## 冷却：非战斗快速、战斗中缓慢，击杀加速。
func tick(delta: float, in_combat: bool, kills: int = 0) -> void:
	if lock_remaining > 0.0:
		lock_remaining = maxf(lock_remaining - delta, 0.0)
		if lock_remaining <= 0.0:
			lock_changed.emit(false)
	weapon_disabled_remaining = maxf(weapon_disabled_remaining - delta, 0.0)
	if heat <= AlchemyRules.HEAT_MIN:
		return
	var rate: float = AlchemyRules.HEAT_COOLDOWN_COMBAT if in_combat else AlchemyRules.HEAT_COOLDOWN_IDLE
	rate += float(maxi(kills, 0)) * AlchemyRules.HEAT_COOLDOWN_KILL_BONUS
	rate *= maxf(cooldown_multiplier, 0.0)
	heat = maxf(heat - rate * delta, AlchemyRules.HEAT_MIN)
	heat_changed.emit(heat)

## 过热警告分级：0 正常、1 黄色、2 橙色、3 红色、4 过载。
func warning_level() -> int:
	var percent: float = heat / AlchemyRules.HEAT_MAX * 100.0
	if percent >= 100.0:
		return 4
	if percent >= 90.0:
		return 3
	if percent >= 75.0:
		return 2
	if percent >= 50.0:
		return 1
	return 0

func reset() -> void:
	heat = AlchemyRules.HEAT_MIN
	consecutive_stacks = 0
	lock_remaining = 0.0
	weapon_disabled_remaining = 0.0
	heat_changed.emit(heat)
