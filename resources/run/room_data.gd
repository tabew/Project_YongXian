class_name RoomData
extends RefCounted

## 单个房间的数据：类型、主题、形状、场景元素、可破坏物、敌人、门、材料与热量预算。
## 纯数据，不含节点；可在工作线程构造，UI 与生成器共享同一份结构。

var node_id: int = -1
var region_index: int = -1
var depth: int = 0
var kind: int = RoomKind.Kind.COMBAT
var theme_id: StringName = &""
var shape: int = RoomShape.Shape.OPEN
var scene_elements: Array[StringName] = []
var breakables: Array[StringName] = []
var enemy_spawns: Array[Dictionary] = []
var doors: Array[DoorInfo] = []
var material_drops: Array[Dictionary] = []
var secret_door: Dictionary = {}
## 热量预算（最小值 / 最大值），生成器按房间类型给出。
var heat_budget: Vector2 = Vector2.ZERO


func is_combat_room() -> bool:
	return RoomKind.is_combat(kind)


func decision() -> int:
	return RoomKind.decision_of(kind)


func kind_name() -> String:
	return RoomKind.name_of(kind)


func theme_name() -> String:
	return RegionThemeCatalog.name_of(theme_id)


func has_secret_door() -> bool:
	return not secret_door.is_empty()


func door_targets() -> PackedInt32Array:
	var result := PackedInt32Array()
	for door: DoorInfo in doors:
		result.append(door.to_node)
	return result


func add_door(door: DoorInfo) -> void:
	doors.append(door)


func to_dict() -> Dictionary:
	var door_dicts: Array[Dictionary] = []
	for door: DoorInfo in doors:
		door_dicts.append(door.to_dict())
	return {
		"node_id": node_id,
		"region_index": region_index,
		"depth": depth,
		"kind": kind,
		"theme": String(theme_id),
		"shape": shape,
		"scene_elements": scene_elements,
		"breakables": breakables,
		"enemy_spawns": enemy_spawns,
		"doors": door_dicts,
		"material_drops": material_drops,
		"secret_door": secret_door,
		"heat_budget": [heat_budget.x, heat_budget.y],
	}
