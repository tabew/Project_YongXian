class_name SceneElementCatalog
extends RefCounted

## 场景元素配置表：这些元素可被长按 E 吸附，为炼金提供材料来源。
## traits 是吸附后进入词条池的词条；tags 参与材料反应配对；
## material_id 是吸附一次产出的炼金材料，必须与 traits 同族（见 tests/test_room_props.gd）。

const ELEMENTS: Array[Dictionary] = [
	{"id": &"brazier", "name": "火盆", "traits": [&"fire"], "tags": [], "material_id": 1002},
	{"id": &"poison_pool", "name": "毒池", "traits": [&"poison"], "tags": [], "material_id": 1001},
	{"id": &"iron_bar", "name": "铁栏", "traits": [&"magnet"], "tags": [&"metal"], "material_id": 1021},
	{"id": &"water_barrel", "name": "水桶", "traits": [], "tags": [&"water"], "material_id": 1015},
	{"id": &"oil_barrel", "name": "油桶", "traits": [&"fire", &"explode"], "tags": [&"oil"], "material_id": 1006},
	{"id": &"bone_pile", "name": "骨堆", "traits": [&"bone"], "tags": [], "material_id": 1003},
	{"id": &"gear_pile", "name": "齿轮堆", "traits": [&"pierce"], "tags": [&"metal", &"machine"], "material_id": 1012},
	{"id": &"ice_pillar", "name": "冰柱", "traits": [&"ice"], "tags": [], "material_id": 1005},
	{"id": &"acid_pool", "name": "酸池", "traits": [&"acid"], "tags": [], "material_id": 1004},
	{"id": &"thunder_cloud", "name": "雷云", "traits": [&"electric"], "tags": [], "material_id": 1022},
	{"id": &"vine", "name": "藤蔓", "traits": [&"duration"], "tags": [&"wood"], "material_id": 1013},
	{"id": &"mirror", "name": "镜面", "traits": [&"light"], "tags": [&"reflect"], "material_id": 1026},
	{"id": &"rift", "name": "暗裂隙", "traits": [&"dark"], "tags": [], "material_id": 1027},
	{"id": &"sand_pile", "name": "沙堆", "traits": [&"sand"], "tags": [], "material_id": 1011},
	{"id": &"blood_pool", "name": "血池", "traits": [&"blood"], "tags": [&"lifesteal"], "material_id": 1028},
	{"id": &"poison_mushroom", "name": "毒蘑菇", "traits": [&"poison"], "tags": [], "material_id": 1001},
	{"id": &"ore_vein", "name": "矿脉", "traits": [&"fire"], "tags": [], "material_id": 1002},
	{"id": &"gravestone", "name": "墓碑", "traits": [&"soul"], "tags": [], "material_id": 1023},
	{"id": &"mist", "name": "雾", "traits": [&"soul"], "tags": [&"phase"], "material_id": 1023},
	{"id": &"conveyor", "name": "传送带", "traits": [&"magnet"], "tags": [&"machine"], "material_id": 1021},
	{"id": &"conductor", "name": "导体", "traits": [&"electric"], "tags": [&"metal"], "material_id": 1022},
	{"id": &"pipe", "name": "管道", "traits": [&"acid"], "tags": [&"metal"], "material_id": 1004},
	{"id": &"ice_floor", "name": "冰面", "traits": [&"ice"], "tags": [], "material_id": 1005},
	{"id": &"lava", "name": "熔岩", "traits": [&"fire"], "tags": [], "material_id": 1002},
	{"id": &"fire_pillar", "name": "火柱", "traits": [&"fire", &"duration"], "tags": [], "material_id": 1014},
	{"id": &"sandstorm", "name": "沙暴", "traits": [&"wind"], "tags": [], "material_id": 1010},
	{"id": &"quicksand", "name": "流沙", "traits": [&"sand"], "tags": [], "material_id": 1011},
	{"id": &"tree", "name": "树木", "traits": [&"living"], "tags": [&"wood"], "material_id": 1065},
	{"id": &"altar", "name": "祭坛", "traits": [&"blood"], "tags": [], "material_id": 1028},
	{"id": &"light_pillar", "name": "光柱", "traits": [&"light"], "tags": [], "material_id": 1026},
	{"id": &"darkness", "name": "黑暗", "traits": [&"dark"], "tags": [], "material_id": 1027},
]

static var _by_id: Dictionary = {}


static func _ensure() -> void:
	if not _by_id.is_empty():
		return
	for entry: Dictionary in ELEMENTS:
		_by_id[StringName(entry["id"])] = entry


static func has_element(id: StringName) -> bool:
	_ensure()
	return _by_id.has(id)


static func definition_of(id: StringName) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})


static func name_of(id: StringName) -> String:
	return String(definition_of(id).get("name", "未知元素"))


static func traits_of(id: StringName) -> Array:
	return definition_of(id).get("traits", [])


static func tags_of(id: StringName) -> Array:
	return definition_of(id).get("tags", [])


## 吸附一次产出的炼金材料 id；未配置返回 -1。
static func material_of(id: StringName) -> int:
	return int(definition_of(id).get("material_id", -1))
