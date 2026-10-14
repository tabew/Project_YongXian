class_name DoorInfo
extends RefCounted

## 门：打完房间后出现的可选路线。
## 门显示房间类型 + 区域主题 + 材料预告 + 敌人抗性/弱点，玩家按炼金需求选路。

var from_node: int = -1
var to_node: int = -1
var room_kind: int = RoomKind.Kind.COMBAT
var theme_id: StringName = &""
var material_preview: PackedInt32Array = PackedInt32Array()
var resistance: Array[StringName] = []
var weakness: Array[StringName] = []


static func create(from_node_value: int, to_node_value: int, kind: int, theme: StringName, preview: PackedInt32Array, resist: Array[StringName], weak: Array[StringName]) -> DoorInfo:
	var door := DoorInfo.new()
	door.from_node = from_node_value
	door.to_node = to_node_value
	door.room_kind = kind
	door.theme_id = theme
	door.material_preview = preview
	door.resistance = resist
	door.weakness = weak
	return door


func room_kind_name() -> String:
	return RoomKind.name_of(room_kind)


func theme_name() -> String:
	return RegionThemeCatalog.name_of(theme_id)


func describe() -> String:
	return "%s · %s" % [room_kind_name(), theme_name()]


func to_dict() -> Dictionary:
	return {
		"from": from_node,
		"to": to_node,
		"kind": room_kind,
		"theme": String(theme_id),
		"materials": material_preview,
		"resistance": resistance,
		"weakness": weakness,
	}
