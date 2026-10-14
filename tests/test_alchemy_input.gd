extends SceneTree

## 按 E 状态机单元测试：非战斗菜单、短按复用、长按轮盘、受击打断、Esc 关闭。

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
	_test_menu()
	_test_short_press()
	_test_short_press_stun()
	_test_long_press_wheel()
	_test_interrupt()
	_test_close()
	_test_guards()
	_test_phase_signal()
	print("ALCHEMY INPUT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_menu() -> void:
	var input: AlchemyInputState = AlchemyInputState.new()
	var log: Array[String] = []
	input.menu_opened.connect(func() -> void: log.append("menu_opened"))
	input.menu_closed.connect(func() -> void: log.append("menu_closed"))
	_check(input.phase == AlchemyInputState.Phase.IDLE, "初始为 IDLE")
	_check(not input.is_slow_motion(), "IDLE 不是慢动作")
	input.press()
	_check(input.phase == AlchemyInputState.Phase.MENU, "非战斗按 E 打开完整炼金台")
	_check(input.is_menu_open(), "菜单已打开")
	_check(log.has("menu_opened"), "触发 menu_opened")
	_check(input.close(), "Esc 关闭菜单")
	_check(input.phase == AlchemyInputState.Phase.IDLE, "关闭后回到 IDLE")
	_check(log.has("menu_closed"), "触发 menu_closed")

func _test_short_press() -> void:
	var input: AlchemyInputState = AlchemyInputState.new()
	input.in_combat = true
	var log: Array[String] = []
	input.recipe_repeated.connect(func() -> void: log.append("repeat"))
	input.wheel_opened.connect(func() -> void: log.append("wheel"))
	input.press()
	_check(input.phase == AlchemyInputState.Phase.CHARGING, "战斗中按 E 进入蓄力")
	input.tick(0.1)
	_check(input.phase == AlchemyInputState.Phase.CHARGING, "未到长按阈值仍是蓄力")
	_check(not input.is_slow_motion(), "蓄力不慢动作")
	input.release()
	_check(log.has("repeat"), "短按重复上次配方")
	_check(not log.has("wheel"), "短按不打开轮盘")
	_check(input.phase == AlchemyInputState.Phase.IDLE, "短按后回到 IDLE")


## 短按 E 的动作硬直；遗物「快速之手」把 stun_enabled 关掉后不再有硬直。
func _test_short_press_stun() -> void:
	var input: AlchemyInputState = AlchemyInputState.new()
	input.in_combat = true
	input.press()
	input.tick(0.1)
	input.release()
	_check(input.stun_remaining > 0.0, "短按后进入动作硬直")
	input.press()
	_check(input.phase == AlchemyInputState.Phase.IDLE, "硬直期间再按 E 不进入蓄力")
	input.tick(AlchemyRules.SHORT_PRESS_STUN + 0.01)
	_check(is_equal_approx(input.stun_remaining, 0.0), "硬直随时间结束")
	input.press()
	_check(input.phase == AlchemyInputState.Phase.CHARGING, "硬直结束后恢复蓄力")
	input.release()
	# 快速之手：硬直直接不产生。
	var swift: AlchemyInputState = AlchemyInputState.new()
	swift.in_combat = true
	swift.stun_enabled = false
	swift.press()
	swift.tick(0.1)
	swift.release()
	_check(is_equal_approx(swift.stun_remaining, 0.0), "快速之手让短按没有硬直")
	swift.press()
	_check(swift.phase == AlchemyInputState.Phase.CHARGING, "无硬直时可以立刻再蓄力")
	swift.release()

func _test_long_press_wheel() -> void:
	var input: AlchemyInputState = AlchemyInputState.new()
	input.in_combat = true
	var log: Array[String] = []
	input.wheel_opened.connect(func() -> void: log.append("wheel_opened"))
	input.wheel_closed.connect(func() -> void: log.append("wheel_closed"))
	input.press()
	input.tick(AlchemyRules.LONG_PRESS_SECONDS + 0.01)
	_check(input.phase == AlchemyInputState.Phase.WHEEL, "长按进入慢动作轮盘")
	_check(input.is_wheel_open(), "轮盘已打开")
	_check(input.is_slow_motion(), "轮盘使用慢动作")
	_check(log.has("wheel_opened"), "触发 wheel_opened")
	input.release()
	_check(input.phase == AlchemyInputState.Phase.IDLE, "松开轮盘回到 IDLE")
	_check(log.has("wheel_closed"), "触发 wheel_closed")

func _test_interrupt() -> void:
	var wheel: AlchemyInputState = AlchemyInputState.new()
	wheel.in_combat = true
	var log: Array[String] = []
	wheel.interrupted.connect(func() -> void: log.append("interrupted"))
	wheel.wheel_closed.connect(func() -> void: log.append("wheel_closed"))
	wheel.press()
	wheel.tick(AlchemyRules.LONG_PRESS_SECONDS + 0.01)
	_check(wheel.interrupt(), "受击打断生效")
	_check(wheel.phase == AlchemyInputState.Phase.COOLDOWN, "打断后进入冷却")
	_check(log.has("interrupted"), "触发 interrupted")
	_check(log.has("wheel_closed"), "打断会关闭轮盘")
	_check(is_equal_approx(wheel.cooldown_remaining, AlchemyRules.INTERRUPT_COOLDOWN), "打断冷却 1 秒")
	wheel.tick(0.5)
	_check(wheel.phase == AlchemyInputState.Phase.COOLDOWN, "冷却中仍是 COOLDOWN")
	wheel.tick(0.6)
	_check(wheel.phase == AlchemyInputState.Phase.IDLE, "冷却结束回到 IDLE")

	var charging: AlchemyInputState = AlchemyInputState.new()
	charging.in_combat = true
	charging.press()
	_check(charging.interrupt(), "蓄力中被打断")
	_check(charging.phase == AlchemyInputState.Phase.COOLDOWN, "蓄力打断也进冷却")

	var idle: AlchemyInputState = AlchemyInputState.new()
	_check(not idle.interrupt(), "IDLE 无可打断")

	var menu: AlchemyInputState = AlchemyInputState.new()
	menu.press()
	_check(not menu.interrupt(), "菜单不受受击打断")

func _test_close() -> void:
	var charging: AlchemyInputState = AlchemyInputState.new()
	charging.in_combat = true
	var log: Array[String] = []
	charging.recipe_repeated.connect(func() -> void: log.append("repeat"))
	charging.press()
	_check(charging.close(), "Esc 取消蓄力")
	_check(charging.phase == AlchemyInputState.Phase.IDLE, "取消蓄力回到 IDLE")
	_check(not log.has("repeat"), "取消蓄力不重复配方")
	var idle: AlchemyInputState = AlchemyInputState.new()
	_check(not idle.close(), "IDLE 无可关闭")

func _test_guards() -> void:
	var cool: AlchemyInputState = AlchemyInputState.new()
	cool.in_combat = true
	cool.press()
	cool.interrupt()
	cool.press()
	_check(cool.phase == AlchemyInputState.Phase.COOLDOWN, "冷却中按 E 被忽略")
	var menu: AlchemyInputState = AlchemyInputState.new()
	menu.press()
	menu.press()
	_check(menu.is_menu_open(), "菜单打开时按 E 被忽略")

func _test_phase_signal() -> void:
	var input: AlchemyInputState = AlchemyInputState.new()
	input.in_combat = true
	var phases: Array[int] = []
	input.phase_changed.connect(func(value: int) -> void: phases.append(value))
	input.press()
	input.tick(AlchemyRules.LONG_PRESS_SECONDS + 0.01)
	input.release()
	_check(phases == [AlchemyInputState.Phase.CHARGING, AlchemyInputState.Phase.WHEEL, AlchemyInputState.Phase.IDLE], "phase_changed 依次上报")
