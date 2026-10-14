extends SceneTree

## 词条图鉴：未发现占位、发现记录、完成度、数值摘要、存档往返与炼金台自动登记。

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
	_test_catalog_shape()
	_test_unknown_placeholders()
	_test_discovery()
	_test_completion()
	_test_describe()
	_test_serialization()
	_test_station_records()
	print("ALCHEMY COMPENDIUM: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_catalog_shape() -> void:
	_check(TraitCatalog.TRAITS.size() == 38, "词条总数 38（元素 13 / 行为 9 / 触发 8 / 修饰 8）")
	_check(ReactionCatalog.REACTIONS.size() == 32, "反应总数 32")
	_check(AlchemyCompendium.new().total_entries() == 70, "图鉴总条目 = 38 词条 + 32 反应")


func _test_unknown_placeholders() -> void:
	var book: AlchemyCompendium = AlchemyCompendium.new()
	var elements: Array[Dictionary] = book.entries_of(AlchemyCompendium.Section.ELEMENT)
	_check(elements.size() == 13, "元素栏 13 条")
	for entry: Dictionary in elements:
		_check(not entry["discovered"], "未发现：discovered 为假")
		_check(entry["name"] == AlchemyCompendium.UNKNOWN_TEXT, "未发现显示「？？？」")
		_check(entry["effect"] == "", "未发现不显示效果")
	var reactions: Array[Dictionary] = book.entries_of(AlchemyCompendium.Section.REACTION)
	_check(reactions.size() == 32, "反应栏 32 条")
	_check(reactions[0]["name"] == AlchemyCompendium.UNKNOWN_TEXT, "未发现反应显示「？？？」")
	_check(book.entries_of(AlchemyCompendium.Section.MATERIAL).size() == MaterialCatalog.all_ids().size(),
		"材料栏覆盖全部材料")


func _test_discovery() -> void:
	var book: AlchemyCompendium = AlchemyCompendium.new()
	_check(not book.is_trait_discovered(&"fire"), "初始未发现火")
	_check(book.trait_level_seen(&"fire") == 0, "未发现等级为 0")
	_check(book.discover_trait(&"fire", 2), "首次发现火 II 记为新增")
	_check(book.is_trait_discovered(&"fire"), "火已发现")
	_check(book.trait_level_seen(&"fire") == 2, "记录火 II")
	_check(not book.discover_trait(&"fire", 1), "更低等级不刷新记录")
	_check(book.trait_level_seen(&"fire") == 2, "等级保持 II")
	_check(book.discover_trait(&"fire", 5), "更高等级刷新记录")
	_check(book.trait_level_seen(&"fire") == 5, "等级升到 V")
	_check(not book.discover_trait(&"", 3), "空 id 不记录")
	_check(book.discover_reaction(&"poison_smoke"), "发现毒烟")
	_check(not book.discover_reaction(&"poison_smoke"), "重复发现不重复计数")
	_check(book.discover_conflict("冰火反噬"), "发现冲突")
	_check(book.discover_material(1002), "发现硝石")
	var entry: Dictionary = book.entries_of(AlchemyCompendium.Section.ELEMENT)[0]
	_check(entry["discovered"] and entry["name"] == "火" and entry["level"] == 5, "已发现元素显示名称与等级")
	_check(String(entry["effect"]).contains("伤害 18"), "已发现元素显示 V 级效果")


func _test_completion() -> void:
	var book: AlchemyCompendium = AlchemyCompendium.new()
	_check(is_zero_approx(book.completion_ratio()), "初始完成度 0")
	for definition: Dictionary in TraitCatalog.TRAITS:
		book.discover_trait(definition.get("id", &""), 1)
	_check(book.discovered_count() == 38, "发现全部词条后计数 38")
	_check(is_equal_approx(book.completion_ratio(), 38.0 / 70.0), "完成度 = 38/70")
	for reaction: Dictionary in ReactionCatalog.REACTIONS:
		book.discover_reaction(reaction.get("id", &""))
	_check(book.discovered_count() == 70, "词条 + 反应全发现计数 70")
	_check(is_equal_approx(book.completion_ratio(), 1.0), "全发现完成度 100%")
	book.reset()
	_check(book.discovered_count() == 0 and is_zero_approx(book.completion_ratio()), "reset 清空图鉴")


func _test_describe() -> void:
	var fire: Dictionary = TraitCatalog.definition_of(&"fire")
	var fire_v: String = AlchemyCompendium.describe_level(fire, 5)
	_check(fire_v.contains("伤害 18"), "火 V 伤害 18")
	_check(fire_v.contains("点燃 25%"), "火 V 点燃 25%")
	_check(fire_v.contains("时长 5s"), "火 V 时长 5s")
	_check(fire_v.contains("留火焰地面"), "火 V 标记留火焰地面")
	var duration: Dictionary = TraitCatalog.definition_of(&"duration")
	_check(AlchemyCompendium.describe_level(duration, 1).contains("时长 +20%"), "持续 I 显示 +20%")
	_check(AlchemyCompendium.describe_level(duration, 5).contains("可刷新"), "持续 V 显示可刷新")
	var pierce: Dictionary = TraitCatalog.definition_of(&"pierce")
	var pierce_i: String = AlchemyCompendium.describe_level(pierce, 1)
	_check(pierce_i.contains("穿透 1"), "穿透 I 次数 1")
	_check(pierce_i.contains("伤害衰减 -30%"), "穿透 I 衰减 -30%")
	var soul: Dictionary = TraitCatalog.definition_of(&"soul")
	_check(AlchemyCompendium.describe_level(soul, 1).contains("生成率 5%"), "灵魂 I 生成率 5%")
	_check(AlchemyCompendium.describe_level(fire, 99).contains("伤害 18"), "超界等级按最高级裁剪")


func _test_serialization() -> void:
	var book: AlchemyCompendium = AlchemyCompendium.new()
	book.discover_trait(&"ice", 3)
	book.discover_trait(&"acid", 1)
	book.discover_reaction(&"steam_burst")
	book.discover_conflict("光暗湮灭")
	book.discover_material(1005)
	var restored: AlchemyCompendium = AlchemyCompendium.new()
	restored.from_dict(book.to_dict())
	_check(restored.trait_level_seen(&"ice") == 3, "存档保留冰 III")
	_check(restored.trait_level_seen(&"acid") == 1, "存档保留酸 I")
	_check(restored.is_reaction_discovered(&"steam_burst"), "存档保留反应")
	_check(restored.discovered_conflicts.has("光暗湮灭"), "存档保留冲突")
	_check(restored.is_material_discovered(1005), "存档保留材料")
	_check(is_equal_approx(restored.completion_ratio(), book.completion_ratio()), "存档往返完成度一致")


func _test_station_records() -> void:
	var station: AlchemyStation = AlchemyStation.new()
	station.setup()
	# GDScript 的 lambda 按值捕获局部变量，用数组承载计数才能被回调改写。
	var changes: Array[int] = [0]
	station.compendium_changed.connect(func() -> void: changes[0] += 1)
	station.absorb_material(1002, 4)
	station.absorb_material(1001, 4)
	var combo: BrewCombo = station.brew_from_slots()
	_check(combo != null, "炼金成功")
	_check(changes[0] == 1, "有新发现时发一次 compendium_changed")
	_check(station.compendium.is_material_discovered(1002), "登记硝石")
	_check(station.compendium.is_material_discovered(1001), "登记毒菇")
	_check(station.compendium.is_trait_discovered(&"fire"), "登记火")
	_check(station.compendium.is_trait_discovered(&"poison"), "登记毒")
	_check(station.compendium.is_trait_discovered(&"explode"), "登记爆炸")
	_check(station.compendium.is_reaction_discovered(&"poison_smoke"), "火 + 毒登记毒烟反应")
	_check(station.compendium.completion_ratio() > 0.0, "完成度大于 0")
	station.free()
