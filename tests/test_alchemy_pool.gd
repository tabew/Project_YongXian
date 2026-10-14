extends SceneTree

## 词条池计算单元测试：收集 → 叠加 → 反应 → 冲突 → 上限裁剪 → 效果标签。

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

func _materials(ids: Array[int]) -> Array[AlchemyMaterial]:
	var result: Array[AlchemyMaterial] = []
	for material_id: int in ids:
		result.append(MaterialCatalog.create(material_id, 1))
	return result

func _pool(ids: Array[int], limit: int = AlchemyRules.POOL_LIMIT_PROTOTYPE) -> TraitPoolResult:
	return TraitPool.build(_materials(ids), limit)

func _run() -> void:
	_test_collect()
	_test_stack()
	_test_reactions()
	_test_conflicts()
	_test_limit()
	_test_effect_tags()
	_test_unknown_material()
	print("ALCHEMY POOL: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_collect() -> void:
	var pool: TraitPoolResult = _pool([1002])
	_check(pool.traits.size() == 2, "硝石收集到 2 个词条")
	_check(pool.has_trait(&"fire") and pool.has_trait(&"explode"), "硝石带来火与爆炸")
	_check(pool.quality == AlchemyMaterial.Quality.COMMON, "品质取素材最高品质")
	_check(pool.reactions.is_empty() and pool.conflicts.is_empty(), "单个材料不产生反应")

func _test_stack() -> void:
	var pool: TraitPoolResult = _pool([1002, 1006])
	var fire: TraitInstance = pool.trait_of(&"fire")
	_check(fire != null, "硝石 + 火油 里有火")
	_check(fire.stacks == 2, "两份火叠加成 2 层")
	_check(fire.level == 1, "同等级叠加后仍是 I")
	_check(is_equal_approx(fire.stack_multiplier(), 1.5), "2 层叠加倍率 1.5")

	var high: TraitPoolResult = _pool([1002, 1061])
	var strong: TraitInstance = high.trait_of(&"fire")
	_check(strong.level == 4, "硝石 I + 龙血 IV 取最高等级 IV")
	_check(strong.stacks == 2, "跨等级叠加层数仍相加")
	_check(high.quality == AlchemyMaterial.Quality.LEGENDARY, "含传说材料时品质取传说")

func _test_reactions() -> void:
	var smoke: TraitPoolResult = _pool([1002, 1001])
	_check(smoke.reactions.size() == 1, "火 + 毒 命中 1 个反应")
	_check(smoke.reactions[0]["id"] == &"poison_smoke", "火 + 毒 = 毒烟")
	_check(int(smoke.reactions[0]["level"]) == 1, "毒烟等级取平均")
	_check(smoke.conflicts.is_empty(), "毒烟不是冲突")

	var steam: TraitPoolResult = _pool([1002, 1005])
	_check(steam.reactions[0]["id"] == &"steam_burst", "火 + 冰 = 蒸汽爆炸")
	_check(int(steam.reactions[0]["level"]) == 1, "蒸汽爆炸等级取最高")

	var field: TraitPoolResult = _pool([1022, 1021])
	var field_found: bool = false
	for reaction: Dictionary in field.reactions:
		if reaction["id"] == &"magnetic_field":
			field_found = true
			_check(int(reaction["level"]) == 2, "磁场拉拽取平均等级 II")
	_check(field_found, "电 + 磁 = 磁场拉拽")

	var corrode: TraitPoolResult = _pool([1004, 1021])
	_check(corrode.has_tag(&"metal"), "水银把金属标签带进池子")
	_check(corrode.reactions[0]["id"] == &"corrosive_sunder", "酸 + 金属 = 腐蚀破甲")
	_check(int(corrode.reactions[0]["level"]) == 1, "腐蚀破甲取酸等级")

func _test_conflicts() -> void:
	var ice_fire: TraitPoolResult = _pool([1002, 1005])
	_check(ice_fire.conflicts.size() == 1, "火 + 冰 触发 1 个反噬")
	_check(ice_fire.conflicts[0]["name"] == "冰火反噬", "反噬名称正确")
	_check(ice_fire.self_damage_per_second() > 0.0, "反噬带来每秒自伤")

	var annihilation: TraitPoolResult = _pool([1066])
	_check(annihilation.reactions.size() == 1 and annihilation.reactions[0]["id"] == &"annihilation", "光 + 暗 = 湮灭")
	_check(int(annihilation.reactions[0]["level"]) == 4, "湮灭取最高等级")
	_check(annihilation.conflicts.size() == 1, "光 + 暗 同时反噬")

func _test_limit() -> void:
	var wide: Array[int] = [1002, 1001, 1003, 1006]
	var limited: TraitPoolResult = _pool(wide, 3)
	_check(limited.traits.size() == 3, "词条池按上限裁到 3 条")
	_check(not limited.dropped.is_empty(), "被裁掉的词条记入 dropped")
	_check(limited.traits.size() + limited.dropped.size() >= 4, "裁剪只是移出，不丢失数据")
	# 元素优先：裁剪后仍保留元素词条。
	var has_element: bool = false
	for trait_instance: TraitInstance in limited.traits:
		has_element = has_element or trait_instance.category == TraitCategory.Kind.ELEMENT
	_check(has_element, "裁剪优先保留元素词条")

func _test_effect_tags() -> void:
	var pool: TraitPoolResult = _pool([1002, 1001])
	var expected: Array[StringName] = [&"fire", &"poison", &"poison_smoke"]
	_check(pool.effect_tags == expected, "效果标签 = 元素词条 + 反应，排序去重")
	var spark: TraitPoolResult = _pool([1022])
	var marrow: TraitPoolResult = _pool([1041])
	_check(spark.effect_tags == marrow.effect_tags, "同元素不同材料视为同一组合")
	_check(spark.effect_tags == [&"electric"], "行为词条不进效果标签")
	var oily: TraitPoolResult = _pool([1006, 1001])
	_check(oily.effect_tags.has(&"deflagration"), "火油带油标签，触发爆燃反应")
	var different: TraitPoolResult = _pool([1002, 1005])
	_check(different.effect_tags != expected, "换元素会改变效果标签")

func _test_unknown_material() -> void:
	var materials: Array[AlchemyMaterial] = [null, MaterialCatalog.create(9999, 1)]
	var pool: TraitPoolResult = TraitPool.build(materials, AlchemyRules.POOL_LIMIT_PROTOTYPE)
	_check(pool.is_empty(), "空材料与未知材料不产生词条")
