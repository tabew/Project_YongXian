extends SceneTree

## 武器炼金槽单元测试：临时槽上限与挤出、永久槽、加成聚合、存档往返、炼金台接线。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## 造一个只有效果标签和强度的最小组合。
static func _combo(tag: StringName, power: float) -> BrewCombo:
	var combo: BrewCombo = BrewCombo.new()
	combo.effect_tags = [tag]
	combo.power = power
	combo.base_duration = AlchemyRules.BASE_DURATION
	return combo


## 组合是否只有这一个效果标签。
static func _tagged(combo: BrewCombo, tag: StringName) -> bool:
	return combo != null and combo.effect_tags.size() == 1 and combo.effect_tags[0] == tag


func _run() -> void:
	# ── 默认值 ──────────────────────────────────────────────────────────
	var slots: AlchemyWeaponSlots = AlchemyWeaponSlots.new()
	_check(slots.temporary_limit == 1, "临时槽初始 1 个")
	_check(slots.temporary_count() == 0, "初始没有临时槽内容")
	_check(slots.permanent_count() == 0, "初始没有永久槽")
	_check(slots.has_free_temporary(), "初始有空闲临时槽")
	_check(slots.active_temporary() == null, "没有内容时当前临时组合为空")
	_check(is_equal_approx(slots.permanent_bonus(), 0.0), "没有永久槽时加成为 0")

	# ── 临时槽上限 ──────────────────────────────────────────────────────
	_check(slots.set_temporary_limit(5) == AlchemyWeaponSlots.TEMPORARY_MAX, "临时槽上限封顶 2")
	_check(slots.set_temporary_limit(0) == AlchemyWeaponSlots.TEMPORARY_BASE, "临时槽下限 1")
	_check(slots.set_temporary_limit(2) == 2, "临时槽可扩到 2")

	# ── 装入与挤出 ──────────────────────────────────────────────────────
	_check(slots.install_temporary(null) == null, "空组合不被装入")
	_check(slots.install_temporary(BrewCombo.new()) == null, "无标签组合不被装入")
	_check(slots.install_temporary(_combo(&"fire", 2.0)) == null, "第一个槽不挤出任何东西")
	_check(slots.temporary_count() == 1, "装入一个临时槽")
	_check(_tagged(slots.active_temporary(), &"fire"), "当前临时组合是最近装入的")
	_check(slots.install_temporary(_combo(&"ice", 3.0)) == null, "上限 2 时第二个槽不挤出")
	_check(slots.temporary_count() == 2, "两个临时槽都占满")
	_check(not slots.has_free_temporary(), "占满后没有空闲临时槽")
	var evicted: BrewCombo = slots.install_temporary(_combo(&"poison", 4.0))
	_check(_tagged(evicted, &"fire"), "装入第三个挤出最旧的")
	_check(slots.temporary_count() == 2, "挤出后临时槽数量不超上限")
	_check(_tagged(slots.active_temporary(), &"poison"), "最新装入的组合生效")

	# 缩小上限会丢掉多余的临时槽。
	_check(slots.set_temporary_limit(1) == 1, "临时槽缩回 1")
	_check(slots.temporary_count() == 1, "缩小时丢掉多余的临时槽")
	_check(_tagged(slots.active_temporary(), &"poison"), "保留最近生效的那个")

	# ── 永久槽 ──────────────────────────────────────────────────────────
	_check(not slots.add_permanent(null), "空组合不能开永久槽")
	_check(not slots.add_permanent(BrewCombo.new()), "无标签组合不能开永久槽")
	_check(slots.add_permanent(_combo(&"light", 1.5)), "开出一个永久槽")
	_check(slots.add_permanent(_combo(&"dark", 0.5)), "永久槽可以累加")
	_check(slots.permanent_count() == 2, "两个永久槽")
	_check(is_equal_approx(slots.permanent_bonus(), 2.0), "永久槽加成是各槽强度之和")
	_check(slots.temporary_count() == 1, "开永久槽不动临时槽")
	# 永久槽不受缩小上限影响。
	_check(slots.set_temporary_limit(1) == 1, "再设一次上限")
	_check(slots.permanent_count() == 2, "永久槽不受临时槽上限影响")

	# ── 摘要与清空 ──────────────────────────────────────────────────────
	var rows: Array[Dictionary] = slots.summaries()
	_check(rows.size() == 3, "摘要把临时槽与永久槽都列出来")
	_check(bool(rows[0]["permanent"]) == false and bool(rows[2]["permanent"]), "摘要按临时在前、永久在后")
	slots.clear_temporary()
	_check(slots.temporary_count() == 0 and slots.permanent_count() == 2, "清空只清临时槽")
	slots.clear()
	_check(slots.temporary_count() == 0 and slots.permanent_count() == 0, "clear 清掉全部槽位")

	# ── 存档往返 ────────────────────────────────────────────────────────
	var source: AlchemyWeaponSlots = AlchemyWeaponSlots.new()
	source.set_temporary_limit(2)
	source.install_temporary(_combo(&"fire", 2.5))
	source.add_permanent(_combo(&"soul", 1.25))
	var snapshot: Dictionary = source.to_dict()
	var restored: AlchemyWeaponSlots = AlchemyWeaponSlots.new()
	restored.from_dict(snapshot)
	_check(restored.temporary_limit == 2, "存档往返保留临时槽上限")
	_check(restored.temporary_count() == 1 and restored.permanent_count() == 1, "存档往返保留槽位数量")
	_check(_tagged(restored.active_temporary(), &"fire"), "存档往返保留临时槽标签")
	_check(is_equal_approx(restored.permanent_bonus(), 1.25), "存档往返保留永久槽强度")
	var tampered: AlchemyWeaponSlots = AlchemyWeaponSlots.new()
	tampered.from_dict({"temporary_limit": 99, "temporary": [snapshot["temporary"][0], snapshot["temporary"][0], snapshot["temporary"][0]]})
	_check(tampered.temporary_limit == AlchemyWeaponSlots.TEMPORARY_MAX, "存档越界上限被截断")
	_check(tampered.temporary_count() == AlchemyWeaponSlots.TEMPORARY_MAX, "存档多余临时槽被丢掉")

	# ── 炼金台接线 ──────────────────────────────────────────────────────
	var station: AlchemyStation = AlchemyStation.new()
	root.add_child(station)
	_check(station.weapon_slots != null, "炼金台持有武器炼金槽")
	_check(station.weapon_slots.temporary_limit == 1, "默认 1 个临时槽")
	_check(station.weapon_slot_free(), "默认有空闲临时槽")
	_check(is_equal_approx(station.permanent_slot_bonus(), 0.0), "初始永久槽加成为 0")

	station.add_upgrade(&"weapon_slot_plus", 1)
	_check(station.weapon_slots.temporary_limit == 2, "升级把临时槽扩到 2")
	station.add_upgrade(&"weapon_slot_plus", 5)
	_check(station.weapon_slots.temporary_limit == AlchemyWeaponSlots.TEMPORARY_MAX, "升级不能突破 2 个上限")

	# 炼金会把组合装进临时槽。
	station.absorb_material(1006, 3)
	var brewed: BrewCombo = station.brew_from_slots()
	_check(brewed != null, "素材槽炼出组合")
	_check(station.weapon_slots.temporary_count() == 1, "炼金装入一个临时槽")
	_check(station.weapon_slots.active_temporary().matches(brewed), "临时槽内容就是刚炼出的组合")

	# 战斗中拒绝熔永久槽。
	station.absorb_material(1006, 3)
	station.in_combat = true
	_check(station.alloy_permanent_slot() == null, "战斗中不能熔永久槽")
	_check(station.weapon_slots.permanent_count() == 0, "战斗中永久槽不变")
	station.in_combat = false
	var permanent: BrewCombo = station.alloy_permanent_slot()
	_check(permanent != null, "非战斗可以熔永久槽")
	_check(station.weapon_slots.permanent_count() == 1, "熔出一个永久槽")
	_check(is_equal_approx(station.permanent_slot_bonus(), permanent.power), "永久槽加成写进炼金台")
	# 永久加成叠加在激活组合之上。
	_check(is_equal_approx(station.combo_power(), station.session.combo_power() + permanent.power), "combo_power 含永久槽加成")

	# 过载清空临时槽，永久槽保留。
	station.session.heat.add_heat(AlchemyRules.HEAT_MAX)
	_check(station.weapon_slots.temporary_count() == 0, "过载清空临时槽")
	_check(station.weapon_slots.permanent_count() == 1, "过载不动永久槽")
	station.session.heat.reset()
	station.free()

	print("ALCHEMY WEAPON SLOTS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
