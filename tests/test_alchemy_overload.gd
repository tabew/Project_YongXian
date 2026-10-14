extends SceneTree

## 过载惩罚：爆炸范围伤害、自伤、武器失效、炼金锁定、随机材料损失一半。

var _checks: int = 0
var _failures: int = 0


class StubMonster:
	extends Node2D

	var taken: int = 0

	func take_damage(amount: int) -> void:
		taken += amount


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var player: PlayerCharacter = (load("res://scenes/game/player.tscn") as PackedScene).instantiate() as PlayerCharacter
	player.max_health = 100
	root.add_child(player)
	var station: AlchemyStation = player.alchemy_station
	_check(station != null, "主角自带随身炼金台")

	# 近处敌人（20px < 3 格 = 48px）吃满爆炸伤害，远处敌人不受影响。
	var near: StubMonster = StubMonster.new()
	near.global_position = player.global_position + Vector2(20.0, 0.0)
	near.add_to_group("monsters")
	root.add_child(near)
	var far: StubMonster = StubMonster.new()
	far.global_position = player.global_position + Vector2(200.0, 0.0)
	far.add_to_group("monsters")
	root.add_child(far)

	# 只放一种材料，让「随机损失一半」的结果可断言。
	station.absorb_material(1002, 4)
	_check(station.bag.count(1002) == 4, "过载前有 4 个硝石")

	# GDScript 的 lambda 按值捕获局部变量，用数组承载才能拿到回调里的 report。
	var captured_reports: Array[Dictionary] = []
	station.overloaded.connect(func(captured: Dictionary) -> void: captured_reports.append(captured))
	station.session.heat.add_heat(AlchemyRules.HEAT_MAX)

	_check(not captured_reports.is_empty(), "过载发出 report")
	var report: Dictionary = captured_reports[0] if not captured_reports.is_empty() else {}
	_check(report.has("blast_damage"), "过载发出爆炸参数")
	_check(near.taken == int(AlchemyRules.OVERLOAD_BLAST_DAMAGE), "范围内敌人吃 30 点爆炸伤害")
	_check(far.taken == 0, "范围外敌人不受影响")
	_check(player.health == 100 - int(AlchemyRules.OVERLOAD_SELF_DAMAGE), "过载自伤 15")
	_check(player.weapon_controller.is_disabled(), "过载使武器失效")
	_check(is_equal_approx(player.weapon_controller.disabled_remaining, AlchemyRules.OVERLOAD_WEAPON_DISABLE),
		"武器失效 8 秒")
	_check(not station.session.heat.can_brew(), "过载后 3 秒内不能炼金")
	_check(station.active_combo() == null, "过载立即结束当前效果")
	_check(station.bag.count(1002) == 2, "随机一种材料损失一半")
	_check(report.has("material_loss"), "report 带上材料损失明细")
	_check(int((report.get("material_loss", {}) as Dictionary).get("lost", 0)) == 2, "损失数量记入 report")

	# 冷却结束后恢复：3 秒锁定与 8 秒武器失效。
	station.tick(AlchemyRules.OVERLOAD_LOCKOUT + 0.1)
	_check(station.session.heat.can_brew(), "锁定结束后可以再炼金")
	_check(station.is_weapon_disabled(), "3 秒时武器仍然失效")
	station.tick(AlchemyRules.OVERLOAD_WEAPON_DISABLE)
	_check(not station.is_weapon_disabled(), "8 秒后武器恢复")

	player.free()
	print("ALCHEMY OVERLOAD: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
