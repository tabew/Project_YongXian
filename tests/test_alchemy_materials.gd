extends SceneTree

## 炼金材料的世界产出：群系 / Boss 房产出表、世界物品注册、吸附半径与悬浮表现。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _ids_of(pool: Array[Dictionary]) -> Array[int]:
	var ids: Array[int] = []
	for entry: Dictionary in pool:
		ids.append(int(entry["id"]))
	return ids


## 物品注册表是 autoload（uid 注册），测试里按节点取，避免直接引用全局标识符。
func _template_of(material_id: int) -> IngredientData:
	var item_list: Node = root.get_node_or_null("ItemListGlobal")
	if item_list == null:
		return null
	return item_list.call("get_template", material_id) as IngredientData


func _run() -> void:
	# 产出表：id 必须是合法炼金材料，深海等无群系不刷材料。
	_check(not AlchemyMaterialSources.BIOME_TABLE.is_empty(), "群系产出表非空")
	_check(AlchemyMaterialSources.all_source_ids().size() >= 20, "产出表覆盖足够多的材料")
	for material_id: int in AlchemyMaterialSources.all_source_ids():
		_check(MaterialCatalog.has_material(material_id), "产出表 id %d 是合法炼金材料" % material_id)
	_check(not AlchemyMaterialSources.BIOME_TABLE.has(Biome.Kind.DEEP_OCEAN), "深海不刷炼金材料")
	_check(AlchemyMaterialSources.ROOM_TABLE.has(RoomType.Kind.BOSS), "Boss 房有独立产出表")

	# 传说材料只从 Boss 房出。
	var biome_ids: Array[int] = []
	for entries: Array in AlchemyMaterialSources.BIOME_TABLE.values():
		for entry: Dictionary in entries:
			biome_ids.append(int(entry["id"]))
	var boss_ids: Array[int] = []
	for entry: Dictionary in AlchemyMaterialSources.ROOM_TABLE[RoomType.Kind.BOSS]:
		boss_ids.append(int(entry["id"]))
	for legendary: int in [1061, 1062, 1063, 1064, 1066]:
		_check(not biome_ids.has(legendary), "传说材料 %d 不出现在群系表" % legendary)
		_check(boss_ids.has(legendary), "传说材料 %d 出现在 Boss 表" % legendary)

	# Boss 材料：品质档位 Boss，只在 Boss 表出现，品质修正高于传说。
	_check(MaterialCatalog.BOSS_IDS.size() >= 4, "Boss 材料至少 4 种")
	var boss_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	boss_rng.seed = 4242
	for boss_id: int in MaterialCatalog.BOSS_IDS:
		_check(MaterialCatalog.has_material(boss_id), "Boss 材料 %d 在配置表里" % boss_id)
		_check(MaterialCatalog.is_boss_material(boss_id), "Boss 材料 %d 标记为 Boss" % boss_id)
		_check(not biome_ids.has(boss_id), "Boss 材料 %d 不出现在群系表" % boss_id)
		_check(boss_ids.has(boss_id), "Boss 材料 %d 出现在 Boss 表" % boss_id)
		_check(AlchemyMaterialSources.amount_for(boss_id, boss_rng) == 1, "Boss 材料 %d 固定掉 1" % boss_id)
		var boss_material: AlchemyMaterial = MaterialCatalog.create(boss_id, 1)
		_check(boss_material != null and boss_material.quality == AlchemyMaterial.Quality.BOSS, "Boss 材料 %d 品质为 Boss" % boss_id)
		_check(boss_material.quality_name() == "Boss", "Boss 材料品质名")
	_check(not MaterialCatalog.is_boss_material(1061), "传说材料不是 Boss 材料")
	_check(not MaterialCatalog.is_boss_material(1001), "普通材料不是 Boss 材料")
	_check(AlchemyRules.quality_multiplier(AlchemyMaterial.Quality.BOSS) > AlchemyRules.quality_multiplier(AlchemyMaterial.Quality.LEGENDARY), "Boss 品质修正高于传说")

	# 灵感结算桥接：Boss 材料单独计数，其余按品质计数。
	var settlement: Dictionary = MaterialCatalog.settlement_counts([1001, 1001, 1021, 1061, 1071, 1072, 9999])
	var settlement_counts: Dictionary = settlement["counts"]
	_check(int(settlement_counts.get(0, 0)) == 2, "结算把普通材料计 2")
	_check(int(settlement_counts.get(1, 0)) == 1, "结算把稀有材料计 1")
	_check(int(settlement_counts.get(3, 0)) == 1, "结算把传说材料计 1")
	_check(int(settlement_counts.get(AlchemyMaterial.Quality.BOSS, 0)) == 0, "Boss 材料不进品质表")
	_check(int(settlement["boss_count"]) == 2, "结算单独统计 Boss 材料")
	_check(InspirationRules.material_conversion(settlement_counts, int(settlement["boss_count"])) \
		== InspirationRules.material_value(0) * 2 + InspirationRules.material_value(1) \
		+ InspirationRules.material_value(3) + InspirationRules.BOSS_MATERIAL_VALUE * 2,
		"结算转化值 = 品质转化 + Boss 材料 200/个")

	# 世界物品注册：每个炼金材料都能按 id 取到模板与图标。
	var item_list: Node = root.get_node_or_null("ItemListGlobal")
	_check(item_list != null, "物品注册表可用")
	for material_id: int in MaterialCatalog.all_ids():
		var template: IngredientData = _template_of(material_id)
		_check(template != null and template.texture != null, "材料 %d 已注册世界物品" % material_id)
	_check(AlchemyMaterialItems.template_of(1001) == AlchemyMaterialItems.template_of(1001), "同一材料复用同一模板")
	_check(AlchemyMaterialItems.template_of(2) == null, "石头不是炼金材料模板")
	_check(AlchemyMaterialItems.QUALITY_BORDER_COLORS.size() == 5, "五档品质描边色（含 Boss）")
	_check(AlchemyMaterialItems.QUALITY_BORDER_COLORS[0] != AlchemyMaterialItems.QUALITY_BORDER_COLORS[3], "品质描边色可区分")
	_check(AlchemyMaterialItems.hue_color(1001) == AlchemyMaterialItems.hue_color(1001), "材料主色稳定")
	_check(AlchemyMaterialItems.hue_color(1001) != AlchemyMaterialItems.hue_color(1002), "不同材料主色不同")

	# 世界 id → 炼金材料 id：正式材料恒等，旧材料走桥接表。
	_check(MaterialCatalog.material_id_for_world(1001) == 1001, "正式材料恒等映射")
	_check(MaterialCatalog.material_id_for_world(1021) == 1021, "稀有水银恒等映射")
	_check(MaterialCatalog.material_id_for_world(2) == 1002, "旧石头仍走桥接表")
	_check(MaterialCatalog.material_id_for_world(9999) == -1, "未知 id 返回 -1")

	# 抽样表：石头 / 木棍 + 本群系材料；Boss 房覆盖群系表。
	var spec: MapSpec = MapSpec.new()
	spec.biome_id = Biome.Kind.SWAMP
	var pool: Array[Dictionary] = GroundMaterials._material_pool(spec)
	var pool_ids: Array[int] = _ids_of(pool)
	_check(pool.size() == 2 + AlchemyMaterialSources.BIOME_TABLE[Biome.Kind.SWAMP].size(), "抽样表 = 石头 / 木棍 + 群系材料")
	_check(pool_ids.has(GroundMaterials.STONE_ID), "抽样表含石头")
	_check(pool_ids.has(GroundMaterials.STICK_ID), "抽样表含木棍")
	_check(pool_ids.has(1001), "沼泽抽样表含毒菇")
	var boss_spec: MapSpec = MapSpec.new()
	boss_spec.biome_id = Biome.Kind.SWAMP
	boss_spec.room_kind = RoomType.Kind.BOSS
	var boss_pool_ids: Array[int] = _ids_of(GroundMaterials._material_pool(boss_spec))
	_check(boss_pool_ids.has(1061) and not boss_pool_ids.has(1001), "Boss 房用传说材料表覆盖群系表")

	# 掉落数量：普通 1~3、稀有 1~2、史诗 / 传说与石头固定 1。
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	_check(AlchemyMaterialSources.amount_for(GroundMaterials.STONE_ID, rng) == 1, "石头固定掉 1")
	_check(AlchemyMaterialSources.amount_for(1061, rng) == 1, "传说材料固定掉 1")
	_check(AlchemyMaterialSources.amount_for(1041, rng) == 1, "史诗材料固定掉 1")
	var common_max: int = 0
	var common_min: int = 99
	for _index: int in range(40):
		var amount: int = AlchemyMaterialSources.amount_for(1001, rng)
		common_max = maxi(common_max, amount)
		common_min = mini(common_min, amount)
	_check(common_min >= 1 and common_max <= 3, "普通材料掉 1~3")
	var picked: Dictionary = GroundMaterials._pick(rng, pool)
	_check(pool_ids.has(int(picked["id"])), "抽到的材料来自抽样表")
	_check(int(picked["amount"]) >= 1, "掉落数量至少 1")

	# 兜底：保证石头 / 木棍与群系材料各至少一条。
	var result: Array[Dictionary] = []
	for _index: int in range(6):
		result.append({"tile": Vector2i.ZERO, "item_id": 1002, "amount": 1})
	GroundMaterials._ensure_required(result, pool, rng)
	_check(GroundMaterials._contains_id(result, GroundMaterials.STONE_ID), "兜底补上石头")
	_check(GroundMaterials._contains_id(result, GroundMaterials.STICK_ID), "兜底补上木棍")
	_check(GroundMaterials._contains_id(result, 1001), "兜底补上群系材料")

	# 吸附半径：基础 3 格，磁词条按等级扩大。
	var station: AlchemyStation = AlchemyStation.new()
	root.add_child(station)
	await process_frame
	_check(station.adsorb_radius_tiles() == AlchemyRules.BASE_ADSORB_RADIUS_TILES, "无磁词条时为基础半径")
	_check(station.adsorb_radius_pixels() == AlchemyRules.BASE_ADSORB_RADIUS_TILES * float(WorldGenerator.TILE_SIZE), "像素半径按格换算")
	station.absorb_material(1021, 2)
	station.brew_from_slots()
	_check(station.active_combo() != null, "水银炼金成功")
	_check(station.adsorb_radius_tiles() == AlchemyRules.BASE_ADSORB_RADIUS_TILES + 2.0, "磁词条 II 级 +2 格")

	# 材料悬浮：炼金材料会悬浮，石头不会。
	var alchemy_pickup: GroundPickup = GroundPickup.new()
	alchemy_pickup.bind(_template_of(1001), 1)
	root.add_child(alchemy_pickup)
	await process_frame
	_check(alchemy_pickup.is_alchemy_material(), "炼金材料可识别")
	_check(alchemy_pickup._float_tween != null, "炼金材料有悬浮动画")
	var stone_pickup: GroundPickup = GroundPickup.new()
	stone_pickup.bind(_template_of(GroundMaterials.STONE_ID), 1)
	root.add_child(stone_pickup)
	await process_frame
	_check(not stone_pickup.is_alchemy_material(), "石头不是炼金材料")
	_check(stone_pickup._float_tween == null, "石头没有悬浮动画")

	Engine.time_scale = 1.0
	paused = false
	alchemy_pickup.free()
	stone_pickup.free()
	station.free()
	print("ALCHEMY MATERIALS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
