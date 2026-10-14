extends SceneTree

## 诅咒炼金：配置表、手动选择、随机诅咒、修正聚合与炼金台结算。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _run() -> void:
	# ── 配置表 ──────────────────────────────────────────────────────────
	_check(AlchemyCurses.CURSES.size() >= 8, "诅咒配置至少 8 条")
	_check(AlchemyCurses.has_curse(&"deathmark"), "已知诅咒可查询")
	_check(not AlchemyCurses.has_curse(&"nope"), "未知诅咒返回 false")
	_check(AlchemyCurses.curse_of(&"deathmark").get("power", 0.0) == 1.0, "死印强度 +100%")
	_check(AlchemyCurses.display_name_of(&"blood_pact") == "血契", "诅咒显示名")
	_check(AlchemyCurses.all_curse_ids().size() == AlchemyCurses.CURSES.size(), "诅咒 id 列表完整")
	# 每条诅咒至少有一个收益与一个代价。
	for entry: Dictionary in AlchemyCurses.CURSES:
		var gain: float = float(entry.get("power", 0.0)) + float(entry.get("duration", 0.0))
		var cost: float = float(entry.get("self_damage", 0.0)) + float(entry.get("heat", 0.0)) \
			+ float(entry.get("material_cost", 0.0))
		_check(gain > 0.0, "诅咒 %s 有收益" % entry["id"])
		_check(cost > 0.0 or float(entry.get("duration", 0.0)) < 0.0, "诅咒 %s 有代价" % entry["id"])

	# ── 手动选择 ────────────────────────────────────────────────────────
	var curses: AlchemyCurses = AlchemyCurses.new()
	_check(not curses.is_active(), "初始没有激活诅咒")
	_check(not curses.select(&"nope"), "未知诅咒无法选中")
	_check(curses.select(&"frenzy"), "选中狂乱")
	_check(curses.active_curses() == [&"frenzy"], "激活列表只有选中的那条")
	_check(is_equal_approx(curses.power_bonus(), 0.40), "狂乱强度 +40%")
	_check(is_equal_approx(curses.heat_bonus(), 30.0), "狂乱热量 +30")
	curses.clear_selection()
	_check(not curses.is_active(), "取消后无激活诅咒")

	# ── 随机诅咒 ────────────────────────────────────────────────────────
	var rolled: Array[StringName] = curses.pick_random(3, _seeded(11))
	_check(rolled.size() == 3, "随机抽 3 条诅咒")
	_check(rolled[0] != rolled[1] and rolled[1] != rolled[2] and rolled[0] != rolled[2], "随机诅咒互不相同")
	for id: StringName in rolled:
		_check(AlchemyCurses.has_curse(id), "随机结果都是有效诅咒")
	_check(curses.pick_random(0, _seeded(1)).is_empty(), "抽 0 条返回空")
	_check(curses.pick_random(99, _seeded(1)).size() == AlchemyCurses.CURSES.size(), "抽取数量不超过总数")

	# ── 诅咒词条 → 诅咒条数 ─────────────────────────────────────────────
	var plain: BrewCombo = BrewCombo.new()
	_check(AlchemyCurses.curse_count_of(plain) == 0, "没有诅咒词条时不附带")
	_check(AlchemyCurses.curse_count_of(null) == 0, "空组合不附带")
	var cursed_combo: BrewCombo = BrewCombo.new()
	cursed_combo.traits = [TraitCatalog.create(&"curse", 1)]
	_check(AlchemyCurses.curse_count_of(cursed_combo) == 1, "诅咒 I 附带 1 条")
	cursed_combo.traits = [TraitCatalog.create(&"curse", 5)]
	_check(AlchemyCurses.curse_count_of(cursed_combo) == 3, "诅咒 V 附带 3 条")

	# ── roll_for_combo ─────────────────────────────────────────────────
	var roller: AlchemyCurses = AlchemyCurses.new()
	roller.select(&"chaos")
	var manual: Array[StringName] = roller.roll_for_combo(cursed_combo, _seeded(2))
	_check(manual == [&"chaos"], "手动选择优先于随机")
	roller.clear_selection()
	var random_roll: Array[StringName] = roller.roll_for_combo(cursed_combo, _seeded(2))
	_check(random_roll.size() == 3, "诅咒词条随机附带 3 条")
	_check(roller.active_curses() == random_roll, "随机结果进入激活列表")
	_check(is_equal_approx(roller.power_bonus(), roller.power_bonus()), "随机诅咒强度可累加")

	# ── 组合结算 ────────────────────────────────────────────────────────
	var multi: AlchemyCurses = AlchemyCurses.new()
	multi.select(&"brittle")
	_check(is_equal_approx(multi.power_bonus(), 0.50), "脆化强度 +50%")
	_check(is_equal_approx(multi.duration_bonus(), -0.30), "脆化时长 -30%")
	var tithe: AlchemyCurses = AlchemyCurses.new()
	tithe.select(&"soul_tithe")
	_check(tithe.material_cost() == 1, "魂税额外消耗 1 个材料")
	_check(is_equal_approx(tithe.self_damage(), 0.0), "魂税没有自伤")

	# ── 炼金台接线 ──────────────────────────────────────────────────────
	var base_station: AlchemyStation = AlchemyStation.new()
	root.add_child(base_station)
	base_station.absorb_material(1002, 5)
	base_station.clear_slots()
	base_station.fill_first_free_slot(1002)
	var base_combo: BrewCombo = base_station.brew_from_slots()
	_check(base_combo != null, "基准炼金成功")
	var base_power: float = base_combo.power
	var base_damage: float = base_combo.self_damage

	var cursed_station: AlchemyStation = AlchemyStation.new()
	root.add_child(cursed_station)
	_check(cursed_station.select_curse(&"deathmark"), "炼金台选中死印")
	_check(cursed_station.active_curses() == [&"deathmark"], "炼金台报告激活诅咒")
	cursed_station.absorb_material(1002, 5)
	cursed_station.clear_slots()
	cursed_station.fill_first_free_slot(1002)
	var cursed_result: BrewCombo = cursed_station.brew_from_slots()
	_check(cursed_result != null, "诅咒炼金成功")
	_check(is_equal_approx(cursed_result.power, base_power * 2.0), "死印让强度翻倍")
	_check(cursed_result.self_damage > base_damage, "死印增加每秒自伤")
	_check(cursed_result.overload_heat_bonus >= 0.0, "诅咒热量加成写入组合")

	# 魂税：多消耗一个材料。
	var tithe_station: AlchemyStation = AlchemyStation.new()
	root.add_child(tithe_station)
	tithe_station.select_curse(&"soul_tithe")
	tithe_station.absorb_material(1002, 5)
	tithe_station.clear_slots()
	tithe_station.fill_first_free_slot(1002)
	tithe_station.brew_from_slots()
	_check(tithe_station.bag.count(1002) == 3, "魂税额外消耗 1 个材料（5 - 1 - 1）")

	# 未选诅咒且无诅咒词条时不附带。
	var plain_station: AlchemyStation = AlchemyStation.new()
	root.add_child(plain_station)
	plain_station.absorb_material(1002, 3)
	plain_station.clear_slots()
	plain_station.fill_first_free_slot(1002)
	var plain_result: BrewCombo = plain_station.brew_from_slots()
	_check(is_equal_approx(plain_result.power, base_power), "无诅咒时强度与基准一致")
	_check(plain_station.active_curses().is_empty(), "无诅咒时激活列表为空")

	base_station.free()
	cursed_station.free()
	tithe_station.free()
	plain_station.free()
	print("ALCHEMY CURSES: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
