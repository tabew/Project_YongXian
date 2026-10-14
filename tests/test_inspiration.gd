extends SceneTree

## 灵感系统单元测试：掉落表、留存、贤者之石转化、结算公式、光点表现参数。

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
	_test_drop_table()
	_test_roll()
	_test_conversion()
	_test_retention_and_difficulty()
	_test_codex_bonus()
	_test_settlement()
	_test_run_ledger()
	_test_drop_visuals()
	print("INSPIRATION: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_drop_table() -> void:
	_check(InspirationRules.COUNT == 10, "10 种灵感来源")
	_check(is_equal_approx(InspirationRules.chance_of(InspirationRules.Source.NORMAL), 0.15), "小怪 15%")
	_check(InspirationRules.amount_range(InspirationRules.Source.NORMAL) == Vector2i(1, 3), "小怪掉 1~3")
	_check(is_equal_approx(InspirationRules.chance_of(InspirationRules.Source.ELITE), 0.80), "精英 80%")
	_check(InspirationRules.amount_range(InspirationRules.Source.ELITE) == Vector2i(15, 30), "精英掉 15~30")
	_check(is_equal_approx(InspirationRules.chance_of(InspirationRules.Source.REGION_BOSS), 1.0), "区域 Boss 100%")
	_check(InspirationRules.amount_range(InspirationRules.Source.REGION_BOSS) == Vector2i(50, 80), "区域 Boss 掉 50~80")
	_check(InspirationRules.amount_range(InspirationRules.Source.FINAL_BOSS) == Vector2i(150, 200), "最终 Boss 掉 150~200")
	_check(InspirationRules.amount_range(InspirationRules.Source.SPECIAL) == Vector2i(5, 10), "特殊怪掉 5~10")
	_check(InspirationRules.amount_range(InspirationRules.Source.BREAKABLE) == Vector2i(1, 1), "场景破坏掉 1")
	_check(InspirationRules.amount_range(InspirationRules.Source.EVENT) == Vector2i(10, 40), "事件掉 10~40")
	_check(InspirationRules.amount_range(InspirationRules.Source.CODEX) == Vector2i(5, 5), "图鉴新发现 5")
	_check(InspirationRules.amount_range(InspirationRules.Source.FLAWLESS_ROOM) == Vector2i(5, 5), "无伤清房 5")
	_check(InspirationRules.amount_range(InspirationRules.Source.REPLACEMENT_BURST) == Vector2i(3, 3), "替换爆发击杀 3")


func _test_roll() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var total: int = 0
	for index: int in 2000:
		var value: int = InspirationRules.roll(InspirationRules.Source.NORMAL, rng)
		_check(value == 0 or (value >= 1 and value <= 3), "小怪掉落数量合法")
		if value > 0:
			total += 1
	# 15% 概率，2000 次抽样允许较宽区间。
	_check(total > 150 and total < 450, "小怪掉落率接近 15%%（实际 %d/2000）" % total)
	for index: int in 50:
		var boss: int = InspirationRules.roll(InspirationRules.Source.REGION_BOSS, rng)
		_check(boss >= 50 and boss <= 80, "区域 Boss 必掉且数量合法")
	_check(InspirationRules.roll(999, rng) == 0, "未知来源不掉落")


func _test_conversion() -> void:
	_check(InspirationRules.material_value(0) == 2, "普通材料 2")
	_check(InspirationRules.material_value(1) == 8, "稀有材料 8")
	_check(InspirationRules.material_value(2) == 25, "史诗材料 25")
	_check(InspirationRules.material_value(3) == 80, "传说材料 80")
	_check(InspirationRules.material_value(0, true) == 200, "Boss 材料 200")
	_check(InspirationRules.material_conversion({0: 3, 1: 2, 2: 1, 3: 1}) == 6 + 16 + 25 + 80, "混合品质转化")
	_check(InspirationRules.material_conversion({}, 2) == 400, "Boss 材料单独统计")
	_check(InspirationRules.material_conversion({9: 1}) == 80, "越界品质夹到最高档")


func _test_retention_and_difficulty() -> void:
	_check(is_zero_approx(InspirationRules.retention_ratio(0)), "未购买留存时 0%")
	_check(is_equal_approx(InspirationRules.retention_ratio(1), 0.05), "留存 I = 5%")
	_check(is_equal_approx(InspirationRules.retention_ratio(3), 0.15), "留存 III = 15%")
	_check(is_equal_approx(InspirationRules.retention_ratio(5), 0.25), "留存 V = 25%")
	_check(is_equal_approx(InspirationRules.retention_ratio(9), 0.25), "留存上限 25%")
	_check(is_equal_approx(InspirationRules.difficulty_multiplier(0), 1.0), "学徒 1.0x")
	_check(is_equal_approx(InspirationRules.difficulty_multiplier(1), 1.2), "炼金师 1.2x")
	_check(is_equal_approx(InspirationRules.difficulty_multiplier(2), 1.5), "大师 1.5x")
	_check(is_equal_approx(InspirationRules.difficulty_multiplier(9), 1.5), "难度倍率夹到上限")


func _test_codex_bonus() -> void:
	_check(is_zero_approx(InspirationRules.codex_bonus(0.1)), "图鉴 10% 无加成")
	_check(is_equal_approx(InspirationRules.codex_bonus(0.25), 0.05), "图鉴 25% → +5%")
	_check(is_equal_approx(InspirationRules.codex_bonus(0.5), 0.10), "图鉴 50% → +10%")
	_check(is_equal_approx(InspirationRules.codex_bonus(0.75), 0.20), "图鉴 75% → +20%")
	_check(is_equal_approx(InspirationRules.codex_bonus(1.0), 0.30), "图鉴 100% → +30%")


func _test_settlement() -> void:
	var plain: Dictionary = InspirationRules.settlement(100, {}, 0)
	_check(int(plain["final"]) == 200, "基础结算 = 局内 + 贤者之石 100")
	_check(int(plain["sage_stone"]) == 100, "贤者之石基础 100")
	var converted: Dictionary = InspirationRules.settlement(100, {0: 5}, 0)
	_check(int(converted["materials"]) == 10, "5 个普通材料 = 10")
	_check(int(converted["final"]) == 210, "含材料转化的结算")
	var hard: Dictionary = InspirationRules.settlement(100, {}, 2, 20, 1.0)
	_check(int(hard["base"]) == 220, "表现加成计入基数")
	_check(int(hard["final"]) == int(round(220.0 * 1.5 * 1.3)), "难度与图鉴按乘区处理")


func _test_run_ledger() -> void:
	var run := InspirationRun.new()
	run.launch(20, InspirationRules.Source.ELITE)
	_check(run.in_flight == 20 and run.gained == 0, "掉落先进飞行中")
	_check(run.collect(20) == 20, "飞入后计入已获得")
	_check(run.gained == 20 and run.in_flight == 0, "账本守恒")
	_check(run.source_total(InspirationRules.Source.ELITE) == 20, "来源统计正确")
	run.launch(5, InspirationRules.Source.NORMAL)
	_check(run.total_launched() == 25, "总数含飞行中")
	var death: Dictionary = run.death(1)
	_check(int(death["kept"]) == 1 and int(death["lost"]) == 19, "死亡保留 5%")
	_check(run.in_flight == 0, "死亡清空飞行中")
	var settle: Dictionary = run.settle({1: 2}, 0)
	_check(int(settle["final"]) == 1 + 100 + 16, "通关结算")


func _test_drop_visuals() -> void:
	_check(InspirationDrop.POOL_SIZE == 200, "对象池预分配 200")
	_check(InspirationDrop.MERGE_THRESHOLD == 30, "超过 30 个合并光团")
	_check(InspirationDrop.BURST_END < InspirationDrop.SCATTER_END, "阶段顺序：生成早于散开")
	_check(InspirationDrop.SCATTER_END < InspirationDrop.HOVER_END, "阶段顺序：散开早于悬停")
	_check(is_equal_approx(InspirationDrop.hover_duration(InspirationRules.Source.NORMAL), 0.2), "小怪悬停 0.2s")
	_check(is_equal_approx(InspirationDrop.hover_duration(InspirationRules.Source.ELITE), 0.4), "精英悬停 0.4s")
	_check(is_equal_approx(InspirationDrop.hover_duration(InspirationRules.Source.REGION_BOSS), 0.6), "Boss 悬停 0.6s")
	_check(InspirationDrop.trajectory_of(InspirationRules.Source.NORMAL) == InspirationDrop.Trajectory.STRAIGHT, "小怪直线")
	_check(InspirationDrop.trajectory_of(InspirationRules.Source.ELITE) == InspirationDrop.Trajectory.ARC, "精英弧线")
	_check(InspirationDrop.trajectory_of(InspirationRules.Source.REGION_BOSS) == InspirationDrop.Trajectory.SPIRAL, "Boss 螺旋")
	_check(InspirationDrop.is_batched(InspirationRules.Source.ELITE), "精英分批飞入")
	_check(not InspirationDrop.is_batched(InspirationRules.Source.NORMAL), "小怪一次飞入")
	_check(InspirationDrop.FLY_SPEED_START < InspirationDrop.FLY_SPEED_END, "飞入先慢后快")
	_check(InspirationDrop.DIAMETER_MIN >= 4.0 and InspirationDrop.DIAMETER_MAX <= 12.0, "光点直径 4~12px")
	_check(InspirationDrop.TRAIL_SEGMENTS_MIN >= 3 and InspirationDrop.TRAIL_SEGMENTS_MAX <= 8, "拖尾 3~8 节")
	for source: int in InspirationRules.COUNT:
		_check(InspirationDrop.sfx_of(source) != &"", "来源 %d 有音效" % source)
	var splits: PackedInt32Array = InspirationDrop.split_amount(10, 3)
	var sum: int = 0
	for value: int in splits:
		sum += value
	_check(sum == 10, "光点拆分后总数不变")
	_check(splits.size() == 3 and splits[0] >= splits[2], "拆分尽量平均")
	_check(InspirationDrop.point_count(0, InspirationRules.Source.NORMAL) == 0, "0 灵感没有光点")
	_check(InspirationDrop.point_count(60, InspirationRules.Source.REGION_BOSS) <= 12, "Boss 光点数量有上限")
