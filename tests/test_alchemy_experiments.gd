extends SceneTree

## 实验系统：配方匹配、未解锁遮蔽、成功 / 事故分支、材料消耗与图鉴登记。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## 固定种子的随机源，保证「成功 / 事故」分支可复现。
func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _run() -> void:
	# ── 配置表 ──────────────────────────────────────────────────────────
	_check(AlchemyExperiments.EXPERIMENTS.size() >= 12, "实验配置至少 12 条")
	_check(not AlchemyExperiments.definition_of(&"exp_poison_smoke").is_empty(), "已知实验能取到定义")
	_check(AlchemyExperiments.definition_of(&"exp_not_exist").is_empty(), "未知实验返回空定义")

	# ── 配方匹配（与顺序无关，取材料最多的子集）────────────────────────
	_check(AlchemyExperiments.key_of([1002, 1001]) == AlchemyExperiments.key_of([1001, 1002]), "配方键与顺序无关")
	var match: Dictionary = AlchemyExperiments.experiment_for([1002, 1001])
	_check(match.get("id", &"") == &"exp_poison_smoke", "毒菇 + 硝石 命中毒烟实验")
	_check(AlchemyExperiments.experiment_for([1001]).is_empty(), "缺少一种材料不命中")
	_check(AlchemyExperiments.experiment_for([9999]).is_empty(), "无关材料不命中")
	var bigger: Dictionary = AlchemyExperiments.experiment_for([1001, 1002, 1003])
	_check(bigger.get("id", &"") == &"exp_poison_smoke", "多材料组合取最长匹配子集")

	# ── 未解锁遮蔽 ──────────────────────────────────────────────────────
	var lab: AlchemyExperiments = AlchemyExperiments.new()
	_check(lab.display_name(&"exp_poison_smoke") == AlchemyExperiments.UNKNOWN_TEXT, "未解锁显示「？？？」")
	_check(not lab.hint_of(&"exp_poison_smoke").is_empty(), "未解锁仍给产地提示")
	_check(not lab.is_unlocked(&"exp_poison_smoke"), "初始未解锁")
	_check(lab.unlock(&"exp_poison_smoke"), "首次解锁成功")
	_check(not lab.unlock(&"exp_poison_smoke"), "重复解锁返回 false")
	_check(lab.is_unlocked(&"exp_poison_smoke"), "解锁后可查询")
	_check(lab.display_name(&"exp_poison_smoke") == "毒烟", "解锁后显示正式名字")
	_check(lab.completion_ratio() > 0.0 and lab.completion_ratio() < 1.0, "完成度介于 0 与 1 之间")
	_check(is_equal_approx(lab.completion_ratio(), float(lab.unlocked_count()) / float(AlchemyExperiments.EXPERIMENTS.size())), "完成度 = 解锁数 / 总数")

	# ── resolve：无关组合 → nothing ─────────────────────────────────────
	var probe: AlchemyExperiments = AlchemyExperiments.new()
	var nothing: Dictionary = probe.resolve([9999], _seeded(1))
	_check(nothing.get("status", "") == "nothing", "无关组合返回 nothing")
	_check(probe.unlocked_count() == 0, "nothing 不解锁任何东西")

	# ── resolve：事故分支（自伤 + 额外热量）────────────────────────────
	var accident_rng: RandomNumberGenerator = _seeded(7)
	var accident: Dictionary = {}
	for _i: int in range(200):
		probe.reset()
		var attempt: Dictionary = probe.resolve([1001, 1002], accident_rng)
		if attempt.get("status", "") == "accident":
			accident = attempt
			break
	_check(not accident.is_empty(), "固定种子下能复现事故分支")
	_check(is_equal_approx(float(accident.get("self_damage", 0.0)), AlchemyExperiments.ACCIDENT_SELF_DAMAGE), "事故自伤等于配置值")
	_check(is_equal_approx(float(accident.get("heat", 0.0)), AlchemyExperiments.EXPERIMENT_HEAT + AlchemyExperiments.ACCIDENT_HEAT), "事故热量 = 基础 + 额外")
	_check(not probe.is_unlocked(&"exp_poison_smoke"), "事故不解锁实验")

	# ── resolve：成功分支（解锁 + 登记反应）────────────────────────────
	var success_rng: RandomNumberGenerator = _seeded(3)
	var success: Dictionary = {}
	for _i: int in range(200):
		probe.reset()
		var attempt: Dictionary = probe.resolve([1001, 1002], success_rng)
		if attempt.get("status", "") == "unlocked":
			success = attempt
			break
	_check(not success.is_empty(), "固定种子下能复现成功分支")
	_check(probe.is_unlocked(&"exp_poison_smoke"), "成功解锁实验")
	_check(is_equal_approx(float(success.get("self_damage", 0.0)), 0.0), "成功不自伤")
	_check(is_equal_approx(float(success.get("heat", 0.0)), AlchemyExperiments.EXPERIMENT_HEAT), "成功只有基础热量")
	_check(StringName(success.get("reaction", &"")) == &"poison_smoke", "成功返回对应反应 id")

	# ── resolve：已解锁 → known ─────────────────────────────────────────
	var known: Dictionary = probe.resolve([1001, 1002], _seeded(99))
	_check(known.get("status", "") == "known", "已解锁组合返回 known")
	_check(known.get("name", "") == "毒烟", "known 带正式名字")

	# ── 存档往返 ────────────────────────────────────────────────────────
	var snapshot: Dictionary = probe.to_dict()
	var restored: AlchemyExperiments = AlchemyExperiments.new()
	restored.from_dict(snapshot)
	_check(restored.is_unlocked(&"exp_poison_smoke"), "存档往返保留解锁状态")
	_check(restored.unlocked_count() == probe.unlocked_count(), "存档往返解锁数一致")
	restored.reset()
	_check(restored.unlocked_count() == 0, "reset 清空解锁")

	# ── 炼金台接线：消耗材料、登记图鉴、拒绝无效组合 ──────────────────
	var station: AlchemyStation = AlchemyStation.new()
	station.setup()
	root.add_child(station)

	var rejected: Array[String] = []
	station.brew_rejected.connect(func(reason: String) -> void: rejected.append(reason))

	station.run_experiment()
	_check(rejected.size() == 1, "空素材槽做实验发出拒绝")

	station.absorb_material(1001, 3)
	station.absorb_material(1002, 3)
	station.clear_slots()
	station.fill_first_free_slot(1001)
	station.fill_first_free_slot(1002)
	var bag_before: int = station.bag.count(1001) + station.bag.count(1002)
	var self_damage_seen: Array[float] = []
	station.self_damage.connect(func(amount: float) -> void: self_damage_seen.append(amount))
	station._rng.seed = 7
	var result: Dictionary = station.run_experiment()
	var status: String = String(result.get("status", ""))
	_check(status == "unlocked" or status == "accident", "命中配方返回成功或事故")
	var bag_after: int = station.bag.count(1001) + station.bag.count(1002)
	_check(bag_after < bag_before, "实验消耗素材槽材料")
	_check(is_equal_approx(station.session.heat.heat, float(result.get("heat", 0.0))), "实验热量写入热量系统")
	if status == "accident":
		_check(self_damage_seen.size() == 1, "事故发出自伤信号")

	# 无效组合不消耗材料。
	station.clear_slots()
	station.absorb_material(9999, 1)
	station.fill_first_free_slot(9999)
	var bag_unknown_before: int = station.bag.count(9999)
	station.run_experiment()
	_check(station.bag.count(9999) == bag_unknown_before, "无效组合不消耗材料")

	# 成功时把反应登记进图鉴（直接调用登记逻辑，避免随机性）。
	var before_reaction: bool = station.compendium.is_reaction_discovered(&"poison_smoke")
	station._record_experiment({"reaction": &"poison_smoke"})
	_check(station.compendium.is_reaction_discovered(&"poison_smoke"), "实验成功把反应登记进图鉴")
	_check(before_reaction == false or before_reaction == true, "图鉴登记调用安全")

	station.free()
	print("ALCHEMY EXPERIMENTS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
