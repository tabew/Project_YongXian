extends SceneTree

## 快速预设：格数上限、存取去重、需求与可用性判定、炼金台复原与失败反馈。

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
	_test_capacity()
	_test_store()
	_test_requirements()
	_test_station_apply()
	print("ALCHEMY PRESETS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_capacity() -> void:
	var presets: BrewPresets = BrewPresets.new()
	_check(presets.preset_count() == 1, "基础 1 格快速预设")
	presets.set_slot_count(4)
	_check(presets.preset_count() == 4, "升级到 4 格")
	presets.set_slot_count(99)
	_check(presets.preset_count() == BrewPresets.MAX_SLOT_COUNT, "格数封顶 4")
	presets.set_slot_count(2)
	_check(presets.preset_count() == 2, "缩容到 2 格")
	_check(BrewPresets.new(0).preset_count() == 0, "可以 0 格")


func _test_store() -> void:
	var presets: BrewPresets = BrewPresets.new(3)
	var ids: Array[int] = [1002, 1001, 1002]
	_check(presets.store(0, ids), "存入第 0 格")
	_check(presets.preset_at(0) == ([1002, 1001] as Array[int]), "去重保序")
	_check(not presets.is_empty(0), "第 0 格非空")
	_check(presets.is_empty(1), "第 1 格为空")
	_check(not presets.store(7, ids), "越界写入失败")
	var many: Array[int] = [1, 2, 3, 4, 5, 6]
	presets.store(1, many)
	_check(presets.preset_at(1).size() == BrewPresets.MAX_MATERIALS_PER_PRESET, "单个预设最多 4 种材料")
	_check(presets.first_empty_index() == 2, "第一个空位是 2")
	_check(presets.clear(0), "清空第 0 格")
	_check(presets.is_empty(0), "第 0 格已空")
	_check(not presets.clear(0), "重复清空返回 false")
	presets.clear_all()
	_check(presets.first_empty_index() == 0, "全清后第一个空位是 0")


func _test_requirements() -> void:
	var presets: BrewPresets = BrewPresets.new(2)
	presets.store(0, [1002, 1002, 1001] as Array[int])
	var need: Dictionary = presets.requirements(0)
	_check(int(need.get(1002, 0)) == 1, "去重后硝石只需 1")
	_check(int(need.get(1001, 0)) == 1, "毒菇只需 1")
	_check(presets.can_apply(0, {1002: 1, 1001: 1}), "材料齐备可应用")
	_check(not presets.can_apply(0, {1002: 1}), "缺毒菇不可应用")
	_check(not presets.can_apply(0, {}), "空背包不可应用")
	_check(not presets.can_apply(1, {1002: 5, 1001: 5}), "空预设不可应用")


func _test_station_apply() -> void:
	var station: AlchemyStation = AlchemyStation.new()
	station.preset_slots = 2
	station.setup()
	var rejected: Array[String] = []
	station.brew_rejected.connect(func(reason: String) -> void: rejected.append(reason))
	var preset_signals: Array[int] = [0]
	station.presets_changed.connect(func() -> void: preset_signals[0] += 1)

	station.absorb_material(1002, 3)
	station.absorb_material(1001, 3)
	station.clear_slots()
	station.fill_first_free_slot(1002)
	station.fill_first_free_slot(1001)
	_check(station.save_preset(0), "存下当前布局")
	_check(station.presets.preset_at(0) == ([1002, 1001] as Array[int]), "预设内容正确")
	_check(preset_signals[0] >= 1, "存预设发出 presets_changed")
	station.clear_slots()
	_check(station.slots.is_empty(), "素材槽已清空")
	_check(station.preset_ready(0), "预设材料充足")
	_check(station.apply_preset(0), "应用预设成功")
	_check(station.slots.material_ids() == ([1002, 1001] as Array[int]), "素材槽按预设复原")

	# 空预设：拒绝且不改动素材槽。
	rejected.clear()
	_check(not station.apply_preset(1), "空预设应用失败")
	_check(rejected.size() == 1 and rejected[0] == "预设是空的", "空预设给出提示")
	_check(station.slots.material_ids() == ([1002, 1001] as Array[int]), "失败时素材槽不变")

	# 材料不足：拒绝且不改动素材槽。
	station.presets.store(1, [1061] as Array[int])
	rejected.clear()
	_check(not station.preset_ready(1), "缺龙血时预设不可用")
	_check(not station.apply_preset(1), "材料不足应用失败")
	_check(rejected.size() == 1 and rejected[0] == "预设材料不足", "材料不足给出提示")
	_check(station.slots.material_ids() == ([1002, 1001] as Array[int]), "失败时素材槽仍不变")

	_check(station.clear_preset(1), "清空预设 1")
	_check(station.presets.is_empty(1), "预设 1 已空")
	station.free()
