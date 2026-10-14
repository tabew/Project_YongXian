class_name BreakableCatalog
extends RefCounted

## 可破坏物配置表：打碎后掉对应材料。生成器按区域主题挑选。

const BREAKABLES: Array[Dictionary] = [
	{"id": &"wooden_crate", "name": "木箱", "material_id": 1013},
	{"id": &"ore_vein", "name": "矿脉", "material_id": 1002},
	{"id": &"lime_rock", "name": "石灰岩", "material_id": 1009},
	{"id": &"poison_mushroom", "name": "毒菇", "material_id": 1001},
	{"id": &"bone_pile", "name": "骨堆", "material_id": 1003},
	{"id": &"gear_pile", "name": "齿轮堆", "material_id": 1012},
	{"id": &"ice_crystal", "name": "冰晶簇", "material_id": 1005},
	{"id": &"acid_crust", "name": "酸蚀壳", "material_id": 1004},
	{"id": &"mirror_shard", "name": "镜片堆", "material_id": 1026},
	{"id": &"blood_stone", "name": "血石堆", "material_id": 1028},
]

## 区域主题 → 可破坏物候选。
const THEME_BREAKABLES: Dictionary = {
	&"poison_swamp": [&"poison_mushroom", &"wooden_crate"],
	&"mine": [&"ore_vein", &"lime_rock", &"wooden_crate"],
	&"graveyard": [&"bone_pile", &"wooden_crate"],
	&"mechanical_ruins": [&"gear_pile", &"wooden_crate"],
	&"thunder_field": [&"gear_pile", &"ore_vein"],
	&"acid_pool": [&"acid_crust", &"lime_rock"],
	&"ice_zone": [&"ice_crystal", &"lime_rock"],
	&"fire_zone": [&"ore_vein", &"lime_rock"],
	&"desert": [&"lime_rock", &"wooden_crate"],
	&"forest": [&"wooden_crate", &"poison_mushroom"],
	&"blood_altar": [&"blood_stone", &"bone_pile"],
	&"light_palace": [&"mirror_shard", &"lime_rock"],
	&"abyss": [&"blood_stone", &"bone_pile"],
}

static var _by_id: Dictionary = {}


static func _ensure() -> void:
	if not _by_id.is_empty():
		return
	for entry: Dictionary in BREAKABLES:
		_by_id[StringName(entry["id"])] = entry


static func has_breakable(id: StringName) -> bool:
	_ensure()
	return _by_id.has(id)


static func definition_of(id: StringName) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})


static func material_of(id: StringName) -> int:
	return int(definition_of(id).get("material_id", -1))


static func candidates_for(theme_id: StringName) -> Array:
	return THEME_BREAKABLES.get(theme_id, [&"wooden_crate"])
