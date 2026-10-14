class_name PermanentUpgrade
extends RefCounted

## 一条永久升级的配置：等级、消耗、每级效果、前置条件与描述。

var id: StringName = &""
var name: String = ""
var max_level: int = 1
var costs: Array[int] = []
var effects: Array[float] = []
## 效果键：由工坊与炼金桥接层读取，用于把升级效果应用到炼金系统。
var effect_kind: StringName = &""
## 元素词条升级专用：指定具体元素词条。
var trait_id: StringName = &""
var prerequisite_id: StringName = &""
var prerequisite_level: int = 1
var description: String = ""


static func create(entry: Dictionary) -> PermanentUpgrade:
	var upgrade := PermanentUpgrade.new()
	upgrade.id = StringName(entry.get("id", &""))
	upgrade.name = String(entry.get("name", ""))
	upgrade.max_level = int(entry.get("max_level", 1))
	for cost: int in entry.get("costs", []):
		upgrade.costs.append(cost)
	for effect: float in entry.get("effects", []):
		upgrade.effects.append(effect)
	upgrade.effect_kind = StringName(entry.get("effect_kind", &""))
	upgrade.trait_id = StringName(entry.get("trait_id", &""))
	upgrade.prerequisite_id = StringName(entry.get("prerequisite_id", &""))
	upgrade.prerequisite_level = int(entry.get("prerequisite_level", 1))
	upgrade.description = String(entry.get("description", ""))
	return upgrade


## 升到下一级的花费；已满级返回 -1。
func cost_for_level(current_level: int) -> int:
	if current_level >= max_level:
		return -1
	return costs[clampi(current_level, 0, costs.size() - 1)]


## 升满的总花费。
func total_cost() -> int:
	var total: int = 0
	for cost: int in costs:
		total += cost
	return total


## 某一级（1 起）的单级效果值。
func effect_at_level(level: int) -> float:
	if level <= 0 or effects.is_empty():
		return 0.0
	return effects[clampi(level - 1, 0, effects.size() - 1)]


## 累计效果：前 level 级之和。
func total_effect(level: int) -> float:
	var total: float = 0.0
	for index: int in clampi(level, 0, effects.size()):
		total += effects[index]
	return total
