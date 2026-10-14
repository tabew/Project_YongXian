class_name RegionTheme
extends RefCounted

## 区域主题：决定敌人、场景元素与材料掉落。
## 所有主题配置集中在 RegionThemeCatalog，本类只提供只读查询。

var id: StringName = &""
var name: String = ""
var element_traits: Array[StringName] = []
var material_ids: PackedInt32Array = PackedInt32Array()
var scene_elements: Array[StringName] = []
var resistance: Array[StringName] = []
var weakness: Array[StringName] = []


static func create(entry: Dictionary) -> RegionTheme:
	var theme := RegionTheme.new()
	theme.id = StringName(entry.get("id", &""))
	theme.name = String(entry.get("name", ""))
	for trait_id: StringName in entry.get("elements", []):
		theme.element_traits.append(trait_id)
	for material_id: int in entry.get("materials", []):
		theme.material_ids.append(material_id)
	for element: StringName in entry.get("scene_elements", []):
		theme.scene_elements.append(element)
	for element: StringName in entry.get("resistance", []):
		theme.resistance.append(element)
	for element: StringName in entry.get("weakness", []):
		theme.weakness.append(element)
	return theme


func material_preview(count: int = 3) -> Array[int]:
	var result: Array[int] = []
	for index: int in mini(count, material_ids.size()):
		result.append(material_ids[index])
	return result


func describe_resistance() -> String:
	if resistance.is_empty():
		return "无"
	return "、".join(_trait_names(resistance))


func describe_weakness() -> String:
	if weakness.is_empty():
		return "无"
	return "、".join(_trait_names(weakness))


func _trait_names(ids: Array[StringName]) -> PackedStringArray:
	var result := PackedStringArray()
	for id: StringName in ids:
		result.append(String(id))
	return result
