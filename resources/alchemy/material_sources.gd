class_name AlchemyMaterialSources
extends RefCounted

## 炼金材料的产出表（唯一真源）：按群系 / 房间类型决定地面刷出哪些正式材料。
##
## 每条 {"id": 材料 id, "weight": 权重}；品质决定单次掉落数量（普通 1~3、稀有 1~2、更高 1）。
## 新增材料来源只改这里，GroundMaterials 会自动把权重并入石头 / 木棍的同一张抽样表。

const BIOME_TABLE: Dictionary = {
	# 毒沼：毒菇 / 孢子 / 毒腺 / 酸液 / 酸胆
	Biome.Kind.SWAMP: [
		{"id": 1001, "weight": 6}, {"id": 1025, "weight": 3}, {"id": 1029, "weight": 2},
		{"id": 1004, "weight": 4}, {"id": 1043, "weight": 1},
		{"id": 1003, "weight": 3}, {"id": 1023, "weight": 2}, {"id": 1045, "weight": 1},
		{"id": 1028, "weight": 2}, {"id": 1047, "weight": 1},
	],
	# 山地：硝石 / 石灰 / 水银 / 雷石 / 磁石 / 雷髓
	Biome.Kind.MOUNTAIN: [
		{"id": 1002, "weight": 6}, {"id": 1009, "weight": 4}, {"id": 1021, "weight": 2},
		{"id": 1022, "weight": 3}, {"id": 1044, "weight": 2}, {"id": 1041, "weight": 1},
		{"id": 1010, "weight": 2},
	],
	# 雪峰：硝石 / 磁石 / 雷髓 / 龙骨
	Biome.Kind.ALPINE: [
		{"id": 1002, "weight": 4}, {"id": 1044, "weight": 2}, {"id": 1041, "weight": 1},
		{"id": 1022, "weight": 2}, {"id": 1046, "weight": 1},
	],
	# 苔原：冰晶 / 幽灵尘 / 骨粉 / 灵魂石 / 暗晶 / 冰核 / 龙骨
	Biome.Kind.TUNDRA: [
		{"id": 1005, "weight": 6}, {"id": 1023, "weight": 3}, {"id": 1003, "weight": 4},
		{"id": 1045, "weight": 1}, {"id": 1027, "weight": 2}, {"id": 1042, "weight": 2},
		{"id": 1046, "weight": 1}, {"id": 1051, "weight": 1}, {"id": 1015, "weight": 3},
	],
	# 雪原：冰晶 / 冰核 / 镜片 / 光核
	Biome.Kind.SNOWY_PLAINS: [
		{"id": 1005, "weight": 6}, {"id": 1042, "weight": 2}, {"id": 1026, "weight": 3},
		{"id": 1050, "weight": 1},
	],
	# 针叶林：藤蔓 / 冰晶 / 暗晶 / 暗核
	Biome.Kind.TAIGA: [
		{"id": 1013, "weight": 6}, {"id": 1005, "weight": 3}, {"id": 1027, "weight": 2},
		{"id": 1051, "weight": 1},
	],
	# 森林：藤蔓 / 火绒 / 肾上腺素 / 血石 / 世界树皮
	Biome.Kind.FOREST: [
		{"id": 1013, "weight": 6}, {"id": 1014, "weight": 4}, {"id": 1024, "weight": 2},
		{"id": 1028, "weight": 2}, {"id": 1065, "weight": 1}, {"id": 1008, "weight": 3},
	],
	# 雨林：藤蔓 / 毒菇 / 孢子 / 毒腺
	Biome.Kind.TROPICAL_RAINFOREST: [
		{"id": 1013, "weight": 6}, {"id": 1001, "weight": 4}, {"id": 1025, "weight": 2},
		{"id": 1029, "weight": 2},
	],
	# 草原：藤蔓 / 火绒 / 黏土 / 风羽 / 风灵 / 肾上腺素
	Biome.Kind.GRASSLAND: [
		{"id": 1013, "weight": 5}, {"id": 1014, "weight": 3}, {"id": 1008, "weight": 4},
		{"id": 1010, "weight": 3}, {"id": 1048, "weight": 1}, {"id": 1024, "weight": 2},
	],
	# 稀树草原：沙砾 / 藤蔓 / 火绒 / 风羽 / 风灵
	Biome.Kind.SAVANNA: [
		{"id": 1011, "weight": 5}, {"id": 1013, "weight": 4}, {"id": 1014, "weight": 3},
		{"id": 1010, "weight": 3}, {"id": 1048, "weight": 1},
	],
	# 沙漠：沙砾 / 玻璃 / 火油 / 硝石 / 沙皇
	Biome.Kind.DESERT: [
		{"id": 1011, "weight": 6}, {"id": 1007, "weight": 3}, {"id": 1006, "weight": 4},
		{"id": 1002, "weight": 3}, {"id": 1049, "weight": 1},
	],
	# 海岸：沙砾 / 玻璃 / 石灰 / 齿轮 / 水银 / 镜片
	Biome.Kind.BEACH: [
		{"id": 1011, "weight": 5}, {"id": 1007, "weight": 2}, {"id": 1009, "weight": 3},
		{"id": 1012, "weight": 3}, {"id": 1021, "weight": 2}, {"id": 1026, "weight": 2},
		{"id": 1008, "weight": 3}, {"id": 1015, "weight": 4},
	],
}

## 房间类型覆盖表：Boss 房刷 Boss 材料与传说材料，替代群系表。
const ROOM_TABLE: Dictionary = {
	RoomType.Kind.BOSS: [
		{"id": 1071, "weight": 2}, {"id": 1072, "weight": 2}, {"id": 1073, "weight": 2},
		{"id": 1074, "weight": 2},
		{"id": 1061, "weight": 1}, {"id": 1062, "weight": 1}, {"id": 1063, "weight": 1},
		{"id": 1064, "weight": 1}, {"id": 1066, "weight": 1},
	],
}


## 该区域的炼金材料权重表；没有配置时返回空（只刷石头 / 木棍）。
static func pool_for(spec: MapSpec) -> Array:
	if spec == null:
		return []
	if ROOM_TABLE.has(spec.room_kind):
		return ROOM_TABLE[spec.room_kind]
	return BIOME_TABLE.get(spec.biome_id, [])


## 表里出现过的全部材料 id（测试与图鉴用）。
static func all_source_ids() -> Array[int]:
	var ids: Array[int] = []
	for table: Dictionary in [BIOME_TABLE, ROOM_TABLE]:
		for entries: Array in table.values():
			for entry: Dictionary in entries:
				var material_id: int = int(entry["id"])
				if not ids.has(material_id):
					ids.append(material_id)
	ids.sort()
	return ids


## 单次掉落数量：普通材料 1~3、稀有 1~2、史诗 / 传说 / Boss 1；非炼金材料（石头 / 木棍）固定 1。
static func amount_for(material_id: int, rng: RandomNumberGenerator) -> int:
	if not MaterialCatalog.has_material(material_id):
		return 1
	var quality: int = int(MaterialCatalog.definition_of(material_id).get("quality", 0))
	match quality:
		0:
			return rng.randi_range(1, 3)
		1:
			return rng.randi_range(1, 2)
	return 1
