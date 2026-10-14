extends SceneTree

## 行为词条 → 命中效果表：9 条行为词条逐级数值、空表、半径与穿透预算。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## 只用一条行为词条造组合。
static func _combo(trait_id: StringName, level: int) -> BrewCombo:
	var combo: BrewCombo = BrewCombo.new()
	var instance: TraitInstance = TraitCatalog.create(trait_id, level, 1)
	if instance != null:
		combo.traits = [instance]
	combo.effect_tags = [trait_id]
	return combo


func _run() -> void:
	# ── 空表 ────────────────────────────────────────────────────────────
	var empty: Dictionary = AlchemyHitEffects.profile(null)
	_check(not AlchemyHitEffects.has_any(empty), "空组合没有任何行为效果")
	_check(int(empty["pierce"]) == 0, "空表穿透为 0")
	_check(is_equal_approx(float(empty["spread_tiles"]), 0.0), "空表扩散为 0")
	_check(AlchemyHitEffects.profile(BrewCombo.new()) == empty, "无词条组合与空表一致")
	_check(is_equal_approx(AlchemyHitEffects.extra_hit_radius_tiles(empty), 0.0), "空表额外命中半径为 0")
	_check(AlchemyHitEffects.pierce_budget(empty) == 0, "空表穿透预算为 0")

	# ── 爆炸：10/15/20/25/30% 触发，1/1.5/2/2.5/3 格，50/60/70/80/100% 伤害 ──
	for level: int in range(1, 6):
		var explode: Dictionary = AlchemyHitEffects.profile(_combo(&"explode", level))["explode"]
		_check(is_equal_approx(float(explode["chance"]), [0.10, 0.15, 0.20, 0.25, 0.30][level - 1]), "爆炸 %d 级触发率" % level)
		_check(is_equal_approx(float(explode["radius_tiles"]), [1.0, 1.5, 2.0, 2.5, 3.0][level - 1]), "爆炸 %d 级范围" % level)
		_check(is_equal_approx(float(explode["damage"]), [0.50, 0.60, 0.70, 0.80, 1.00][level - 1]), "爆炸 %d 级伤害比" % level)
	_check(bool(AlchemyHitEffects.profile(_combo(&"explode", 5))["explode"]["chain"]), "爆炸 V 可连锁")
	_check(not bool(AlchemyHitEffects.profile(_combo(&"explode", 4))["explode"]["chain"]), "爆炸 IV 不可连锁")

	# ── 连锁：目标 1/1/2/3/4，V 可回弹 ──────────────────────────────────
	for level: int in range(1, 6):
		var chain: Dictionary = AlchemyHitEffects.profile(_combo(&"chain", level))["chain"]
		_check(int(chain["targets"]) == [1, 1, 2, 3, 4][level - 1], "连锁 %d 级目标数" % level)
		_check(is_equal_approx(float(chain["damage"]), [0.50, 0.60, 0.70, 0.80, 1.00][level - 1]), "连锁 %d 级伤害比" % level)
	_check(bool(AlchemyHitEffects.profile(_combo(&"chain", 5))["chain"]["rebound"]), "连锁 V 可回弹")

	# ── 回旋：III 起才有伤害，V 可二次回旋 ──────────────────────────────
	var whirl_1: Dictionary = AlchemyHitEffects.profile(_combo(&"whirl", 1))["whirl"]
	_check(is_equal_approx(float(whirl_1["chance"]), 0.20), "回旋 I 级触发率 20%")
	_check(is_equal_approx(float(whirl_1["damage"]), 0.60), "回旋 I 级没有伤害比时退回 60%")
	var whirl_3: Dictionary = AlchemyHitEffects.profile(_combo(&"whirl", 3))["whirl"]
	_check(is_equal_approx(float(whirl_3["damage"]), 0.60), "回旋 III 级伤害比 60%")
	_check(not bool(whirl_3["double"]), "回旋 III 不可二次回旋")
	_check(bool(AlchemyHitEffects.profile(_combo(&"whirl", 5))["whirl"]["double"]), "回旋 V 可二次回旋")

	# ── 弹射：次数 1/1/2/3/4，V 可弹墙 ──────────────────────────────────
	for level: int in range(1, 6):
		var bounce: Dictionary = AlchemyHitEffects.profile(_combo(&"bounce", level))["bounce"]
		_check(int(bounce["bounces"]) == [1, 1, 2, 3, 4][level - 1], "弹射 %d 级次数" % level)
	_check(bool(AlchemyHitEffects.profile(_combo(&"bounce", 5))["bounce"]["wall"]), "弹射 V 可弹墙")

	# ── 穿透：1/1/2/3/无限（-1）────────────────────────────────────────
	_check(AlchemyHitEffects.pierce_budget(AlchemyHitEffects.profile(_combo(&"pierce", 1))) == 1, "穿透 I 打 1 个")
	_check(AlchemyHitEffects.pierce_budget(AlchemyHitEffects.profile(_combo(&"pierce", 3))) == 2, "穿透 III 打 2 个")
	_check(AlchemyHitEffects.pierce_budget(AlchemyHitEffects.profile(_combo(&"pierce", 5))) == -1, "穿透 V 无限")

	# ── 扩散：+1/1.5/2/2.5/3 格，并叠加到额外命中半径 ───────────────────
	var spread: Dictionary = AlchemyHitEffects.profile(_combo(&"spread", 4))
	_check(is_equal_approx(float(spread["spread_tiles"]), 2.5), "扩散 IV 级 2.5 格")
	_check(AlchemyHitEffects.has_any(spread), "只有扩散也算有行为效果")
	_check(is_equal_approx(AlchemyHitEffects.extra_hit_radius_tiles(spread), 2.5), "扩散单独决定额外命中半径")
	# 爆炸 + 扩散：半径取爆炸的，再叠加扩散。
	var combo: BrewCombo = _combo(&"explode", 2)
	var extra_spread: TraitInstance = TraitCatalog.create(&"spread", 1, 1)
	combo.traits.append(extra_spread)
	var combined: Dictionary = AlchemyHitEffects.profile(combo)
	_check(is_equal_approx(AlchemyHitEffects.extra_hit_radius_tiles(combined), 2.5), "爆炸 1.5 格 + 扩散 1 格 = 2.5 格")

	# ── 召唤 / 变形：只做配置透出，不参与命中半径 ───────────────────────
	var summon: Dictionary = AlchemyHitEffects.profile(_combo(&"summon", 5))["summon"]
	_check(int(summon["count"]) == 3 and is_equal_approx(float(summon["duration"]), 12.0), "召唤 V 数量 3 / 时长 12s")
	_check(bool(summon["explode"]), "召唤 V 可爆炸")
	_check(is_equal_approx(AlchemyHitEffects.extra_hit_radius_tiles(AlchemyHitEffects.profile(_combo(&"summon", 5))), 0.0), "召唤不改变额外命中半径")
	var transform: Dictionary = AlchemyHitEffects.profile(_combo(&"transform", 5))["transform"]
	_check(is_equal_approx(float(transform["radius"]), 0.50), "变形 V 范围 +50%")
	_check(bool(transform["free_switch"]), "变形 V 自由切换")

	# ── 召唤来源表：命中触发（召唤 / 骨 V）与击杀触发（灵魂）────────────
	_check(AlchemyHitEffects.summon_specs(empty).is_empty(), "空表没有命中召唤来源")
	_check(AlchemyHitEffects.kill_specs(empty).is_empty(), "空表没有击杀召唤来源")
	var summon_specs: Array[Dictionary] = AlchemyHitEffects.summon_specs(AlchemyHitEffects.profile(_combo(&"summon", 5)))
	_check(summon_specs.size() == 1, "召唤词条给出一条命中召唤来源")
	_check(is_equal_approx(float(summon_specs[0]["chance"]), 0.25), "召唤 V 触发率 25%")
	_check(int(summon_specs[0]["count"]) == 3, "召唤 V 数量 3")
	_check(is_equal_approx(float(summon_specs[0]["duration"]), 12.0), "召唤 V 时长 12s")
	_check(bool(summon_specs[0]["explode"]), "召唤 V 的召唤物可爆炸")
	_check(summon_specs[0]["flavor"] == &"summon", "召唤来源标记为 summon")

	var bone_specs: Array[Dictionary] = AlchemyHitEffects.summon_specs(AlchemyHitEffects.profile(_combo(&"bone", 5)))
	_check(bone_specs.size() == 1, "骨 V 给出一条骷髅来源")
	_check(bone_specs[0]["flavor"] == &"bone", "骷髅来源标记为 bone")
	_check(is_equal_approx(float(bone_specs[0]["chance"]), AlchemyRules.SKELETON_CHANCE), "骷髅触发率取配置值")
	_check(is_equal_approx(float(bone_specs[0]["duration"]), AlchemyRules.SKELETON_DURATION), "骷髅寿命取配置值")
	_check(not bool(bone_specs[0]["explode"]), "骷髅不带自爆标记")
	_check(AlchemyHitEffects.summon_specs(AlchemyHitEffects.profile(_combo(&"bone", 4))).is_empty(), "骨 IV 还不能召唤骷髅")

	var both: BrewCombo = _combo(&"summon", 1)
	both.traits.append(TraitCatalog.create(&"bone", 5, 1))
	_check(AlchemyHitEffects.summon_specs(AlchemyHitEffects.profile(both)).size() == 2, "召唤 + 骨 V 同时给出两条来源")

	var soul_specs: Array[Dictionary] = AlchemyHitEffects.kill_specs(AlchemyHitEffects.profile(_combo(&"soul", 5)))
	_check(soul_specs.size() == 1, "灵魂词条给出一条击杀召唤来源")
	_check(is_equal_approx(float(soul_specs[0]["chance"]), 0.25), "灵魂 V 生成概率 25%")
	_check(int(soul_specs[0]["count"]) == 3, "灵魂 V 生成 3 个游魂")
	_check(bool(soul_specs[0]["explode"]), "灵魂 V 的游魂可爆炸")
	_check(soul_specs[0]["flavor"] == &"soul", "游魂来源标记为 soul")
	_check(is_equal_approx(float(soul_specs[0]["duration"]), AlchemyRules.SOUL_BURST_DURATION), "游魂寿命取配置值")
	var soul_two: Array[Dictionary] = AlchemyHitEffects.kill_specs(AlchemyHitEffects.profile(_combo(&"soul", 2)))
	_check(soul_two.size() == 1 and soul_two[0]["flavor"] == &"soul", "灵魂 II 也走击杀生成")
	_check(not bool(soul_two[0]["explode"]), "灵魂 II 的游魂不爆炸")

	# ── 召唤来源 → 外观颜色 ─────────────────────────────────────────────
	_check(AlchemyHitEffects.flavor_color(&"bone") != AlchemyHitEffects.flavor_color(&"soul"), "骨与灵魂颜色不同")
	_check(AlchemyHitEffects.flavor_color(&"soul") != AlchemyHitEffects.flavor_color(&"split"), "灵魂与分身颜色不同")
	_check(AlchemyHitEffects.flavor_color(&"summon") == AlchemyHitEffects.flavor_color(&"unknown"), "未标记的来源用默认色")

	# ── 非行为词条不进表 ────────────────────────────────────────────────
	var element: Dictionary = AlchemyHitEffects.profile(_combo(&"fire", 5))
	_check(not AlchemyHitEffects.has_any(element), "元素词条不产生行为效果")
	_check(is_equal_approx(AlchemyHitEffects.extra_hit_radius_tiles(element), 0.0), "元素词条不改变额外命中半径")
	var modifier: Dictionary = AlchemyHitEffects.profile(_combo(&"heavy", 5))
	_check(not AlchemyHitEffects.has_any(modifier), "修饰词条不产生行为效果")

	# ── 炼金台接口 ──────────────────────────────────────────────────────
	var station: AlchemyStation = AlchemyStation.new()
	root.add_child(station)
	_check(not AlchemyHitEffects.has_any(station.hit_effects()), "没有激活组合时效果表为空")
	station.absorb_material(1002, 2)
	station.fill_first_free_slot(1002)
	var brewed: BrewCombo = station.brew_from_slots()
	_check(brewed != null, "硝石炼出组合")
	var live: Dictionary = station.hit_effects()
	_check(live.has("explode") and not live["explode"].is_empty(), "激活组合的爆炸词条透出到效果表")
	_check(AlchemyHitEffects.has_any(live), "激活组合有行为效果")
	station.free()

	print("ALCHEMY HIT EFFECTS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
