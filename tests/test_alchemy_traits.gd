extends SceneTree

## 词条 / 材料数据结构与配置表单元测试。
## 覆盖：38 条词条分类、等级倍率、叠加倍率、词条实例、材料模板、反应表配对。

const ELEMENT_COUNT: int = 13
const BEHAVIOR_COUNT: int = 9
const TRIGGER_COUNT: int = 8
const MODIFIER_COUNT: int = 8

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
	_test_catalog()
	_test_multipliers()
	_test_instance()
	_test_materials()
	_test_reaction_table()
	print("ALCHEMY TRAITS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_catalog() -> void:
	_check(TraitCatalog.all_ids().size() == 38, "词条表共 38 条")
	_check(TraitCatalog.ids_of_category(TraitCategory.Kind.ELEMENT).size() == ELEMENT_COUNT, "元素词条 13 个")
	_check(TraitCatalog.ids_of_category(TraitCategory.Kind.BEHAVIOR).size() == BEHAVIOR_COUNT, "行为词条 9 个")
	_check(TraitCatalog.ids_of_category(TraitCategory.Kind.TRIGGER).size() == TRIGGER_COUNT, "触发词条 8 个")
	_check(TraitCatalog.ids_of_category(TraitCategory.Kind.MODIFIER).size() == MODIFIER_COUNT, "修饰词条 8 个")
	for trait_id: StringName in TraitCatalog.all_ids():
		var definition: Dictionary = TraitCatalog.definition_of(trait_id)
		var levels: Array = definition.get("levels", [])
		_check(levels.size() == AlchemyRules.MAX_TRAIT_LEVEL, "%s 有 5 级数值" % trait_id)
		_check(not String(definition.get("name", "")).is_empty(), "%s 有中文名" % trait_id)
	for trait_id: StringName in TraitCatalog.PROTOTYPE_IDS:
		_check(TraitCatalog.has_trait(trait_id), "原型词条 %s 已配置" % trait_id)
	_check(TraitCatalog.create(&"not_a_trait") == null, "未知词条不会造出实例")

func _test_multipliers() -> void:
	_check(AlchemyRules.level_multiplier(1) == 1.0, "等级 I 倍率 1.0")
	_check(AlchemyRules.level_multiplier(2) == 1.3, "等级 II 倍率 1.3")
	_check(AlchemyRules.level_multiplier(3) == 1.6, "等级 III 倍率 1.6")
	_check(AlchemyRules.level_multiplier(4) == 2.0, "等级 IV 倍率 2.0")
	_check(AlchemyRules.level_multiplier(5) == 2.5, "等级 V 倍率 2.5")
	_check(AlchemyRules.stack_multiplier(1) == 1.0, "1 层倍率 1.0")
	_check(AlchemyRules.stack_multiplier(2) == 1.5, "2 层倍率 1.5")
	_check(AlchemyRules.stack_multiplier(3) == 1.75, "3 层倍率 1.75")
	_check(AlchemyRules.stack_multiplier(4) == 1.85, "4 层倍率 1.85")
	_check(AlchemyRules.stack_multiplier(5) == 1.9, "5 层倍率 1.9")
	_check(AlchemyRules.stack_multiplier(9) == 1.9, "5 层以上不再增加")
	_check(AlchemyRules.quality_multiplier(0) == 1.0, "普通品质修正 1.0")
	_check(AlchemyRules.quality_multiplier(3) == 1.5, "传说品质修正 1.5")

func _test_instance() -> void:
	var fire: TraitInstance = TraitCatalog.create(&"fire", 4, 2)
	_check(fire.id == &"fire" and fire.category == TraitCategory.Kind.ELEMENT, "火属于元素类")
	_check(fire.level == 4 and fire.stacks == 2, "等级与层数按参数写入")
	_check(fire.value_of(&"damage") == 12.0, "火 IV 附加伤害 12")
	_check(fire.value_of(&"ignite") == 0.20, "火 IV 点燃 20%")
	_check(fire.has_flag(&"spread"), "火 IV 起扩散")
	_check(not fire.has_flag(&"ground"), "火 IV 不留火焰地面")
	_check(fire.value_of(&"missing", 7.5) == 7.5, "缺失键返回兜底值")
	_check(fire.level_multiplier() == 2.0 and fire.stack_multiplier() == 1.5, "实例倍率取等级与层数")

	var merged: TraitInstance = TraitCatalog.create(&"fire", 2, 1)
	merged.merge(TraitCatalog.create(&"fire", 5, 3))
	_check(merged.level == 5, "叠加时等级取最高")
	_check(merged.stacks == 4, "叠加时层数相加")

	var high: TraitInstance = TraitCatalog.create(&"fire", 99)
	_check(high.level == AlchemyRules.MAX_TRAIT_LEVEL, "等级超过 V 会被夹到 V")

func _test_materials() -> void:
	var mushroom: AlchemyMaterial = MaterialCatalog.create(1001, 3)
	_check(mushroom != null and mushroom.display_name == "毒菇", "毒菇模板可造实例")
	_check(mushroom.quality == AlchemyMaterial.Quality.COMMON, "毒菇是普通材料")
	_check(mushroom.max_stack == 99 and mushroom.amount == 3, "毒菇堆叠上限与数量正确")
	_check(mushroom.trait_ids() == [&"poison", &"duration", &"spread"], "毒菇词条为毒 / 持续 / 扩散")
	_check(mushroom.trait_level(&"poison") == 1, "毒菇提供毒 I")
	_check(mushroom.trait_level(&"fire") == 0, "毒菇不提供火")

	var mercury: AlchemyMaterial = MaterialCatalog.create(1021, 1)
	_check(mercury.quality == AlchemyMaterial.Quality.RARE, "水银是稀有材料")
	_check(mercury.trait_level(&"magnet") == 2, "水银提供磁 II")
	_check(mercury.has_tag(&"metal"), "水银带金属标签")

	var gear: AlchemyMaterial = MaterialCatalog.create(1012, 1)
	_check(gear.has_tag(&"machine") and gear.has_tag(&"metal"), "齿轮带机械与金属标签")

	var over: AlchemyMaterial = MaterialCatalog.create(1001, 500)
	_check(over.amount == 99, "数量不会超过堆叠上限")
	_check(MaterialCatalog.create(9999) == null, "未知材料返回 null")
	_check(MaterialCatalog.display_name_of(1061) == "龙血", "传说材料名称可查")

	for material_id: int in MaterialCatalog.PROTOTYPE_IDS:
		_check(MaterialCatalog.has_material(material_id), "原型材料 %d 已配置" % material_id)
	for material_id: int in MaterialCatalog.all_ids():
		var definition: Dictionary = MaterialCatalog.definition_of(material_id)
		for entry: Dictionary in definition.get("traits", []):
			_check(TraitCatalog.has_trait(entry.get("id", &"")), "材料 %d 的词条 %s 在词条表里" % [material_id, entry.get("id", &"")])

func _test_reaction_table() -> void:
	_check(ReactionCatalog.pair_key(&"fire", &"ice") == ReactionCatalog.pair_key(&"ice", &"fire"), "配对键与顺序无关")
	_check(not ReactionCatalog.reaction_of(&"fire", &"poison").is_empty(), "火 + 毒 有反应")
	_check(ReactionCatalog.reaction_of(&"fire", &"water").is_empty(), "未配置的组合没有反应")
	_check(not ReactionCatalog.conflict_of(&"fire", &"ice").is_empty(), "火 + 冰 是冲突")
	_check(not ReactionCatalog.reaction_of(&"fire", &"ice").is_empty(), "火 + 冰 同时有反应")
	_check(ReactionCatalog.reaction_level(&"average", 1, 3) == 2, "平均等级取中值")
	_check(ReactionCatalog.reaction_level(&"max", 1, 3) == 3, "最高等级取大值")
	_check(ReactionCatalog.reaction_level(&"min", 1, 3) == 1, "最低等级取小值")
	_check(ReactionCatalog.reaction_level(&"a", 4, 1) == 4, "指定一侧取 a")
	_check(ReactionCatalog.all_reactions().size() == 32, "反应表共 32 条")
	_check(ReactionCatalog.all_conflicts().size() == 4, "冲突表共 4 条")
	for reaction_id: StringName in ReactionCatalog.PROTOTYPE_REACTION_IDS:
		var found: bool = false
		for entry: Dictionary in ReactionCatalog.all_reactions():
			found = found or entry.get("id", &"") == reaction_id
		_check(found, "原型反应 %s 已配置" % reaction_id)
