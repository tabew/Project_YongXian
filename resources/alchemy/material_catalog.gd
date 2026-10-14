class_name MaterialCatalog
extends RefCounted

## 材料配置表（唯一真源）。新增材料只改这里：id / 名称 / 品质 / 词条 / 标签 / 堆叠上限。
## 材料 id 从 1000 起，避开 ItemListGlobal 已用的 1~4 与 300+ 药水段。

const MATERIALS: Array[Dictionary] = [
	# ── 普通材料（堆叠 99，词条 I~II）──
	{"id": 1001, "name": "毒菇", "quality": 0, "max_stack": 99,
		"traits": [{"id": &"poison", "level": 1}, {"id": &"duration", "level": 1}, {"id": &"spread", "level": 1}]},
	{"id": 1002, "name": "硝石", "quality": 0, "max_stack": 99,
		"traits": [{"id": &"fire", "level": 1}, {"id": &"explode", "level": 1}]},
	{"id": 1003, "name": "骨粉", "quality": 0, "max_stack": 99,
		"traits": [{"id": &"bone", "level": 1}, {"id": &"bounce", "level": 1}, {"id": &"pierce", "level": 1}]},
	{"id": 1004, "name": "酸液", "quality": 0, "max_stack": 99,
		"traits": [{"id": &"acid", "level": 1}]},
	{"id": 1005, "name": "冰晶", "quality": 0, "max_stack": 99,
		"traits": [{"id": &"ice", "level": 1}]},
	{"id": 1006, "name": "火油", "quality": 0, "max_stack": 99, "tags": [&"oil"],
		"traits": [{"id": &"fire", "level": 1}, {"id": &"duration", "level": 1}, {"id": &"spread", "level": 1}]},
	{"id": 1007, "name": "玻璃", "quality": 0, "max_stack": 99, "tags": [&"thorns"],
		"traits": [{"id": &"sharp", "level": 1}, {"id": &"fragile", "level": 1}]},
	{"id": 1008, "name": "黏土", "quality": 0, "max_stack": 99,
		"traits": [{"id": &"heavy", "level": 1}, {"id": &"spread", "level": 1}, {"id": &"stability", "level": 1}]},
	{"id": 1009, "name": "石灰", "quality": 0, "max_stack": 99, "tags": [&"neutral"],
		"traits": [{"id": &"stability", "level": 1}, {"id": &"duration", "level": 1}]},
	{"id": 1010, "name": "风羽", "quality": 0, "max_stack": 99,
		"traits": [{"id": &"wind", "level": 1}]},
	{"id": 1011, "name": "沙砾", "quality": 0, "max_stack": 99,
		"traits": [{"id": &"sand", "level": 1}, {"id": &"spread", "level": 1}]},
	{"id": 1012, "name": "齿轮", "quality": 0, "max_stack": 99, "tags": [&"metal", &"machine"],
		"traits": [{"id": &"pierce", "level": 1}, {"id": &"bounce", "level": 1}]},
	{"id": 1013, "name": "藤蔓", "quality": 0, "max_stack": 99, "tags": [&"wood"],
		"traits": [{"id": &"duration", "level": 1}]},
	{"id": 1014, "name": "火绒", "quality": 0, "max_stack": 99, "tags": [&"oil"],
		"traits": [{"id": &"fire", "level": 1}, {"id": &"duration", "level": 1}, {"id": &"spread", "level": 1}]},
	{"id": 1015, "name": "潮汐盐", "quality": 0, "max_stack": 99, "tags": [&"water"],
		"traits": [{"id": &"stability", "level": 1}, {"id": &"duration", "level": 1}]},

	# ── 稀有材料（堆叠 20，词条 II~III）──
	{"id": 1021, "name": "水银", "quality": 1, "max_stack": 20, "tags": [&"metal"],
		"traits": [{"id": &"magnet", "level": 2}, {"id": &"transform", "level": 2}, {"id": &"pierce", "level": 2}]},
	{"id": 1022, "name": "雷石", "quality": 1, "max_stack": 20,
		"traits": [{"id": &"electric", "level": 2}, {"id": &"chain", "level": 2}]},
	{"id": 1023, "name": "幽灵尘", "quality": 1, "max_stack": 20, "tags": [&"phase"],
		"traits": [{"id": &"soul", "level": 2}, {"id": &"pierce", "level": 2}]},
	{"id": 1024, "name": "肾上腺素", "quality": 1, "max_stack": 20, "tags": [&"haste", &"self_harm"],
		"traits": [{"id": &"overload", "level": 2}]},
	{"id": 1025, "name": "孢子", "quality": 1, "max_stack": 20,
		"traits": [{"id": &"poison", "level": 2}, {"id": &"summon", "level": 2}]},
	{"id": 1026, "name": "镜片", "quality": 1, "max_stack": 20, "tags": [&"reflect"],
		"traits": [{"id": &"light", "level": 2}, {"id": &"sharp", "level": 2}]},
	{"id": 1027, "name": "暗晶", "quality": 1, "max_stack": 20,
		"traits": [{"id": &"dark", "level": 2}, {"id": &"curse", "level": 2}]},
	{"id": 1028, "name": "血石", "quality": 1, "max_stack": 20, "tags": [&"lifesteal"],
		"traits": [{"id": &"blood", "level": 2}]},
	{"id": 1029, "name": "毒腺", "quality": 1, "max_stack": 20,
		"traits": [{"id": &"poison", "level": 2}, {"id": &"spread", "level": 2}, {"id": &"duration", "level": 2}]},

	# ── 史诗材料（堆叠 10，词条 III~IV）──
	{"id": 1041, "name": "雷髓", "quality": 2, "max_stack": 10,
		"traits": [{"id": &"electric", "level": 3}, {"id": &"chain", "level": 3}]},
	{"id": 1042, "name": "冰核", "quality": 2, "max_stack": 10,
		"traits": [{"id": &"ice", "level": 3}]},
	{"id": 1043, "name": "酸胆", "quality": 2, "max_stack": 10,
		"traits": [{"id": &"acid", "level": 3}]},
	{"id": 1044, "name": "磁石", "quality": 2, "max_stack": 10, "tags": [&"metal"],
		"traits": [{"id": &"magnet", "level": 3}]},
	{"id": 1045, "name": "灵魂石", "quality": 2, "max_stack": 10,
		"traits": [{"id": &"soul", "level": 3}, {"id": &"summon", "level": 3}]},
	{"id": 1046, "name": "龙骨", "quality": 2, "max_stack": 10,
		"traits": [{"id": &"bone", "level": 3}, {"id": &"summon", "level": 3}]},
	{"id": 1047, "name": "血髓", "quality": 2, "max_stack": 10,
		"traits": [{"id": &"blood", "level": 3}]},
	{"id": 1048, "name": "风灵", "quality": 2, "max_stack": 10,
		"traits": [{"id": &"wind", "level": 3}]},
	{"id": 1049, "name": "沙皇", "quality": 2, "max_stack": 10,
		"traits": [{"id": &"sand", "level": 3}, {"id": &"spread", "level": 3}]},
	{"id": 1050, "name": "光核", "quality": 2, "max_stack": 10,
		"traits": [{"id": &"light", "level": 3}]},
	{"id": 1051, "name": "暗核", "quality": 2, "max_stack": 10,
		"traits": [{"id": &"dark", "level": 3}, {"id": &"curse", "level": 3}]},

	# ── 传说材料（堆叠 5，词条 IV~V）──
	{"id": 1061, "name": "龙血", "quality": 3, "max_stack": 5,
		"traits": [{"id": &"fire", "level": 4}, {"id": &"living", "level": 4}]},
	{"id": 1062, "name": "时之沙", "quality": 3, "max_stack": 5, "tags": [&"time"],
		"traits": [{"id": &"duration", "level": 4}]},
	{"id": 1063, "name": "空间碎片", "quality": 3, "max_stack": 5, "tags": [&"space"],
		"traits": [{"id": &"pierce", "level": 4}, {"id": &"transform", "level": 4}]},
	{"id": 1064, "name": "混沌石", "quality": 3, "max_stack": 5, "tags": [&"random"],
		"traits": [{"id": &"curse", "level": 4}]},
	{"id": 1065, "name": "世界树皮", "quality": 3, "max_stack": 5, "tags": [&"wood"],
		"traits": [{"id": &"living", "level": 4}]},
	{"id": 1066, "name": "湮灭尘", "quality": 3, "max_stack": 5,
		"traits": [{"id": &"light", "level": 4}, {"id": &"dark", "level": 4}]},

	# ── Boss 材料（堆叠 3，词条 V 级 + 专属标签；只从 Boss 掉落）──
	{"id": 1071, "name": "熔火之心", "quality": 4, "max_stack": 3, "tags": [&"oil", &"boss"],
		"traits": [{"id": &"fire", "level": 5}, {"id": &"explode", "level": 4}, {"id": &"living", "level": 3}]},
	{"id": 1072, "name": "腐殖之母", "quality": 4, "max_stack": 3, "tags": [&"boss"],
		"traits": [{"id": &"poison", "level": 5}, {"id": &"summon", "level": 4}, {"id": &"blood", "level": 3}]},
	{"id": 1073, "name": "雷狱之核", "quality": 4, "max_stack": 3, "tags": [&"metal", &"machine", &"boss"],
		"traits": [{"id": &"electric", "level": 5}, {"id": &"chain", "level": 4}, {"id": &"magnet", "level": 3}]},
	{"id": 1074, "name": "虚无之种", "quality": 4, "max_stack": 3, "tags": [&"boss"],
		"traits": [{"id": &"dark", "level": 5}, {"id": &"soul", "level": 4}, {"id": &"curse", "level": 3}]},
]

## Boss 材料 id：只由 Boss 掉落，品质档位为 Quality.BOSS。
const BOSS_IDS: Array[int] = [1071, 1072, 1073, 1074]

## 最小可玩原型的 8 种材料：毒菇 / 硝石 / 骨粉 / 水银 / 雷石 / 酸液 / 冰晶 / 火油。
const PROTOTYPE_IDS: Array[int] = [1001, 1002, 1003, 1004, 1005, 1006, 1021, 1022]

## 旧世界材料 id（ItemListGlobal 的 1~4 号）→ 炼金材料 id 的兼容桥接表。
## 正式炼金材料按群系刷新后直接以自身 id（≥1000）落地，不再走这张表。
const WORLD_MATERIAL_BRIDGE: Dictionary = {
	2: 1002,  # 石头 → 硝石
	3: 1006,  # 木棍 → 火油
	4: 1003,  # 给毛 → 骨粉
	5: 1001,  # 猴皮 → 毒菇
}

static var _by_id: Dictionary = {}

static func _ensure_table() -> void:
	if not _by_id.is_empty():
		return
	for entry: Dictionary in MATERIALS:
		_by_id[int(entry["id"])] = entry

static func has_material(id: int) -> bool:
	_ensure_table()
	return _by_id.has(id)

## 是否 Boss 材料（品质档位 Boss，只由 Boss 掉落）。
static func is_boss_material(id: int) -> bool:
	return quality_of(id) >= AlchemyRules.BOSS_QUALITY


static func quality_of(id: int) -> int:
	return int(definition_of(id).get("quality", 0))


## 把材料 id 列表折算成灵感结算需要的 {quality: 数量} 与 Boss 材料数量。
## Boss 材料单独计数，不重复计入品质表。
static func settlement_counts(material_ids: Array[int]) -> Dictionary:
	var counts: Dictionary = {}
	var boss_count: int = 0
	for material_id: int in material_ids:
		if not has_material(material_id):
			continue
		if is_boss_material(material_id):
			boss_count += 1
			continue
		var quality: int = quality_of(material_id)
		counts[quality] = int(counts.get(quality, 0)) + 1
	return {"counts": counts, "boss_count": boss_count}

## 世界材料 id 对应的炼金材料 id：正式材料（≥1000）是恒等映射，旧材料走桥接表，其余返回 -1。
static func material_id_for_world(world_id: int) -> int:
	_ensure_table()
	if _by_id.has(world_id):
		return world_id
	return int(WORLD_MATERIAL_BRIDGE.get(world_id, -1))

static func definition_of(id: int) -> Dictionary:
	_ensure_table()
	return _by_id.get(id, {})

static func create(id: int, quantity: int = 1) -> AlchemyMaterial:
	_ensure_table()
	if not _by_id.has(id):
		return null
	return AlchemyMaterial.create(_by_id[id], quantity)

static func all_ids() -> Array[int]:
	_ensure_table()
	var ids: Array[int] = []
	for id: int in _by_id:
		ids.append(id)
	ids.sort()
	return ids

static func display_name_of(id: int) -> String:
	return String(definition_of(id).get("name", "未知材料"))
