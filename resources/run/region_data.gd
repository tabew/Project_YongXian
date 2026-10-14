class_name RegionData
extends RefCounted

## 区域数据：一个主题下的一组房间，以及该区域的材料池与敌人池。

var index: int = 0
var theme_id: StringName = &""
var rooms: Array[RoomData] = []
var material_pool: PackedInt32Array = PackedInt32Array()
var enemy_pool: Array[StringName] = []
## 邻接表：node_id -> 可达的 node_id 数组（树状为主 + 少量环路）。
var links: Dictionary = {}


func theme_name() -> String:
	return RegionThemeCatalog.name_of(theme_id)


func room_of(node_id: int) -> RoomData:
	for room: RoomData in rooms:
		if room.node_id == node_id:
			return room
	return null


func room_count() -> int:
	return rooms.size()


## 注意：不能叫 connect，会和 Object.connect 冲突。
func link_rooms(from_node: int, to_node: int) -> void:
	_link(from_node, to_node)
	_link(to_node, from_node)


func neighbours(node_id: int) -> PackedInt32Array:
	return links.get(node_id, PackedInt32Array())


## 环路数量：边数 - 节点数 + 1（连通图的独立环数）。
func loop_count() -> int:
	var edge_total: int = 0
	for node_id: int in links:
		edge_total += (links[node_id] as PackedInt32Array).size()
	return edge_total / 2 - rooms.size() + 1


func _link(from_node: int, to_node: int) -> void:
	var current: PackedInt32Array = links.get(from_node, PackedInt32Array())
	if not current.has(to_node):
		current.append(to_node)
	links[from_node] = current


func to_dict() -> Dictionary:
	var room_dicts: Array[Dictionary] = []
	for room: RoomData in rooms:
		room_dicts.append(room.to_dict())
	return {
		"index": index,
		"theme": String(theme_id),
		"rooms": room_dicts,
		"material_pool": material_pool,
		"enemy_pool": enemy_pool,
		"links": links,
	}
