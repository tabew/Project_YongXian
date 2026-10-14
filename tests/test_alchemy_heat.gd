extends SceneTree

## 热量系统单元测试：积累、连续叠加、打断、冷却、过载惩罚、过热分级。

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
	_test_gain()
	_test_cooldown()
	_test_overload()
	_test_warning_levels()
	_test_formula()
	print("ALCHEMY HEAT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_gain() -> void:
	var heat: HeatSystem = HeatSystem.new()
	_check(is_equal_approx(heat.heat, 0.0), "初始热量为 0")
	_check(heat.can_brew(), "初始可以炼金")
	_check(is_equal_approx(heat.add_brew(0.0, 1.0), 20.0), "首次炼金热量 +20")
	heat.note_same_combo()
	_check(is_equal_approx(heat.add_brew(0.0, 1.0), 25.0), "连续叠相同组合 +25")
	heat.note_same_combo()
	_check(is_equal_approx(heat.add_brew(0.0, 1.0), 30.0), "再叠一次 +30，不设上限")
	_check(is_equal_approx(heat.heat, 75.0), "热量累计正确")
	heat.reset_streak()
	_check(is_equal_approx(heat.add_brew(0.0, 1.0), 20.0), "换新组合后回到 +20")
	_check(is_equal_approx(heat.add_interrupt(), 10.0), "受击打断 +10")
	_check(heat.heat <= AlchemyRules.HEAT_MAX, "热量不超过上限")

func _test_cooldown() -> void:
	var heat: HeatSystem = HeatSystem.new()
	heat.heat = 60.0
	heat.tick(1.0, false, 0)
	_check(is_equal_approx(heat.heat, 60.0 - AlchemyRules.HEAT_COOLDOWN_IDLE), "非战斗快速冷却 12/秒")
	heat.heat = 60.0
	heat.tick(1.0, true, 0)
	_check(is_equal_approx(heat.heat, 60.0 - AlchemyRules.HEAT_COOLDOWN_COMBAT), "战斗中缓慢冷却 3/秒")
	heat.heat = 60.0
	heat.tick(1.0, true, 1)
	_check(is_equal_approx(heat.heat, 60.0 - AlchemyRules.HEAT_COOLDOWN_COMBAT - AlchemyRules.HEAT_COOLDOWN_KILL_BONUS), "击杀加速冷却")
	heat.heat = 5.0
	heat.tick(100.0, false, 0)
	_check(is_equal_approx(heat.heat, 0.0), "冷却不会低于 0")

func _test_overload() -> void:
	var heat: HeatSystem = HeatSystem.new()
	var captured: Dictionary = {}
	heat.overloaded.connect(func(report: Dictionary) -> void: captured["report"] = report)
	heat.add_heat(AlchemyRules.HEAT_MAX)
	_check(captured.has("report"), "热量满 100 触发过载")
	var report: Dictionary = captured["report"]
	_check(is_equal_approx(float(report["weapon_disable"]), 8.0), "过载武器失效 8 秒")
	_check(is_equal_approx(float(report["lockout"]), 3.0), "过载后 3 秒不能炼金")
	_check(is_equal_approx(float(report["blast_damage"]), 30.0), "过载爆炸 30 点伤害")
	_check(is_equal_approx(float(report["self_damage"]), 15.0), "过载自伤 15")
	_check(is_equal_approx(float(report["material_loss_ratio"]), 0.5), "过载随机损失一半材料")
	_check(heat.is_locked() and not heat.can_brew(), "过载期间不能炼金")
	_check(heat.is_weapon_disabled(), "过载期间武器失效")
	_check(heat.overload_count == 1, "过载计数 +1")
	_check(is_equal_approx(heat.heat, 0.0), "过载后热量清零")
	heat.tick(3.0, true, 0)
	_check(not heat.is_locked(), "3 秒后解除炼金锁定")
	_check(heat.is_weapon_disabled(), "8 秒内武器仍失效")
	_check(heat.can_brew(), "解除锁定后可以再炼金")
	heat.tick(5.0, true, 0)
	_check(not heat.is_weapon_disabled(), "8 秒后武器恢复")

func _test_warning_levels() -> void:
	var heat: HeatSystem = HeatSystem.new()
	_check(heat.warning_level() == 0, "0% 无警告")
	heat.add_heat(50.0)
	_check(heat.warning_level() == 1, "50% 黄色警告")
	heat.add_heat(25.0)
	_check(heat.warning_level() == 2, "75% 橙色警告")
	heat.add_heat(15.0)
	_check(heat.warning_level() == 3, "90% 红色警告")

func _test_formula() -> void:
	_check(is_equal_approx(AlchemyRules.heat_gain(0, 0.0, 1.0), 20.0), "公式：20 + 0×5 + 0×1")
	_check(is_equal_approx(AlchemyRules.heat_gain(3, 0.0, 1.0), 35.0), "公式：20 + 3×5")
	_check(is_equal_approx(AlchemyRules.heat_gain(0, 10.0, 2.0), 40.0), "公式：20 + 过载加成 10 × 诅咒 2")
	_check(is_equal_approx(AlchemyRules.heat_gain(2, 5.0, 1.5), 37.5), "公式：20 + 10 + 5×1.5")
