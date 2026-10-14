extends SceneTree

## 活体武器分裂：分裂资格、分身数量 / 时长 / 伤害比例、击杀累积与炼金台接线。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## 构造只带活体词条的组合，等级 / 层数可控。
func _living_combo(level: int, stacks: int = 1) -> BrewCombo:
	var combo: BrewCombo = BrewCombo.new()
	combo.traits = [TraitCatalog.create(&"living", level, stacks)]
	combo.effect_tags = [&"living"]
	return combo


func _run() -> void:
	# ── 分裂资格：活体 V（split 标志）才可分裂 ──────────────────────────
	_check(not AlchemyLivingSplit.can_split(null), "空组合不能分裂")
	_check(not AlchemyLivingSplit.can_split(BrewCombo.new()), "无词条不能分裂")
	_check(not AlchemyLivingSplit.can_split(_living_combo(4)), "活体 IV 还不能分裂")
	_check(AlchemyLivingSplit.can_split(_living_combo(5)), "活体 V 可以分裂")

	# ── 分身数量 / 时长 / 伤害比例 ──────────────────────────────────────
	_check(AlchemyLivingSplit.split_count(_living_combo(5)) == 1, "单层分裂 1 个分身")
	_check(AlchemyLivingSplit.split_count(_living_combo(5, 3)) == 3, "三层分裂 3 个分身")
	_check(AlchemyLivingSplit.split_count(_living_combo(5, 9)) == AlchemyLivingSplit.MAX_SPLITS, "分身数量有上限")
	_check(AlchemyLivingSplit.split_count(_living_combo(4)) == 0, "不可分裂时数量为 0")
	_check(is_equal_approx(AlchemyLivingSplit.split_duration(_living_combo(5)), 8.0), "V 级分身时长 8 秒")
	_check(is_equal_approx(AlchemyLivingSplit.split_duration(_living_combo(3)), 0.0), "不可分裂时时长为 0")
	_check(is_equal_approx(AlchemyLivingSplit.split_damage_ratio(_living_combo(5)), 0.60), "V 级分身伤害 60%")
	_check(is_equal_approx(AlchemyLivingSplit.split_damage_ratio(_living_combo(2)), 0.0), "不可分裂时伤害为 0")
	_check(is_equal_approx(AlchemyLivingSplit.kill_heal(_living_combo(4)), 3.0), "活体 IV 击杀回血 3")
	_check(is_equal_approx(AlchemyLivingSplit.kill_heal(_living_combo(3)), 0.0), "活体 III 不回血")

	# ── 击杀累积 ────────────────────────────────────────────────────────
	var splitter: AlchemyLivingSplit = AlchemyLivingSplit.new()
	var combo: BrewCombo = _living_combo(5)
	_check(splitter.kills_until_split() == AlchemyLivingSplit.KILLS_PER_SPLIT, "初始还差 3 次击杀")
	_check(splitter.note_kill(combo) == 0, "第 1 次击杀不分裂")
	_check(splitter.note_kill(combo) == 0, "第 2 次击杀不分裂")
	_check(splitter.kills_until_split() == 1, "第 2 次后还差 1 次")
	var spawned: int = splitter.note_kill(combo)
	_check(spawned == 1, "第 3 次击杀触发分裂")
	_check(splitter.kills_until_split() == AlchemyLivingSplit.KILLS_PER_SPLIT, "分裂后计数清零")
	_check(splitter.note_kill(_living_combo(2)) == 0, "不可分裂的组合不累积")
	_check(splitter.kill_progress == 0, "不可分裂时清空进度")
	splitter.reset()
	_check(splitter.kill_progress == 0, "reset 清空进度")

	# 三层叠加时一次分裂出多个分身。
	var heavy: AlchemyLivingSplit = AlchemyLivingSplit.new()
	var heavy_combo: BrewCombo = _living_combo(5, 3)
	heavy.note_kill(heavy_combo)
	heavy.note_kill(heavy_combo)
	_check(heavy.note_kill(heavy_combo) == 3, "三层活体一次分裂 3 个分身")

	# ── 信号 ────────────────────────────────────────────────────────────
	var seen: Array[int] = []
	var emitter: AlchemyLivingSplit = AlchemyLivingSplit.new()
	emitter.split_ready.connect(func(count: int) -> void: seen.append(count))
	var signal_combo: BrewCombo = _living_combo(5, 2)
	emitter.note_kill(signal_combo)
	emitter.note_kill(signal_combo)
	emitter.note_kill(signal_combo)
	_check(seen == [2], "分裂时发出 split_ready 信号")

	# ── 炼金台接线 ──────────────────────────────────────────────────────
	var station: AlchemyStation = AlchemyStation.new()
	root.add_child(station)
	var station_seen: Array[int] = []
	station.split_ready.connect(func(count: int) -> void: station_seen.append(count))
	station.session.active_combo = _living_combo(5)
	_check(station.living_split_count() == 1, "炼金台报告分身数量")
	_check(is_equal_approx(station.living_split_duration(), 8.0), "炼金台报告分身时长")
	_check(is_equal_approx(station.living_split_damage_ratio(), 0.60), "炼金台报告分身伤害比例")
	_check(station.register_kill() == 0, "第 1 次击杀不分裂")
	_check(station.register_kill() == 0, "第 2 次击杀不分裂")
	_check(station.register_kill() == 1, "第 3 次击杀分裂")
	_check(station_seen == [1], "炼金台转发 split_ready")
	station.session.active_combo = _living_combo(3)
	_check(station.living_split_count() == 0, "非活体 V 组合不分裂")
	_check(station.register_kill() == 0, "非活体 V 组合击杀不分裂")

	station.free()
	print("ALCHEMY LIVING SPLIT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
