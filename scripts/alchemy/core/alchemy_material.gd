class_name AlchemyMaterial
extends RefCounted

## 材料运行时数据：材料ID、品质、词条列表、堆叠数量。
## 模板由 MaterialCatalog 提供，运行时只保留一份可消耗的数量。

enum Quality { COMMON = 0, RARE = 1, EPIC = 2, LEGENDARY = 3, BOSS = 4 }

const QUALITY_NAMES: Dictionary = {
	Quality.COMMON: "普通",
	Quality.RARE: "稀有",
	Quality.EPIC: "史诗",
	Quality.LEGENDARY: "传说",
	Quality.BOSS: "Boss",
}

var id: int = 0
var display_name: String = ""
var quality: int = Quality.COMMON
## 词条条目：[{"id": StringName, "level": int}]
var trait_entries: Array[Dictionary] = []
## 额外标签（金属 / 机械 / 油 / 木…），和元素词条一起参与反应与冲突判定。
var tags: Array[StringName] = []
var amount: int = 1
var max_stack: int = 99

static func create(definition: Dictionary, quantity: int = 1) -> AlchemyMaterial:
	var material: AlchemyMaterial = AlchemyMaterial.new()
	material.id = int(definition.get("id", 0))
	material.display_name = String(definition.get("name", ""))
	material.quality = int(definition.get("quality", Quality.COMMON))
	material.max_stack = int(definition.get("max_stack", 99))
	for entry: Dictionary in definition.get("traits", []):
		material.trait_entries.append(entry.duplicate())
	for tag: StringName in definition.get("tags", []):
		material.tags.append(tag)
	material.amount = clampi(quantity, 1, maxi(material.max_stack, 1))
	return material

func quality_name() -> String:
	return QUALITY_NAMES.get(quality, "未知")

func trait_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for entry: Dictionary in trait_entries:
		result.append(entry.get("id", &""))
	return result

## 该材料为某词条提供的等级；没有该词条返回 0。
func trait_level(trait_id: StringName) -> int:
	for entry: Dictionary in trait_entries:
		if entry.get("id", &"") == trait_id:
			return int(entry.get("level", 1))
	return 0

func has_tag(tag: StringName) -> bool:
	return tags.has(tag)

func duplicate_material() -> AlchemyMaterial:
	var copy: AlchemyMaterial = AlchemyMaterial.new()
	copy.id = id
	copy.display_name = display_name
	copy.quality = quality
	copy.tags = tags.duplicate()
	copy.amount = amount
	copy.max_stack = max_stack
	for entry: Dictionary in trait_entries:
		copy.trait_entries.append(entry.duplicate())
	return copy
