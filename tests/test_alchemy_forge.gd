extends SceneTree

## 非战斗合金 / 重铸：候选筛选、加权抽取、选择状态与炼金台消耗接线。

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
	# ── 合金资格 ────────────────────────────────────────────────────────
	_check(AlchemyForge.can_alloy(1001, 1002), "同品质不同材料可合金")
	_check(not AlchemyForge.can_alloy(1001, 1001), "同一种材料不能合金")
	_check(not AlchemyForge.can_alloy(1001, 1021), "跨品质不能合金")
	_check(not AlchemyForge.can_alloy(1061, 1062), "传说材料不能再合金")
	_check(not AlchemyForge.can_alloy(9999, 1001), "未知材料不能合金")

	# 毒菇（毒/持续/扩散）+ 硝石（火/爆炸）→ 品质 1 里共享词条的候选。
	var candidates: Array[int] = AlchemyForge.alloy_candidates(1001, 1002)
	_check(not candidates.is_empty(), "合金有候选产物")
	_check(candidates.has(1029), "毒腺（毒/扩散/持续）是候选")
	_check(not candidates.has(1022), "雷石（电/连锁）不是候选")
	for id: int in candidates:
		_check(AlchemyForge.quality_of(id) == 1, "候选品质都是原料 +1")

	# ── 加权抽取 ────────────────────────────────────────────────────────
	for seed_value: int in range(20):
		var product: int = AlchemyForge.alloy(1001, 1002, _seeded(seed_value))
		_check(candidates.has(product), "合金产物落在候选集内")
	var invalid: int = AlchemyForge.alloy(1001, 1001, _seeded(1))
	_check(invalid == -1, "非法合金返回 -1")

	# ── 重铸 ────────────────────────────────────────────────────────────
	var reforges: Array[int] = AlchemyForge.reforge_candidates(1001)
	_check(not reforges.is_empty(), "重铸有候选")
	_check(not reforges.has(1001), "重铸候选不含自身")
	for id: int in reforges:
		_check(AlchemyForge.quality_of(id) == AlchemyForge.quality_of(1001), "重铸保持品质")
	_check(AlchemyForge.can_reforge(1001), "普通材料可重铸")
	var reforged: int = AlchemyForge.reforge(1001, _seeded(5))
	_check(reforges.has(reforged), "重铸产物落在候选集内")

	# ── 选择状态 ────────────────────────────────────────────────────────
	var forge: AlchemyForge = AlchemyForge.new()
	_check(not forge.alloy_ready(), "空选择不能合金")
	_check(forge.toggle_alloy_material(1001), "选中第一种原料")
	_check(not forge.alloy_ready(), "只选一种不能合金")
	_check(forge.toggle_alloy_material(1002), "选中第二种原料")
	_check(forge.alloy_ready(), "两种同品质原料可以合金")
	_check(forge.toggle_alloy_material(1001), "再次点击取消第一种")
	_check(not forge.alloy_selection.has(1001), "取消后不在选择里")
	_check(not forge.toggle_alloy_material(9999), "未知材料无法选中")
	# 第三种会顶掉最早的一种。
	forge.clear_alloy_selection()
	forge.toggle_alloy_material(1001)
	forge.toggle_alloy_material(1002)
	forge.toggle_alloy_material(1003)
	_check(forge.alloy_selection.size() == 2 and forge.alloy_selection[1] == 1003, "第三种顶掉最早的一种")
	_check(forge.set_reforge_material(1004), "选中重铸材料")
	_check(forge.reforge_ready(), "重铸就绪")
	_check(not forge.set_reforge_material(9999), "未知材料无法重铸")

	# ── 炼金台接线 ──────────────────────────────────────────────────────
	var station: AlchemyStation = AlchemyStation.new()
	root.add_child(station)
	station.absorb_material(1001, 3)
	station.absorb_material(1002, 3)
	station.toggle_alloy_material(1001)
	station.toggle_alloy_material(1002)
	_check(station.alloy_ready(), "炼金台合金就绪")
	var before_total: int = station.bag.count(1001) + station.bag.count(1002)
	var product: int = station.alloy_now()
	_check(product > 0, "合金产出材料")
	_check(AlchemyForge.quality_of(product) == 1, "合金产物品质 +1")
	_check(station.bag.count(product) == 1, "合金产物进背包")
	_check(station.bag.count(1001) + station.bag.count(1002) == before_total - 2, "合金各消耗 1 个原料")
	_check(station.forge.alloy_selection.is_empty(), "合金后清空选择")

	station.absorb_material(1004, 2)
	station.set_reforge_material(1004)
	var before_reforge: int = station.bag.count(1004)
	var reforged_id: int = station.reforge_now()
	_check(reforged_id > 0, "重铸产出材料")
	_check(station.bag.count(1004) == before_reforge - 1, "重铸消耗 1 个原料")
	_check(station.bag.count(reforged_id) >= 1, "重铸产物进背包")

	# 材料不足时拒绝并给出提示。
	var rejected: Array[String] = []
	station.brew_rejected.connect(func(reason: String) -> void: rejected.append(reason))
	station.set_reforge_material(1002)
	station.bag.remove(1002, station.bag.count(1002))
	station.reforge_now()
	_check(rejected.size() == 1, "材料不足时重铸被拒绝")

	station.free()
	print("ALCHEMY FORGE: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
