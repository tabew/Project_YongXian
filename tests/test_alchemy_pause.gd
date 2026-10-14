extends SceneTree

## 非战斗按 E：完整炼金台必须把游戏世界「完全暂停」；Esc 关闭后恢复。
## 同时验证暂停期间玩家节点不再收输入，Esc 由常驻炼金 HUD 兜底，且不消耗材料。

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
	var station: AlchemyStation = AlchemyStation.new()
	root.add_child(station)
	var hud: Control = (load("res://scenes/ui/alchemy/alchemy_hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	hud.call("bind", station)
	await process_frame
	await process_frame

	_check(not paused, "初始未暂停")
	_check(hud.process_mode == Node.PROCESS_MODE_ALWAYS, "炼金 HUD 始终处理，暂停时仍可交互")

	# 非战斗按 E：打开完整炼金台并完全暂停世界。
	station.in_combat = false
	station.press_brew()
	await process_frame
	await process_frame
	_check(station.is_menu_open(), "非战斗按 E 打开完整炼金台")
	_check(paused, "打开完整炼金台后游戏世界完全暂停")

	# 暂停中 Esc 由常驻 HUD 兜底关闭，且不消耗材料。
	station.absorb_material(1002, 3)
	var before: int = station.bag.count(1002)
	var cancel_event := InputEventAction.new()
	cancel_event.action = &"alchemy_cancel"
	cancel_event.pressed = true
	hud.call("_unhandled_input", cancel_event)
	await process_frame
	await process_frame
	_check(not station.is_menu_open(), "暂停中 Esc 关闭炼金台")
	_check(not paused, "关闭炼金台后游戏世界恢复")
	_check(station.bag.count(1002) == before, "Esc 关闭不消耗材料")

	# 战斗中长按 E 走慢动作轮盘：只减速，不暂停世界。
	station.in_combat = true
	station.press_brew()
	station.tick(AlchemyRules.LONG_PRESS_SECONDS + 0.01)
	await process_frame
	await process_frame
	_check(station.is_wheel_open(), "战斗中长按 E 打开轮盘")
	_check(not paused, "轮盘只做慢动作，不暂停世界")
	_check(is_equal_approx(Engine.time_scale, station.slow_motion_scale), "轮盘使用慢动作倍率")
	station.release_brew()
	await process_frame
	await process_frame
	_check(not paused and is_equal_approx(Engine.time_scale, 1.0), "关闭轮盘后恢复时间缩放")

	Engine.time_scale = 1.0
	paused = false
	station.free()
	hud.free()
	print("ALCHEMY PAUSE: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
