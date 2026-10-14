extends SceneTree

## 永久升级单元测试：配置表完整性、总消耗、购买与前置、效果聚合、存档往返。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_test_catalog()
	_test_total_cost()
	_test_prerequisites()
	_test_purchase_flow()
	_test_effects()
	_test_retention()
	_test_save_round_trip()
	_test_difficulty_unlock()
	print("PERMANENT UPGRADES: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_catalog() -> void:
	var all: Array[PermanentUpgrade] = PermanentUpgradeCatalog.all()
	_check(all.size() == 13 + PermanentUpgradeCatalog.ELEMENT_TRAITS.size(), "升级项数量 = 13 基础 + 13 元素")
	var ids: Dictionary = {}
	for upgrade: PermanentUpgrade in all:
		_check(upgrade.id != &"", "升级有 id")
		_check(not ids.has(upgrade.id), "升级 id 唯一：" + String(upgrade.id))
		ids[upgrade.id] = true
		_check(upgrade.name != "", "升级有名字：" + String(upgrade.id))
		_check(upgrade.max_level >= 1, "最大等级至少 1：" + String(upgrade.id))
		_check(upgrade.costs.size() == upgrade.max_level, "消耗表长度 = 最大等级：" + String(upgrade.id))
		_check(upgrade.effects.size() == upgrade.max_level, "效果表长度 = 最大等级：" + String(upgrade.id))
		_check(upgrade.effect_kind != &"", "有效果键：" + String(upgrade.id))
		for index: int in range(1, upgrade.costs.size()):
			_check(upgrade.costs[index] > upgrade.costs[index - 1], "消耗逐级递增：" + String(upgrade.id))
	for trait_id: StringName in PermanentUpgradeCatalog.ELEMENT_TRAITS:
		var element: PermanentUpgrade = PermanentUpgradeCatalog.find(StringName("element_" + String(trait_id)))
		_check(element != null and element.trait_id == trait_id, "元素升级存在：" + String(trait_id))
	_check(PermanentUpgradeCatalog.find(&"retention") != null, "灵感留存升级存在")
	_check(PermanentUpgradeCatalog.find(&"not_exist") == null, "未知 id 返回 null")


func _test_total_cost() -> void:
	var total: int = PermanentUpgradeCatalog.total_cost()
	_check(total >= 25000 and total <= 30000, "全部升满总消耗在 25000~30000（实际 %d）" % total)
	var manual: int = 0
	for upgrade: PermanentUpgrade in PermanentUpgradeCatalog.all():
		manual += upgrade.total_cost()
	_check(manual == total, "总消耗与逐项相加一致")


func _test_prerequisites() -> void:
	var disable: PermanentUpgrade = PermanentUpgradeCatalog.find(&"overload_disable")
	_check(disable.prerequisite_id == &"overload_loss", "过热失效需要先点过热损失")
	var state := PermanentUpgradeState.new()
	state.add_inspiration(100000)
	_check(not state.prerequisite_met(&"overload_disable"), "前置未满足")
	_check(not state.can_purchase(&"overload_disable"), "前置未满足不能购买")
	_check(state.purchase(&"overload_loss"), "购买过热损失")
	_check(state.prerequisite_met(&"overload_disable"), "前置满足")
	_check(state.can_purchase(&"overload_disable"), "可以购买过热失效")
	_check(PermanentUpgradeCatalog.dependents_of(&"overload_loss").size() == 1, "过热损失有一个后继升级")


func _test_purchase_flow() -> void:
	var state := PermanentUpgradeState.new()
	state.add_inspiration(1000)
	_check(state.level_of(&"bag_capacity") == 0, "初始 0 级")
	_check(state.cost_of(&"bag_capacity") == 300, "第一级 300")
	_check(state.purchase(&"bag_capacity"), "购买第一级")
	_check(state.inspiration == 700, "扣除灵感")
	_check(state.level_of(&"bag_capacity") == 1, "等级 +1")
	_check(state.cost_of(&"bag_capacity") == 600, "第二级 600")
	_check(state.purchase(&"bag_capacity"), "购买第二级")
	_check(not state.purchase(&"bag_capacity"), "灵感不足不能购买第三级")
	state.add_inspiration(2000)
	_check(state.purchase(&"bag_capacity"), "购买第三级")
	_check(state.is_maxed(&"bag_capacity"), "已满级")
	_check(state.cost_of(&"bag_capacity") == -1, "满级花费 -1")
	_check(not state.can_purchase(&"bag_capacity"), "满级不能继续购买")
	_check(state.total_spent() == 300 + 600 + 1200, "已花灵感统计")
	_check(not state.purchase(&"not_exist"), "未知升级不能购买")


func _test_effects() -> void:
	var state := PermanentUpgradeState.new()
	state.add_inspiration(100000)
	state.purchase(&"material_slots")
	state.purchase(&"material_slots")
	_check(int(state.effect_value(PermanentUpgradeCatalog.EFFECT_MATERIAL_SLOTS)) == 2, "素材槽累计 +2")
	state.purchase(&"heat_max")
	_check(is_equal_approx(state.effect_value(PermanentUpgradeCatalog.EFFECT_HEAT_MAX), 10.0), "热量上限 +10")
	state.purchase(&"retention")
	state.purchase(&"retention")
	_check(int(state.effect_value(PermanentUpgradeCatalog.EFFECT_RETENTION)) == 0, "留存不计入普通聚合")
	_check(state.element_level(&"fire") == 0, "未购买时元素等级 0")
	state.purchase(&"element_fire")
	_check(state.element_level(&"fire") == 1, "元素词条 +1 级")
	_check(state.element_level(&"ice") == 0, "其他元素不受影响")
	_check(int(state.effect_value(PermanentUpgradeCatalog.EFFECT_ELEMENT_LEVEL)) == 0, "元素等级单独查询")


func _test_retention() -> void:
	var state := PermanentUpgradeState.new()
	state.add_inspiration(100000)
	_check(is_zero_approx(state.retention_ratio()), "未购买时留存 0")
	state.purchase(&"retention")
	_check(state.retention_level() == 1 and is_equal_approx(state.retention_ratio(), 0.05), "留存 I")
	for index: int in 4:
		state.purchase(&"retention")
	_check(state.retention_level() == 5, "留存满级")
	_check(is_equal_approx(state.retention_ratio(), 0.25), "留存 V = 25%")
	_check(not state.purchase(&"retention"), "留存不能超过 5 级")


func _test_save_round_trip() -> void:
	var state := PermanentUpgradeState.new()
	state.add_inspiration(5000)
	state.purchase(&"preset_slots")
	state.purchase(&"element_dark")
	state.register_clear()
	var data: Dictionary = state.to_dict()
	var restored := PermanentUpgradeState.new()
	restored.from_dict(data)
	_check(restored.inspiration == state.inspiration, "存档保留灵感")
	_check(restored.level_of(&"preset_slots") == 1, "存档保留等级")
	_check(restored.element_level(&"dark") == 1, "存档保留元素等级")
	_check(restored.clears == 1, "存档保留通关次数")


func _test_difficulty_unlock() -> void:
	_check(DifficultyTier.COUNT == 3, "3 个难度档")
	_check(DifficultyTier.name_of(0) == "学徒", "第一档学徒")
	_check(is_equal_approx(DifficultyTier.multiplier(2), 1.5), "大师 1.5x")
	_check(not DifficultyTier.is_unlocked(1, 0), "0 次通关只解锁学徒")
	_check(DifficultyTier.is_unlocked(1, 1), "通关一次解锁炼金师")
	_check(not DifficultyTier.is_unlocked(2, 1), "通关一次不解锁大师")
	_check(DifficultyTier.is_unlocked(2, 5), "多次通关解锁大师")
	_check(DifficultyTier.modifiers(2).is_empty(), "自定义修饰接口暂为空")
	var state := PermanentUpgradeState.new()
	state.register_clear()
	_check(state.unlocked_difficulty() == 1, "状态记录通关并解锁难度")
