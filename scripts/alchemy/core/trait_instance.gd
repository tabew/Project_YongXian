class_name TraitInstance
extends RefCounted

## 词条运行时实例：词条ID、类别、等级、层数、每级数值表。
## 只描述“池子里有什么”，不承载场景节点或 UI 状态。

var id: StringName = &""
var category: int = TraitCategory.Kind.ELEMENT
var display_name: String = ""
var level: int = 1
var stacks: int = 1
## 配置里的每级数值表，索引 0 对应等级 I。
var levels: Array = []
var notes: String = ""

static func create(definition: Dictionary, trait_level: int = 1, trait_stacks: int = 1) -> TraitInstance:
	var instance: TraitInstance = TraitInstance.new()
	instance.id = definition.get("id", &"")
	instance.category = int(definition.get("category", TraitCategory.Kind.ELEMENT))
	instance.display_name = String(definition.get("name", ""))
	instance.levels = definition.get("levels", [])
	instance.notes = String(definition.get("notes", ""))
	instance.level = AlchemyRules.clamp_level(trait_level)
	instance.stacks = maxi(trait_stacks, 1)
	return instance

func duplicate_instance() -> TraitInstance:
	var copy: TraitInstance = TraitInstance.new()
	copy.id = id
	copy.category = category
	copy.display_name = display_name
	copy.levels = levels.duplicate()
	copy.notes = notes
	copy.level = level
	copy.stacks = stacks
	return copy

## 当前等级对应的数值表。
func values() -> Dictionary:
	if levels.is_empty():
		return {}
	var entry: Variant = levels[clampi(level, 1, levels.size()) - 1]
	if entry is Dictionary:
		return entry as Dictionary
	return {}

func value_of(key: StringName, fallback: float = 0.0) -> float:
	var table: Dictionary = values()
	if not table.has(key):
		return fallback
	return float(table[key])

func has_flag(key: StringName) -> bool:
	return bool(values().get(key, false))

func level_multiplier() -> float:
	return AlchemyRules.level_multiplier(level)

func stack_multiplier() -> float:
	return AlchemyRules.stack_multiplier(stacks)

## 同词条叠加：等级取最高，层数相加。
func merge(other: TraitInstance) -> void:
	level = maxi(level, other.level)
	stacks += other.stacks

func signature() -> String:
	return "%s L%d x%d" % [id, level, stacks]
