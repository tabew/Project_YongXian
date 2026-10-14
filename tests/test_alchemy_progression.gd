extends SceneTree

## 升级与遗物：配置表、层数上限、修正聚合、派生数值、存档往返与炼金台接线。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## 组合里是否含有指定词条。
static func _combo_has(combo: BrewCombo, trait_id: StringName) -> bool:
	if combo == null:
		return false
	for instance: TraitInstance in combo.traits:
		if instance.id == trait_id:
			return true
	return false


## 组合里是否含有指定反应。
static func _combo_has_reaction(combo: BrewCombo, reaction_id: StringName) -> bool:
	if combo == null:
		return false
	for reaction: Dictionary in combo.reactions:
		if StringName(reaction.get("id", &"")) == reaction_id:
			return true
	return false


func _run() -> void:
	# ── 配置表 ──────────────────────────────────────────────────────────
	_check(ProgressionCatalog.UPGRADES.size() >= 18, "升级配置至少 18 条")
	_check(ProgressionCatalog.RELICS.size() >= 30, "遗物配置至少 30 条")
	_check(ProgressionCatalog.has_upgrade(&"slot_plus"), "已知升级可查询")
	_check(not ProgressionCatalog.has_upgrade(&"nope"), "未知升级返回 false")
	_check(ProgressionCatalog.has_relic(&"alchemy_heart"), "已知遗物可查询")
	_check(not ProgressionCatalog.has_relic(&"nope"), "未知遗物返回 false")
	_check(ProgressionCatalog.max_level_of(&"slot_plus") == 2, "素材槽升级最多 2 层")
	_check(ProgressionCatalog.max_level_of(&"bag_expand") == 4, "背包升级最多 4 层")
	_check(ProgressionCatalog.display_name_of(&"alchemy_heart") == "炼金之心", "遗物显示名")
	_check(ProgressionCatalog.display_name_of(&"burst_master") == "爆发大师", "升级显示名")
	# 每个元素都有一件 +1 级遗物。
	for element_id: StringName in [&"fire", &"poison", &"ice", &"electric", &"acid", &"magnet",
			&"soul", &"bone", &"blood", &"wind", &"sand", &"light", &"dark"]:
		_check(ProgressionCatalog.has_relic(StringName("relic_" + String(element_id))), "元素遗物齐全：%s" % element_id)

	# ── 层数与遗物 ──────────────────────────────────────────────────────
	var progress: AlchemyProgression = AlchemyProgression.new()
	_check(progress.upgrade_level(&"slot_plus") == 0, "初始升级层数为 0")
	_check(progress.add_upgrade(&"slot_plus") == 1, "加一层升级")
	_check(progress.add_upgrade(&"slot_plus", 5) == 2, "升级层数按 max_level 截断")
	_check(progress.is_upgrade_maxed(&"slot_plus"), "满层判定")
	_check(progress.add_upgrade(&"slot_plus") == 2, "满层再加不变")
	_check(progress.add_upgrade(&"not_a_upgrade") == 0, "非法升级 id 被忽略")
	_check(progress.upgrade_count() == 2, "升级层数总计")
	_check(progress.add_relic(&"alchemy_heart"), "首次获得遗物")
	_check(not progress.add_relic(&"alchemy_heart"), "重复遗物返回 false")
	_check(not progress.add_relic(&"not_a_relic"), "非法遗物被忽略")
	_check(progress.relic_count() == 1, "遗物数量")

	# ── 派生数值 ────────────────────────────────────────────────────────
	_check(progress.slot_plus() == 3, "素材槽加成累加（升级 2 + 遗物 1）")
	_check(is_equal_approx(progress.slow_motion_scale(), AlchemyRules.SLOW_MOTION_SCALE), "无慢动作遗物用基准值")
	progress.add_relic(&"slow_motion_chip")
	_check(is_equal_approx(progress.slow_motion_scale(), 0.15), "慢动作芯片降到 15%")
	_check(is_equal_approx(progress.burst_ratio(), AlchemyRules.REPLACEMENT_BURST_RATIO), "无爆发升级用基准比例")
	progress.add_upgrade(&"burst_master")
	_check(is_equal_approx(progress.burst_ratio(), 1.5), "爆发大师把替换爆发拉到 150%")
	_check(is_equal_approx(progress.heat_gain_multiplier(), 1.0), "无热量减缓时倍率为 1")
	progress.add_upgrade(&"heat_slow", 2)
	_check(is_equal_approx(progress.heat_gain_multiplier(), 0.0), "两层热量减缓把积累降到 0")
	_check(is_equal_approx(progress.overload_duration_multiplier(), 1.0), "无过热缩短时倍率为 1")
	progress.add_upgrade(&"overload_shorten", 2)
	_check(is_equal_approx(progress.overload_duration_multiplier(), 0.1), "两层过热缩短（下限 10%）")
	_check(is_equal_approx(progress.stack_multiplier(), 1.0), "无堆叠升级时倍率为 1")
	progress.add_upgrade(&"stack_plus", 3)
	_check(is_equal_approx(progress.stack_multiplier(), 1.6), "三层堆叠上限 +60%")
	_check(progress.preset_plus() == 0, "无预设升级时加成 0")
	progress.add_upgrade(&"preset_plus", 2)
	_check(progress.preset_plus() == 2, "预设升级加成 2")
	_check(is_equal_approx(progress.heat_cooldown_multiplier(), 1.0), "无冷却升级时倍率为 1")
	progress.add_relic(&"heat_core")
	_check(is_equal_approx(progress.heat_cooldown_multiplier(), 1.5), "热量核心 +50% 冷却")
	_check(is_equal_approx(progress.adsorb_tiles_plus(), 0.0), "无吸附升级时加成 0")
	progress.add_upgrade(&"magnet_range", 3)
	_check(is_equal_approx(progress.adsorb_tiles_plus(), 3.0), "三层吸附范围 +3 格")
	_check(is_equal_approx(progress.crit_bonus(), 0.0), "无暴击遗物时加成 0")
	progress.add_relic(&"crit_eye")
	_check(is_equal_approx(progress.crit_bonus(), 0.15), "暴击之眼 +15%")
	_check(is_equal_approx(progress.duration_bonus(), 0.0), "无时间遗物时加成 0")
	progress.add_relic(&"time_hourglass")
	_check(is_equal_approx(progress.duration_bonus(), 0.25), "时间沙漏 +25% 时长")
	_check(is_equal_approx(progress.reaction_bonus(), 0.0), "无反应遗物时加成 0")
	progress.add_relic(&"reaction_master")
	_check(is_equal_approx(progress.reaction_bonus(), 0.30), "反应大师 +30%")
	_check(is_equal_approx(progress.side_effect_reduction(), 0.0), "无稳定遗物时减免 0")
	progress.add_relic(&"stability_amulet")
	_check(is_equal_approx(progress.side_effect_reduction(), 0.30), "稳定护符 -30% 副作用")

	# ── 元素等级加成 ────────────────────────────────────────────────────
	_check(progress.element_level_plus(&"fire") == 0, "无元素遗物时火加成 0")
	progress.add_relic(&"elemental_affinity")
	_check(progress.element_level_plus(&"fire") == 1, "元素亲和对所有元素 +1")
	progress.add_relic(&"relic_fire")
	_check(progress.element_level_plus(&"fire") == 2, "火遗物再 +1")
	_check(progress.element_level_plus(&"ice") == 1, "冰不吃火遗物加成")

	# ── 布尔修正 ────────────────────────────────────────────────────────
	_check(not progress.uninterruptible(), "默认不免疫打断")
	progress.add_upgrade(&"brew_uninterruptible")
	_check(progress.uninterruptible(), "炼金不打断生效")
	_check(not progress.overload_material_safe(), "默认过载会损失材料")
	progress.add_upgrade(&"overload_protect")
	_check(progress.overload_material_safe(), "过热保护生效")
	_check(not progress.overload_no_weapon_disable(), "默认过载武器失效")
	progress.add_relic(&"overload_engine")
	_check(progress.overload_no_weapon_disable(), "过载引擎生效")
	_check(not progress.interrupt_no_heat(), "默认打断加热量")
	progress.add_relic(&"decoy_straw")
	_check(progress.interrupt_no_heat(), "替身草人免疫打断热量")
	_check(not progress.no_time_cost(), "默认炼金消耗时间")
	progress.add_relic(&"time_sand")
	_check(progress.no_time_cost(), "时之沙不消耗时间")
	_check(not progress.living_safe(), "默认活体伤己")
	progress.add_relic(&"world_tree")
	_check(progress.living_safe(), "世界树苗活体不伤己")

	# ── 存档往返 ────────────────────────────────────────────────────────
	var snapshot: Dictionary = progress.to_dict()
	var restored: AlchemyProgression = AlchemyProgression.new()
	restored.from_dict(snapshot)
	_check(restored.upgrade_level(&"slot_plus") == 2, "存档往返保留升级层数")
	_check(restored.has_relic(&"alchemy_heart"), "存档往返保留遗物")
	_check(restored.relic_count() == progress.relic_count(), "存档往返遗物数一致")
	var tampered: AlchemyProgression = AlchemyProgression.new()
	tampered.from_dict({"upgrades": {"slot_plus": 99, "bogus": 3}, "relics": ["alchemy_heart", "bogus"]})
	_check(tampered.upgrade_level(&"slot_plus") == 2, "存档越界层数被截断")
	_check(tampered.upgrade_level(&"bogus") == 0, "存档未知升级被忽略")
	_check(tampered.relic_count() == 1, "存档未知遗物被忽略")
	restored.reset()
	_check(restored.relic_count() == 0 and restored.upgrade_count() == 0, "reset 清空进度")

	# ── 炼金台接线 ──────────────────────────────────────────────────────
	var station: AlchemyStation = AlchemyStation.new()
	root.add_child(station)
	_check(station.progression != null, "炼金台持有升级 / 遗物进度")
	var slots_before: int = station.slots.slot_count()
	var bag_before: int = station.bag.capacity
	var presets_before: int = station.presets.slot_count
	station.add_upgrade(&"slot_plus", 2)
	station.add_upgrade(&"bag_expand", 4)
	station.add_upgrade(&"preset_plus", 3)
	_check(station.slots.slot_count() == slots_before + 2, "升级立刻扩素材槽")
	_check(station.slots.slot_count() <= AlchemyRules.MAX_MATERIAL_SLOTS, "素材槽不超过上限")
	_check(station.bag.capacity == bag_before + 8, "背包扩容 +2 格 × 4 层")
	_check(station.presets.slot_count == presets_before + 3, "快速预设 +1 × 3 层")

	station.add_relic(&"alchemy_heart")
	_check(station.slots.slot_count() <= AlchemyRules.MAX_MATERIAL_SLOTS, "遗物扩槽同样受上限约束")

	var radius_before: float = station.adsorb_radius_tiles()
	station.add_upgrade(&"magnet_range", 3)
	_check(is_equal_approx(station.adsorb_radius_tiles(), radius_before + 3.0), "吸附范围升级生效")
	_check(is_equal_approx(station.adsorb_radius_pixels(), station.adsorb_radius_tiles() * float(WorldGenerator.TILE_SIZE)), "像素半径换算一致")

	_check(is_equal_approx(station.current_slow_motion_scale(), AlchemyRules.SLOW_MOTION_SCALE), "默认慢动作倍率")
	station.add_relic(&"slow_motion_chip")
	_check(is_equal_approx(station.current_slow_motion_scale(), 0.15), "慢动作芯片接线生效")
	_check(is_equal_approx(station.slow_motion_scale, 0.15), "导出字段同步给 UI")

	station.add_upgrade(&"burst_master")
	_check(is_equal_approx(station.session.burst_ratio, 1.5), "爆发强度写进会话")
	station.add_relic(&"time_hourglass")
	_check(is_equal_approx(station.session.duration_bonus, 0.25), "持续加成写进会话")
	station.add_upgrade(&"heat_slow", 1)
	_check(is_equal_approx(station.session.heat.gain_multiplier, 0.5), "热量减缓写进热量系统")
	station.add_relic(&"heat_core")
	_check(is_equal_approx(station.session.heat.cooldown_multiplier, 1.5), "热量冷却写进热量系统")

	# 热量减缓实际生效：一次炼金的增量为基准的一半。
	var gain: float = station.session.heat.add_brew(0.0, 1.0)
	_check(is_equal_approx(gain, AlchemyRules.HEAT_PER_BREW * 0.5), "热量减缓按倍率作用于炼金增热")
	station.session.heat.reset()

	# 过热保护：过载不损失材料。
	station.add_upgrade(&"overload_protect")
	station.absorb_material(1002, 5)
	station.session.heat.add_heat(AlchemyRules.HEAT_MAX)
	_check(station.bag.count(1002) == 5, "过热保护下过载不损失材料")
	station.session.heat.reset()

	# 过载引擎：过载后武器不失效。
	station.add_relic(&"overload_engine")
	station.session.heat.add_heat(AlchemyRules.HEAT_MAX)
	_check(not station.session.heat.is_weapon_disabled(), "过载引擎让武器不失效")
	station.session.heat.reset()

	# 替身草人：受击打断不加热量。
	station.add_relic(&"decoy_straw")
	station.session.heat.reset()
	station._on_interrupted()
	_check(is_equal_approx(station.session.heat.heat, 0.0), "替身草人让打断不加热量")

	# 过热缩短：过载惩罚时长减半。
	station.add_upgrade(&"overload_shorten", 1)
	station.session.heat.reset()
	station.session.heat.add_heat(AlchemyRules.HEAT_MAX)
	_check(is_equal_approx(station.session.heat.lock_remaining, AlchemyRules.OVERLOAD_LOCKOUT * 0.5), "过热缩短把锁定减半")

	station.free()

	# ── 新接线：堆叠 / 不打断 / 必爆 / 变异 / 混沌 / 暴击 / 无敌 ──────────
	var fresh: AlchemyStation = AlchemyStation.new()
	root.add_child(fresh)
	# 堆叠上限 +20% × 3 层 → 普通材料单格 99 抬到 158。
	fresh.add_upgrade(&"stack_plus", 3)
	_check(is_equal_approx(fresh.bag.stack_multiplier, 1.6), "堆叠上限写进背包")
	fresh.bag.add(1002, 500)
	_check(int(fresh.bag.slots[0]["amount"]) == 158, "堆叠上限 +60% 把单格 99 抬到 158")

	# 炼金不打断：升级后受击不再打断蓄力。
	fresh.in_combat = true
	fresh.press_brew()
	_check(fresh.interrupt(), "默认受击会打断蓄力")
	fresh.tick(AlchemyRules.INTERRUPT_COOLDOWN + 0.1)
	fresh.press_brew()
	fresh.add_upgrade(&"brew_uninterruptible")
	_check(not fresh.interrupt(), "炼金不打断升级后受击不打断")
	_check(fresh.is_menu_open() == false, "不打断时状态机不进入冷却")
	fresh.free()

	# 火炼金必爆：火系组合强制带上爆炸词条。
	var fire_station: AlchemyStation = AlchemyStation.new()
	root.add_child(fire_station)
	fire_station.absorb_material(1006, 8)
	var plain: BrewCombo = fire_station.brew_from_slots()
	_check(_combo_has(plain, &"fire"), "火油炼出火系组合")
	_check(not _combo_has(plain, &"explode"), "默认火系组合不带爆炸")
	fire_station.add_upgrade(&"fire_guaranteed")
	fire_station.session.heat.reset()
	var forced: BrewCombo = fire_station.brew_from_slots()
	_check(_combo_has(forced, &"explode"), "火炼金必爆补上爆炸词条")

	# 随机变异：额外加一条随机词条。
	fire_station.add_upgrade(&"random_mutation")
	fire_station.session.heat.reset()
	var mutated: BrewCombo = fire_station.brew_from_slots()
	_check(mutated != null and mutated.traits.size() == forced.traits.size() + 1, "随机变异额外加一条词条")

	# 混沌石：随机把一条词条抬 1 级，数量不变。
	fire_station.add_relic(&"chaos_stone")
	fire_station.session.heat.reset()
	var leveled: BrewCombo = fire_station.brew_from_slots()
	_check(leveled != null and leveled.traits.size() == mutated.traits.size(), "混沌石不改变词条数量")
	var above_one: bool = false
	for instance: TraitInstance in leveled.traits:
		if instance.level > 1:
			above_one = true
	_check(above_one, "混沌石把随机一条词条抬到 II 级以上")

	# 暴击之眼 / 炼金无敌：对外接口。
	_check(is_equal_approx(fire_station.crit_bonus(), 0.0), "无暴击遗物时加成为 0")
	fire_station.add_relic(&"crit_eye")
	_check(is_equal_approx(fire_station.crit_bonus(), 0.15), "暴击之眼 +15%")
	_check(is_equal_approx(fire_station.invuln_seconds(), 0.0), "无炼金无敌时长为 0")
	fire_station.add_upgrade(&"brew_invuln")
	_check(is_equal_approx(fire_station.invuln_seconds(), 0.30), "炼金无敌 0.3 秒")
	fire_station.free()

	# 自动稳定剂：同一素材组合的时长按 +10% 拉长。
	var plain_station: AlchemyStation = AlchemyStation.new()
	root.add_child(plain_station)
	plain_station.absorb_material(1006, 2)
	plain_station.fill_first_free_slot(1006)
	var base_combo: BrewCombo = plain_station.brew_from_slots()
	plain_station.free()
	var stable_station: AlchemyStation = AlchemyStation.new()
	root.add_child(stable_station)
	stable_station.add_upgrade(&"auto_stabilizer")
	stable_station.absorb_material(1006, 2)
	stable_station.fill_first_free_slot(1006)
	var stable_combo: BrewCombo = stable_station.brew_from_slots()
	_check(base_combo != null and stable_combo != null, "稳定剂对比组合炼出")
	_check(is_equal_approx(stable_combo.base_duration, base_combo.base_duration * 1.10), "自动稳定剂把时长拉长 10%")
	stable_station.free()

	# 毒不伤己：毒血反应（吸血变自伤）的自伤被免掉。
	var poison_station: AlchemyStation = AlchemyStation.new()
	root.add_child(poison_station)
	poison_station.absorb_material(1001, 2)
	poison_station.absorb_material(1028, 2)
	poison_station.fill_first_free_slot(1001)
	poison_station.fill_first_free_slot(1028)
	var poison_combo: BrewCombo = poison_station.brew_from_slots()
	_check(_combo_has_reaction(poison_combo, &"toxic_blood"), "毒菇 + 血石炼出毒血反应")
	_check(poison_combo.self_damage > 0.0, "毒血反应带来自伤")
	poison_station.free()
	var safe_station: AlchemyStation = AlchemyStation.new()
	root.add_child(safe_station)
	safe_station.add_upgrade(&"poison_safe")
	safe_station.absorb_material(1001, 2)
	safe_station.absorb_material(1028, 2)
	safe_station.fill_first_free_slot(1001)
	safe_station.fill_first_free_slot(1028)
	var safe_combo: BrewCombo = safe_station.brew_from_slots()
	_check(safe_combo != null and is_equal_approx(safe_combo.self_damage, 0.0), "毒不伤己免掉毒血自伤")
	safe_station.free()

	# 快速之手：短按 E 不再有动作硬直。
	var swift: AlchemyStation = AlchemyStation.new()
	root.add_child(swift)
	_check(swift.input_state.stun_enabled, "默认短按 E 有硬直")
	swift.add_relic(&"fast_hand")
	_check(not swift.input_state.stun_enabled, "快速之手关掉短按硬直")
	swift.free()

	# 时之沙：炼金不消耗时间，激活中的效果倒计时不流逝。
	var frozen: AlchemyStation = AlchemyStation.new()
	root.add_child(frozen)
	_check(not frozen.session.freeze_duration, "默认效果倒计时会流逝")
	frozen.absorb_material(1006, 4)
	frozen.fill_first_free_slot(1006)
	var active: BrewCombo = frozen.brew_from_slots()
	_check(active != null, "时之沙用例炼出组合")
	var duration_before: float = frozen.session.duration.remaining
	frozen.in_combat = true
	frozen.tick(1.0)
	_check(frozen.session.duration.remaining < duration_before, "默认战斗中倒计时减少")
	frozen.add_relic(&"time_sand")
	_check(frozen.session.freeze_duration, "时之沙让倒计时冻结")
	var frozen_before: float = frozen.session.duration.remaining
	frozen.tick(5.0)
	_check(is_equal_approx(frozen.session.duration.remaining, frozen_before), "时之沙下倒计时不减少")
	_check(frozen.active_combo() != null, "时之沙下效果不会过期")
	frozen.free()
	print("ALCHEMY PROGRESSION: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
