extends SceneTree

## 单一激活炼金组合单元测试：相同叠加、不同替换、替换爆发、持续时间、自伤。

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

func _materials(ids: Array[int]) -> Array[AlchemyMaterial]:
	var result: Array[AlchemyMaterial] = []
	for material_id: int in ids:
		result.append(MaterialCatalog.create(material_id, 1))
	return result

func _run() -> void:
	_test_activate()
	_test_stack_same_combo()
	_test_replace_and_burst()
	_test_duration_and_expiry()
	_test_self_damage()
	_test_rejected()
	_test_overload_ends_combo()
	print("ALCHEMY BREW: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_activate() -> void:
	var session: BrewSession = BrewSession.new(AlchemyRules.POOL_LIMIT_PROTOTYPE)
	var captured: Dictionary = {}
	session.combo_activated.connect(func(combo: BrewCombo) -> void: captured["activated"] = combo)
	var combo: BrewCombo = session.brew(_materials([1002, 1001]))
	_check(combo != null, "首次炼金产出组合")
	_check(captured.has("activated"), "首次炼金触发激活信号")
	_check(session.is_active(), "炼金后组合生效")
	_check(is_equal_approx(combo.base_duration, 14.4), "12 秒 × (1+0.2 持续) = 14.4 秒")
	_check(is_equal_approx(session.duration.total, 14.4), "持续时间写入追踪器")
	_check(session.last_recipe == [1002, 1001], "记录上次配方供短按 E 复用")
	_check(is_equal_approx(session.heat.heat, 20.0), "首次炼金热量 +20")
	_check(session.heat.consecutive_stacks == 0, "首次炼金没有连续叠加计数")

func _test_stack_same_combo() -> void:
	var session: BrewSession = BrewSession.new(AlchemyRules.POOL_LIMIT_PROTOTYPE)
	var captured: Dictionary = {}
	session.combo_stacked.connect(func(_combo: BrewCombo, stacks: int) -> void: captured["stacks"] = stacks)
	session.brew(_materials([1002, 1001]))
	session.tick(1.0, false, true)
	_check(is_equal_approx(session.duration.remaining, 13.4), "倒计时按秒推进")
	var heat_before: float = session.heat.heat
	session.brew(_materials([1002, 1001]))
	_check(captured.get("stacks", -1) == 1, "第二次同组合叠加计数为 1")
	_check(is_equal_approx(session.duration.total, 28.8), "相同组合时间叠加")
	_check(is_equal_approx(session.duration.remaining, 27.8), "叠加后保留已走过的时间")
	_check(is_equal_approx(session.heat.heat - heat_before, 25.0), "连续叠相同组合额外 +5 热量")
	# 不同材料、但最终效果标签一致（火+毒→毒烟），仍算相同组合。
	session.brew(_materials([1029, 1002]))
	_check(captured.get("stacks", -1) == 2, "换材料但效果标签一致仍算叠加")

func _test_replace_and_burst() -> void:
	var session: BrewSession = BrewSession.new(AlchemyRules.POOL_LIMIT_PROTOTYPE)
	var captured: Dictionary = {}
	session.combo_replaced.connect(func(previous: BrewCombo, burst: float, reactions: Array) -> void:
		captured["previous"] = previous
		captured["burst"] = burst
		captured["reactions"] = reactions)
	var first: BrewCombo = session.brew(_materials([1002, 1001]))
	var replaced_before: BrewCombo = session.brew(_materials([1002, 1005]))
	_check(replaced_before != null, "换新组合后仍产出组合")
	_check(captured.has("previous"), "换组合触发替换信号")
	var previous: BrewCombo = captured["previous"]
	_check(previous.signature() == first.signature(), "替换信号带回的是旧组合")
	_check(is_equal_approx(float(captured["burst"]), first.power * 0.5), "旧效果以 50% 强度爆发")
	var reactions: Array = captured["reactions"]
	_check(reactions.size() == 1 and reactions[0]["id"] == &"poison_smoke", "替换爆发带回旧组合的词条反应")
	_check(not session.active_combo.matches(previous), "新组合取代旧组合")
	_check(session.heat.consecutive_stacks == 0, "换新组合会清空连续叠加计数")
	_check(is_equal_approx(session.duration.total, session.active_combo.base_duration), "换组合后时长按新效果重算")

func _test_duration_and_expiry() -> void:
	var session: BrewSession = BrewSession.new(AlchemyRules.POOL_LIMIT_PROTOTYPE)
	var captured: Dictionary = {}
	session.combo_expired.connect(func(combo: BrewCombo) -> void: captured["expired"] = combo)
	session.brew(_materials([1002, 1001]))
	session.tick(5.0, true, false)
	_check(is_equal_approx(session.duration.remaining, 14.4), "非战斗暂停倒计时")
	session.tick(5.0, false, true)
	_check(is_equal_approx(session.duration.remaining, 9.4), "战斗中恢复倒计时")
	session.tick(20.0, false, true)
	_check(captured.has("expired"), "时间走完触发结束信号")
	_check(not session.is_active(), "时间走完后组合失效")
	_check(is_equal_approx(session.duration.remaining, 0.0), "剩余时间归零")

func _test_self_damage() -> void:
	var session: BrewSession = BrewSession.new(AlchemyRules.POOL_LIMIT_PROTOTYPE)
	var captured: Dictionary = {"total": 0.0}
	session.self_damage.connect(func(amount: float) -> void: captured["total"] = float(captured["total"]) + amount)
	# 龙血带活体 IV：每秒自伤 2 点。
	session.brew(_materials([1061]))
	_check(session.active_combo.self_damage > 0.0, "活体词条带来每秒自伤")
	session.tick(2.0, false, true)
	_check(is_equal_approx(float(captured["total"]), floorf(session.active_combo.self_damage * 2.0)), "自伤按时间累计并整点结算")
	var frozen: float = float(captured["total"])
	session.tick(3.0, true, false)
	_check(is_equal_approx(float(captured["total"]), frozen), "暂停时不自伤")

func _test_rejected() -> void:
	var session: BrewSession = BrewSession.new(AlchemyRules.POOL_LIMIT_PROTOTYPE)
	var captured: Dictionary = {}
	session.brew_rejected.connect(func(reason: String) -> void: captured["reason"] = reason)
	_check(session.brew([]) == null, "空素材槽无法炼金")
	_check(captured.get("reason", "") == "素材槽里没有可用词条", "拒绝原因可读")
	_check(session.brew(_materials([9999])) == null, "未知材料无法炼金")
	session.heat.lock_remaining = 1.0
	_check(session.brew(_materials([1002, 1001])) == null, "过热锁定期间禁止炼金")

func _test_overload_ends_combo() -> void:
	var session: BrewSession = BrewSession.new(AlchemyRules.POOL_LIMIT_PROTOTYPE)
	var captured: Dictionary = {}
	session.combo_expired.connect(func(_combo: BrewCombo) -> void: captured["expired"] = true)
	session.brew(_materials([1002, 1001]))
	_check(session.is_active(), "过载前组合生效")
	session.heat.add_heat(AlchemyRules.HEAT_MAX)
	_check(captured.has("expired"), "过载立即结束当前效果")
	_check(not session.is_active(), "过载后组合失效")
	_check(session.weapon_disabled(), "过载后武器失效")
