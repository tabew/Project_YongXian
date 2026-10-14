extends SceneTree

## 目标文档「词条详细数据」逐级数值的回归测试。
## 覆盖：13 元素 + 9 行为 + 8 触发 + 8 修饰 共 38 条词条的每一级数值 / 标志位，
## 以及「持续时间」章节列出的持续 / 稳定 / 挥发 / 活体 / 诅咒修正区间。
## 这些数字直接来自需求文档，改配置表前先确认需求是否真的变了。

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _c(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

func _level(trait_id: StringName, index: int) -> Dictionary:
	var definition: Dictionary = TraitCatalog.definition_of(trait_id)
	var levels: Array = definition.get("levels", [])
	if index >= levels.size():
		return {}
	return levels[index]

## 断言某一级的数值键等于期望值（float 用近似比较，int 用相等比较）。
func _num(trait_id: StringName, index: int, key: String, expect: float) -> void:
	var value: float = float(_level(trait_id, index).get(key, NAN))
	_c(is_equal_approx(value, expect), "%s L%d %s 期望 %s 实际 %s" % [trait_id, index + 1, key, str(expect), str(value)])

func _int(trait_id: StringName, index: int, key: String, expect: int) -> void:
	var value: int = int(_level(trait_id, index).get(key, -999999))
	_c(value == expect, "%s L%d %s 期望 %d 实际 %d" % [trait_id, index + 1, key, expect, value])

func _flag(trait_id: StringName, index: int, key: String, expect: bool) -> void:
	var value: bool = bool(_level(trait_id, index).get(key, not expect))
	_c(value == expect, "%s L%d %s 期望 %s 实际 %s" % [trait_id, index + 1, key, str(expect), str(value)])

## 从 start 级开始逐级断言一串数值；int 走 _int，其余走 _num。
func _series(trait_id: StringName, key: String, values: Array, start: int = 0) -> void:
	for i: int in values.size():
		if values[i] is int:
			_int(trait_id, start + i, key, values[i])
		else:
			_num(trait_id, start + i, key, float(values[i]))

func _run() -> void:
	_test_elements()
	_test_behaviors()
	_test_triggers()
	_test_modifiers()
	_test_duration_modifiers()
	print("ALCHEMY SPEC: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

## 元素词条（13）：火 / 毒 / 冰 / 电 / 酸 / 磁 / 灵魂 / 骨 / 血 / 风 / 沙 / 光 / 暗。
func _test_elements() -> void:
	_series(&"fire", "damage", [3, 5, 8, 12, 18])
	_series(&"fire", "ignite", [0.05, 0.10, 0.15, 0.20, 0.25])
	_series(&"fire", "duration", [2, 2, 3, 4, 5])
	_num(&"fire", 3, "spread", 1.0)
	_num(&"fire", 4, "spread", 2.0)
	_flag(&"fire", 4, "ground", true)

	_series(&"poison", "stacks", [1, 1, 1, 2, 3])
	_series(&"poison", "dps", [2, 3, 4, 6, 8])
	_series(&"poison", "duration", [3, 4, 5, 6, 8])
	_flag(&"poison", 3, "death_spread", true)
	_flag(&"poison", 4, "cloud", true)

	_series(&"ice", "slow", [0.10, 0.15, 0.25, 0.35, 0.50])
	_series(&"ice", "duration", [2, 2.5, 3, 4, 5])
	_series(&"ice", "freeze_chance", [0.05, 0.10, 0.15], 2)
	_series(&"ice", "freeze_duration", [1, 1.5, 2], 2)
	_flag(&"ice", 4, "shatter", true)

	_series(&"electric", "damage", [3, 5, 8, 12, 18])
	_series(&"electric", "shock", [0.05, 0.10, 0.15, 0.20, 0.25])
	_series(&"electric", "duration", [2, 2, 3, 4, 5])
	_series(&"electric", "chain", [1, 2, 3], 2)
	_flag(&"electric", 4, "wet_guarantee", true)

	_series(&"acid", "sunder", [0.10, 0.15, 0.25, 0.35, 0.50])
	_series(&"acid", "duration", [3, 4, 5, 6, 8])
	_flag(&"acid", 2, "corrode_weapon", true)
	_int(&"acid", 3, "pool", 1)
	_int(&"acid", 4, "pool", 2)
	_int(&"acid", 4, "pool_stacks", 2)

	_series(&"magnet", "pull", [1, 2, 3, 4, 5])
	_num(&"magnet", 1, "drag", 1.0)
	_num(&"magnet", 3, "drag", 2.0)
	_num(&"magnet", 3, "magnetize", 3.0)
	_num(&"magnet", 4, "drag", 3.0)
	_num(&"magnet", 4, "magnetize", 5.0)
	_flag(&"magnet", 4, "metal_collide", true)

	_series(&"soul", "spawn_chance", [0.05, 0.10, 0.15, 0.20, 0.25])
	_series(&"soul", "count", [1, 1, 1, 2, 3])
	_flag(&"soul", 2, "homing", true)
	_flag(&"soul", 4, "explode", true)

	_series(&"bone", "bounce_chance", [0.05, 0.10, 0.15, 0.20, 0.25])
	_series(&"bone", "shards", [1, 1, 2, 3, 4])
	_flag(&"bone", 2, "pierce", true)
	_flag(&"bone", 3, "spikes", true)
	_flag(&"bone", 4, "skeleton", true)

	_series(&"blood", "kill_heal", [1, 2, 3, 4, 6])
	_series(&"blood", "crit_heal", [1, 2, 3], 2)
	_num(&"blood", 4, "shield_cap", 20.0)
	_num(&"blood", 4, "shield_duration", 10.0)

	_series(&"wind", "knockback", [0.5, 1, 1.5, 2, 3])
	_series(&"wind", "attack_speed", [0.05, 0.10, 0.15], 2)
	_flag(&"wind", 4, "dust_storm", true)

	_series(&"sand", "blind", [0.05, 0.10, 0.15, 0.20, 0.25])
	_series(&"sand", "duration", [1, 1.5, 2, 3, 4])
	_num(&"sand", 3, "radius", 1.0)
	_num(&"sand", 4, "radius", 2.0)

	_series(&"light", "vs_dark", [0.10, 0.20, 0.30, 0.40, 0.60])
	_series(&"light", "blind_duration", [1, 2, 3], 2)
	_series(&"dark", "vs_light", [0.10, 0.20, 0.30, 0.40, 0.60])
	_series(&"dark", "lifesteal", [0.05, 0.10, 0.15], 2)

## 行为词条（9）：爆炸 / 连锁 / 回旋 / 穿透 / 弹射 / 扩散 / 持续 / 召唤 / 变形。
func _test_behaviors() -> void:
	_series(&"explode", "chance", [0.10, 0.15, 0.20, 0.25, 0.30])
	_series(&"explode", "radius", [1, 1.5, 2, 2.5, 3])
	_series(&"explode", "damage", [0.50, 0.60, 0.70, 0.80, 1.00])
	_flag(&"explode", 4, "chain", true)

	_series(&"chain", "chance", [0.10, 0.15, 0.20, 0.25, 0.30])
	_series(&"chain", "targets", [1, 1, 2, 3, 4])
	_series(&"chain", "damage", [0.50, 0.60, 0.70, 0.80, 1.00])
	_flag(&"chain", 4, "rebound", true)

	_series(&"whirl", "chance", [0.20, 0.30, 0.40, 0.50, 0.60])
	_series(&"whirl", "damage", [0.60, 0.80, 1.00], 2)
	_flag(&"whirl", 4, "double", true)

	_series(&"pierce", "pierce", [1, 1, 2, 3, -1])
	_series(&"pierce", "falloff", [-0.30, -0.20, -0.15, -0.10, -0.05])

	_series(&"bounce", "bounces", [1, 1, 2, 3, 4])
	_series(&"bounce", "damage", [0.50, 0.60, 0.70, 0.80, 1.00])
	_flag(&"bounce", 4, "wall_bounce", true)

	_series(&"spread", "radius", [1, 1.5, 2, 2.5, 3])
	_flag(&"spread", 4, "through_walls", true)

	_series(&"duration", "duration", [0.20, 0.30, 0.45, 0.60, 0.80])
	_flag(&"duration", 4, "refresh", true)

	_series(&"summon", "chance", [0.05, 0.10, 0.15, 0.20, 0.25])
	_series(&"summon", "count", [1, 1, 1, 2, 3])
	_series(&"summon", "duration", [3, 5, 5, 8, 12])
	_flag(&"summon", 4, "explode", true)

	_series(&"transform", "radius", [0.10, 0.20, 0.30, 0.40, 0.50])
	_flag(&"transform", 2, "form_switch", true)
	_flag(&"transform", 3, "element_infuse", true)
	_flag(&"transform", 4, "free_switch", true)

## 触发词条（8）：命中 / 暴击 / 击杀 / 格挡 / 冲刺 / 背刺 / 蓄力 / 连击。
func _test_triggers() -> void:
	_series(&"on_hit", "bonus", [0.0, 0.10, 0.20, 0.30, 0.40])
	_series(&"on_crit", "bonus", [0.0, 0.10, 0.20, 0.30, 0.40])
	_series(&"on_kill", "bonus", [0.0, 0.10, 0.20, 0.30, 0.40])
	_series(&"on_block", "bonus", [0.0, 0.10, 0.20, 0.30, 0.40])
	_series(&"on_dash", "bonus", [0.0, 0.10, 0.20, 0.30, 0.40])
	_series(&"backstab", "bonus", [0.0, 0.20, 0.40, 0.60, 1.00])
	_series(&"charge", "bonus", [0.0, 0.10, 0.20, 0.30, 0.50])
	_series(&"combo", "hits", [3, 4, 5, 6, 8])

## 修饰词条（8）：稳定 / 挥发 / 活体 / 诅咒 / 锐利 / 沉重 / 易碎 / 过载。
func _test_modifiers() -> void:
	_series(&"stability", "side_effect", [-0.20, -0.35, -0.50, -0.70, -1.00])
	_series(&"stability", "duration", [0.10, 0.15, 0.20, 0.30, 0.40])
	_flag(&"stability", 4, "immune", true)

	_series(&"volatile", "duration", [-0.20, -0.25, -0.30, -0.35, -0.40])
	_series(&"volatile", "power", [0.20, 0.35, 0.50, 0.70, 1.00])

	_series(&"living", "duration", [0.50, 0.75, 1.00, 1.50, 2.00])
	_series(&"living", "self_damage", [1, 1, 2, 2, 3])
	_flag(&"living", 3, "kill_heal", true)
	_flag(&"living", 4, "split", true)

	_series(&"curse", "power", [0.30, 0.50, 0.80, 1.20, 2.00])
	_series(&"curse", "duration", [0.30, 0.50, 0.80, 1.00, 1.20])
	_series(&"curse", "curses", [1, 1, 2, 2, 3])
	_flag(&"curse", 4, "permanent", true)

	_series(&"sharp", "crit_chance", [0.05, 0.10, 0.15, 0.20, 0.30])
	_series(&"sharp", "crit_damage", [0.10, 0.20, 0.40], 2)

	_series(&"heavy", "knockback", [0.20, 0.35, 0.50, 0.70, 1.00])
	_series(&"heavy", "attack_speed", [-0.05, -0.05, -0.10, -0.10, -0.15])
	_series(&"heavy", "radius", [0.10, 0.20, 0.30], 2)
	_flag(&"heavy", 4, "earthquake", true)

	_series(&"fragile", "damage", [0.20, 0.35, 0.50, 0.70, 1.00])
	_series(&"fragile", "self_damage", [1, 1, 2, 2, 3])
	_flag(&"fragile", 3, "shatter_bounce", true)
	_flag(&"fragile", 4, "reassemble", true)

	_series(&"overload", "attack_speed", [0.10, 0.20, 0.30, 0.40, 0.60])
	_series(&"overload", "heat", [5, 5, 10, 10, 15])
	_flag(&"overload", 4, "break_heat_cap", true)

## 「持续时间」章节：持续 +20%~+80%、稳定 +10%~+40%、挥发 -20%~-40%、活体 +50%~+200%、诅咒 +30%~+120%。
func _test_duration_modifiers() -> void:
	_c(is_equal_approx(float(_level(&"duration", 0).get("duration", 0.0)), 0.20), "持续 I 级 +20%")
	_c(is_equal_approx(float(_level(&"duration", 4).get("duration", 0.0)), 0.80), "持续 V 级 +80%")
	_c(is_equal_approx(float(_level(&"stability", 0).get("duration", 0.0)), 0.10), "稳定 I 级 +10%")
	_c(is_equal_approx(float(_level(&"stability", 4).get("duration", 0.0)), 0.40), "稳定 V 级 +40%")
	_c(is_equal_approx(float(_level(&"volatile", 0).get("duration", 0.0)), -0.20), "挥发 I 级 -20%")
	_c(is_equal_approx(float(_level(&"volatile", 4).get("duration", 0.0)), -0.40), "挥发 V 级 -40%")
	_c(is_equal_approx(float(_level(&"living", 0).get("duration", 0.0)), 0.50), "活体 I 级 +50%")
	_c(is_equal_approx(float(_level(&"living", 4).get("duration", 0.0)), 2.00), "活体 V 级 +200%")
	_c(is_equal_approx(float(_level(&"curse", 0).get("duration", 0.0)), 0.30), "诅咒 I 级 +30%")
	_c(is_equal_approx(float(_level(&"curse", 4).get("duration", 0.0)), 1.20), "诅咒 V 级 +120%")
