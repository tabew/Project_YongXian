extends Node

class_name InspirationManager

## 灵感系统运行时单例：把「永久池 + 局内账本 + 出发配置」三件事集中在一处。
##
## 分工：
## - PermanentUpgradeState：局外永久灵感池与已购升级（死亡不掉）。
## - InspirationRun：本局账本（死亡损失、通关结算）。
## - 出发配置：携带武器 / 携带材料 / 难度档位。
##
## 纯数值都在 resources/inspiration 与 resources/workshop 里，本节点只做编排与信号广播。
## 不直接读炼金系统内部数据：对外只发布 get_permanent_modifiers()，炼金侧按需读取。

## 永久池发生变化（购买升级、通关结算入账）。
signal permanent_changed
## 局内灵感发生变化（光点飞入 / 掉落）。
signal run_changed(gained: int, in_flight: int)
## 永久升级购买成功。
signal upgrade_purchased(id: StringName, level: int)
## 一局开始 / 结束。
signal run_started(difficulty_tier: int)
signal run_ended(result: Dictionary)
## 需要世界层生成灵感光点。
signal inspiration_dropped(position: Vector2, amount: int, source: int)
## 死亡结算完成，供 UI 演出。
signal run_failed(detail: Dictionary)

## 永久升级与永久灵感池。
var state: PermanentUpgradeState = PermanentUpgradeState.new()
## 本局账本；不在局内时 also 保留上一局的结果。
var run: InspirationRun = InspirationRun.new()

## 出发配置：武器 id、携带材料 id 列表、难度档位。
var selected_weapon_id: StringName = &"longsword"
var carried_material_ids: PackedInt32Array = PackedInt32Array()
var difficulty_tier: int = DifficultyTier.Tier.APPRENTICE
## 材料库解锁的携带格数上限（初始 1，可解锁到 3）。
var material_slot_capacity: int = 1
## 是否已开始一局（用于区分局内 / 局外）。
var in_run: bool = false


# ------------------------------------------------------------ 永久池

func add_permanent_inspiration(amount: int) -> void:
	if amount <= 0:
		return
	state.add_inspiration(amount)
	permanent_changed.emit()


func purchase_upgrade(id: StringName) -> bool:
	if not state.purchase(id):
		return false
	upgrade_purchased.emit(id, state.level_of(id))
	permanent_changed.emit()
	return true


## 已购升级对应的炼金侧等级：id → 层数。供炼金桥接使用。
func alchemy_upgrade_levels() -> Dictionary:
	var result: Dictionary = {}
	for upgrade: PermanentUpgrade in PermanentUpgradeCatalog.all():
		var level: int = state.level_of(upgrade.id)
		if level > 0 and upgrade.effect_kind != PermanentUpgradeCatalog.EFFECT_RETENTION:
			result[upgrade.id] = level
	return result


## 对外发布的永久修正表（明确接口，炼金 / 战斗 / UI 都读这一份）。
## 键名与 PermanentUpgradeCatalog 的 EFFECT_* 一一对应，另加几个派生键。
func get_permanent_modifiers() -> Dictionary:
	var catalog := PermanentUpgradeCatalog
	var result: Dictionary = {
		&"material_slots_plus": int(state.effect_value(catalog.EFFECT_MATERIAL_SLOTS)),
		&"bag_capacity_plus": int(state.effect_value(catalog.EFFECT_BAG_CAPACITY)),
		&"stack_multiplier": 1.0 + state.effect_value(catalog.EFFECT_STACK_BONUS),
		&"base_duration_plus": state.effect_value(catalog.EFFECT_BASE_DURATION),
		&"burst_ratio_plus": state.effect_value(catalog.EFFECT_BURST_RATIO),
		&"heat_cooldown_multiplier": 1.0 + state.effect_value(catalog.EFFECT_HEAT_COOLDOWN),
		&"heat_max_plus": state.effect_value(catalog.EFFECT_HEAT_MAX),
		&"adsorb_radius_plus": state.effect_value(catalog.EFFECT_ADSORB_RADIUS),
		&"reaction_bonus": state.effect_value(catalog.EFFECT_REACTION_BONUS),
		&"overload_loss_reduction": state.effect_value(catalog.EFFECT_OVERLOAD_LOSS),
		&"overload_disable_reduction": state.effect_value(catalog.EFFECT_OVERLOAD_DISABLE),
		&"preset_slots_plus": int(state.effect_value(catalog.EFFECT_PRESET_SLOTS)),
		&"retention_ratio": state.retention_ratio(),
	}
	var element_levels: Dictionary = {}
	for trait_id: StringName in catalog.ELEMENT_TRAITS:
		var bonus: int = state.element_level(trait_id)
		if bonus > 0:
			element_levels[trait_id] = bonus
	result[&"element_levels"] = element_levels
	return result


## 把能一一对应的永久升级推给炼金台的 AlchemyProgression。
## 只调用炼金侧公开的 add_upgrade()，不读它的内部字段。
## 对应不上的项（基础时长、热量上限、逐元素等级、反应效果、过载细节）留在
## get_permanent_modifiers() 里，由炼金侧后续按需接入，避免这里硬塞错误语义。
func apply_to_alchemy_station(station: Node) -> int:
	if station == null:
		return 0
	var progression: Variant = station.get("progression")
	if progression == null or not (progression is Object):
		return 0
	if not progression.has_method("add_upgrade"):
		return 0
	var applied: int = 0
	for mapping: Array in ALCHEMY_BRIDGE:
		var our_id: StringName = mapping[0]
		var their_id: StringName = mapping[1]
		var per_level: int = int(mapping[2])
		var levels: int = state.level_of(our_id) * per_level
		if levels > 0:
			progression.call("add_upgrade", their_id, levels)
			applied += 1
	return applied


## 永久升级 → 炼金升级的映射：[本侧 id, 炼金 id, 每级折算层数]。
## 只列语义完全一致的项。
const ALCHEMY_BRIDGE: Array = [
	[&"material_slots", &"slot_plus", 1],
	[&"bag_capacity", &"bag_expand", 1],
	[&"stack_bonus", &"stack_plus", 1],
	[&"preset_slots", &"preset_plus", 1],
	[&"heat_cooldown", &"heat_cooldown", 1],
	[&"adsorb_radius", &"magnet_range", 1],
]


# ------------------------------------------------------------ 局内账本

func start_run() -> void:
	run.reset()
	in_run = true
	run_started.emit(difficulty_tier)


## 掉落：只负责记账与广播，具体光点由世界层生成。
func drop_inspiration(position: Vector2, amount: int, source: int) -> int:
	var value: int = run.launch(amount, source)
	if value > 0:
		inspiration_dropped.emit(position, value, source)
		run_changed.emit(run.gained, run.in_flight)
	return value


## 判定并掉落（走概率表）。
func roll_inspiration(position: Vector2, source: int, rng: RandomNumberGenerator) -> int:
	return drop_inspiration(position, InspirationRules.roll(source, rng), source)


## 光点飞入：把金额从「飞行中」转入「已获得」。
func collect_inspiration(amount: int) -> int:
	var value: int = run.collect(amount)
	if value > 0:
		run_changed.emit(run.gained, run.in_flight)
	return value


## 死亡：损失局内灵感，按留存升级保留少量，然后回工坊。
func fail_run() -> Dictionary:
	var detail: Dictionary = run.death(state.retention_level())
	detail["kept_ratio"] = state.retention_ratio()
	in_run = false
	state.add_inspiration(int(detail["kept"]))
	run_failed.emit(detail)
	run_changed.emit(run.gained, run.in_flight)
	permanent_changed.emit()
	return detail


## 通关：贤者之石结算，全部进永久池。
func finish_run(material_counts: Dictionary, performance_bonus: int = 0, codex_completion: float = 0.0, boss_material_count: int = 0) -> Dictionary:
	var result: Dictionary = run.settle(material_counts, difficulty_tier, performance_bonus, codex_completion, boss_material_count)
	in_run = false
	state.register_clear()
	state.add_inspiration(int(result["final"]))
	run_ended.emit(result)
	run_changed.emit(run.gained, run.in_flight)
	permanent_changed.emit()
	return result


# ------------------------------------------------------------ 出发配置

func set_difficulty(tier: int) -> bool:
	if not DifficultyTier.is_unlocked(tier, state.clears):
		return false
	difficulty_tier = tier
	return true


func set_weapon(id: StringName) -> void:
	selected_weapon_id = id


## 设置携带材料：数量与解锁格数双重要求。
func set_carried_materials(ids: PackedInt32Array) -> bool:
	if ids.size() > material_slot_capacity:
		return false
	for material_id: int in ids:
		if not MaterialCatalog.has_material(material_id):
			return false
	carried_material_ids = ids
	return true


func clear_run_state() -> void:
	run.reset()
	in_run = false


func to_dict() -> Dictionary:
	var carried: Array[int] = []
	for material_id: int in carried_material_ids:
		carried.append(material_id)
	return {
		"state": state.to_dict(),
		"weapon": String(selected_weapon_id),
		"carried": carried,
		"difficulty": difficulty_tier,
		"material_slot_capacity": material_slot_capacity,
	}


func from_dict(data: Dictionary) -> void:
	state.from_dict(data.get("state", {}))
	selected_weapon_id = StringName(data.get("weapon", &"longsword"))
	carried_material_ids.clear()
	for material_id: int in data.get("carried", []):
		carried_material_ids.append(material_id)
	difficulty_tier = clampi(int(data.get("difficulty", 0)), 0, DifficultyTier.COUNT - 1)
	material_slot_capacity = maxi(int(data.get("material_slot_capacity", 1)), 1)
