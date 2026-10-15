class_name RegionThemeCatalog
extends RefCounted

## 区域主题配置表（唯一真源）。新增主题只改这里。
## 材料 id 与 MaterialCatalog 对齐（≥1000）；元素字段用词条 id（见 resources/alchemy/trait_catalog.gd）。

const THEMES: Array[Dictionary] = [
	{
		"id": &"poison_swamp", "name": "毒沼",
		"color": Color("7bbf4a"),
		"elements": [&"poison", &"duration", &"spread"],
		"materials": [1001, 1025, 1029],
		"scene_elements": [&"poison_pool", &"poison_mushroom"],
		"resistance": [&"poison"], "weakness": [&"fire"],
	},
	{
		"id": &"mine", "name": "矿洞",
		"color": Color("c98a4b"),
		"elements": [&"fire", &"explode", &"magnet"],
		"materials": [1002, 1009, 1044],
		"scene_elements": [&"brazier", &"ore_vein", &"iron_bar"],
		"resistance": [&"fire"], "weakness": [&"electric"],
	},
	{
		"id": &"graveyard", "name": "墓地",
		"color": Color("8d93a8"),
		"elements": [&"soul", &"bone", &"dark"],
		"materials": [1003, 1023, 1045],
		"scene_elements": [&"bone_pile", &"gravestone", &"mist"],
		"resistance": [&"dark"], "weakness": [&"light"],
	},
	{
		"id": &"mechanical_ruins", "name": "机械废墟",
		"color": Color("7f8fa6"),
		"elements": [&"magnet", &"electric", &"pierce"],
		"materials": [1012, 1021, 1026],
		"scene_elements": [&"gear_pile", &"conveyor", &"iron_bar"],
		"resistance": [&"electric"], "weakness": [&"acid"],
	},
	{
		"id": &"thunder_field", "name": "雷区",
		"color": Color("e8d44a"),
		"elements": [&"electric", &"chain", &"wind"],
		"materials": [1022, 1041],
		"scene_elements": [&"thunder_cloud", &"conductor"],
		"resistance": [&"electric"], "weakness": [&"magnet"],
	},
	{
		"id": &"acid_pool", "name": "酸池",
		"color": Color("b6e04a"),
		"elements": [&"acid"],
		"materials": [1004, 1043],
		"scene_elements": [&"acid_pool", &"pipe"],
		"resistance": [&"acid"], "weakness": [],
	},
	{
		"id": &"ice_zone", "name": "冰区",
		"color": Color("6fd8ff"),
		"elements": [&"ice"],
		"materials": [1005, 1042],
		"scene_elements": [&"ice_floor", &"ice_pillar"],
		"resistance": [&"ice"], "weakness": [&"fire"],
	},
	{
		"id": &"fire_zone", "name": "火区",
		"color": Color("ff7a3c"),
		"elements": [&"fire", &"duration", &"explode"],
		"materials": [1006, 1014, 1002],
		"scene_elements": [&"lava", &"fire_pillar"],
		"resistance": [&"fire"], "weakness": [&"ice"],
	},
	{
		"id": &"desert", "name": "沙漠",
		"color": Color("e0c07a"),
		"elements": [&"sand", &"wind", &"light"],
		"materials": [1011, 1049, 1007],
		"scene_elements": [&"sandstorm", &"quicksand"],
		"resistance": [&"sand"], "weakness": [&"wind"],
	},
	{
		"id": &"forest", "name": "森林",
		"color": Color("4fbf7a"),
		"elements": [&"living"],
		"materials": [1013, 1065],
		"scene_elements": [&"vine", &"tree"],
		"resistance": [&"living"], "weakness": [&"fire"],
	},
	{
		"id": &"blood_altar", "name": "血祭坛",
		"color": Color("e04a5e"),
		"elements": [&"blood", &"curse"],
		"materials": [1028, 1047],
		"scene_elements": [&"blood_pool", &"altar"],
		"resistance": [&"blood"], "weakness": [&"light"],
	},
	{
		"id": &"light_palace", "name": "光殿",
		"color": Color("fff0b8"),
		"elements": [&"light"],
		"materials": [1026, 1050],
		"scene_elements": [&"mirror", &"light_pillar"],
		"resistance": [&"light"], "weakness": [&"dark"],
	},
	{
		"id": &"abyss", "name": "深渊",
		"color": Color("7a5cff"),
		"elements": [&"dark", &"blood", &"curse"],
		"materials": [1027, 1051],
		"scene_elements": [&"darkness", &"rift"],
		"resistance": [&"dark"], "weakness": [&"light"],
	},
]

## 最小可玩原型固定使用前两个区域。
const PROTOTYPE_THEME_IDS: Array[StringName] = [&"poison_swamp", &"mine"]

static var _by_id: Dictionary = {}


static func _ensure() -> void:
	if not _by_id.is_empty():
		return
	for entry: Dictionary in THEMES:
		_by_id[StringName(entry["id"])] = entry


static func has_theme(id: StringName) -> bool:
	_ensure()
	return _by_id.has(id)


static func ids() -> Array[StringName]:
	_ensure()
	var result: Array[StringName] = []
	for id: StringName in _by_id:
		result.append(id)
	result.sort()
	return result


static func definition_of(id: StringName) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})


static func create(id: StringName) -> RegionTheme:
	_ensure()
	var entry: Dictionary = _by_id.get(id, {})
	if entry.is_empty():
		push_warning("RegionThemeCatalog: 主题 %s 未配置" % String(id))
		return null
	return RegionTheme.create(entry)


static func name_of(id: StringName) -> String:
	return String(definition_of(id).get("name", "未知区域"))


## 主题代表色；未配置时用中性灰，保证 UI 不会拿到空值。
static func color_of(id: StringName) -> Color:
	return definition_of(id).get("color", Color(0.5, 0.5, 0.5))


static func material_ids_of(id: StringName) -> PackedInt32Array:
	var result := PackedInt32Array()
	for material_id: int in definition_of(id).get("materials", []):
		result.append(material_id)
	return result
