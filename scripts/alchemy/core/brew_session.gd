class_name BrewSession
extends RefCounted

## 单一激活炼金组合 + 持续时间 + 热量的纯逻辑会话。
## 相同组合（按效果标签判定）叠加时间；不同组合替换旧效果，旧效果以 50% 强度爆发一次。
## 不依赖场景树，可单独单元测试。

signal combo_activated(combo: BrewCombo)
signal combo_stacked(combo: BrewCombo, stacks: int)
signal combo_replaced(previous: BrewCombo, burst_power: float, reactions: Array)
signal combo_expired(combo: BrewCombo)
signal brew_rejected(reason: String)
signal self_damage(amount: float)

var active_combo: BrewCombo = null
var duration: DurationTracker = DurationTracker.new()
var heat: HeatSystem = HeatSystem.new()
var pool_limit: int = AlchemyRules.POOL_LIMIT_PROTOTYPE
## 上次成功炼金用到的材料 id，战斗中短按 E 直接复用。
var last_recipe: Array[int] = []
## 升级 / 遗物带来的修正：替换爆发强度比例（爆发强化等）、持续时间加成（时间沙漏）。
var burst_ratio: float = AlchemyRules.REPLACEMENT_BURST_RATIO
var duration_bonus: float = 0.0
## 遗物「时之沙」：炼金不消耗时间，激活中的效果倒计时不流逝。
var freeze_duration: bool = false

var _pending_self_damage: float = 0.0

func _init(limit: int = AlchemyRules.POOL_LIMIT_PROTOTYPE) -> void:
	pool_limit = limit
	heat.overloaded.connect(_on_overload)

func is_active() -> bool:
	return active_combo != null and duration.is_active()

func combo_power() -> float:
	return active_combo.power if active_combo != null else 1.0

func weapon_disabled() -> bool:
	return heat.is_weapon_disabled()

## 炼金一次。返回生效的组合；被拒绝（热量锁定 / 没有词条）时返回 null。
func brew(materials: Array[AlchemyMaterial]) -> BrewCombo:
	return brew_with(BrewPipeline.evaluate(materials, pool_limit), materials)


## 用预先算好的组合炼金：站点可以先往组合里注入诅咒修正，再走同一套叠加 / 替换逻辑。
func brew_with(combo: BrewCombo, materials: Array[AlchemyMaterial]) -> BrewCombo:
	if not heat.can_brew():
		brew_rejected.emit("过热锁定中" if heat.is_locked() else "热量已满")
		return null
	if combo == null or combo.is_empty():
		brew_rejected.emit("素材槽里没有可用词条")
		return null
	if active_combo != null and active_combo.matches(combo):
		# 相同组合：时间叠加，无硬上限。
		duration.extend(_scaled_duration(combo))
		heat.note_same_combo()
		active_combo = combo
		combo_stacked.emit(combo, heat.consecutive_stacks)
	else:
		if active_combo != null:
			# 不同组合：替换旧组合，旧效果以 50% 强度爆发一次并触发词条反应。
			heat.reset_streak()
			combo_replaced.emit(active_combo.duplicate_combo(), active_combo.burst_power(burst_ratio), active_combo.reactions.duplicate(true))
		duration.start(_scaled_duration(combo))
		active_combo = combo
		combo_activated.emit(combo)
	heat.add_brew(combo.overload_heat_bonus, combo.curse_multiplier)
	last_recipe = recipe_ids(materials)
	return combo


## 组合基础时长叠加「时间沙漏」等持续加成。
func _scaled_duration(combo: BrewCombo) -> float:
	return combo.base_duration * maxf(1.0 + duration_bonus, 0.0)

## 受击打断：材料不丢，只加热量。
func notify_interrupt() -> void:
	heat.add_interrupt()

## 推进倒计时与冷却；paused 为真（非战斗 / 慢动作）时倒计时冻结。
func tick(delta: float, paused: bool, in_combat: bool, kills: int = 0) -> void:
	if duration.tick(delta, paused or freeze_duration) and active_combo != null:
		var ended: BrewCombo = active_combo
		active_combo = null
		combo_expired.emit(ended)
	heat.tick(delta, in_combat, kills)
	if active_combo == null or paused or active_combo.self_damage <= 0.0:
		return
	_pending_self_damage += active_combo.self_damage * delta
	if _pending_self_damage >= 1.0:
		var whole: float = floorf(_pending_self_damage)
		_pending_self_damage -= whole
		self_damage.emit(whole)

## 立即结束当前效果（过载 / 场景重建）。
func force_end() -> void:
	if active_combo == null:
		return
	var ended: BrewCombo = active_combo
	active_combo = null
	duration.clear()
	combo_expired.emit(ended)

func reset() -> void:
	active_combo = null
	duration.clear()
	heat.reset()
	last_recipe.clear()
	_pending_self_damage = 0.0

static func recipe_ids(materials: Array[AlchemyMaterial]) -> Array[int]:
	var ids: Array[int] = []
	for material: AlchemyMaterial in materials:
		if material != null:
			ids.append(material.id)
	return ids

func _on_overload(_report: Dictionary) -> void:
	force_end()
