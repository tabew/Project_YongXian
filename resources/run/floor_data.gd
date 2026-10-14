class_name FloorData
extends RefCounted

## 一层楼：若干区域 + 一个 Boss 房。

var floor_index: int = 0
var regions: Array[RegionData] = []
var boss_room: RoomData = null
## 层内所有房间（含 Boss），node_id 全层唯一。
var rooms: Array[RoomData] = []
## 邻接表：跨区域连接也记录在这里。
var links: Dictionary = {}


func room_of(node_id: int) -> RoomData:
	for room: RoomData in rooms:
		if room.node_id == node_id:
			return room
	return null


func region_of(node_id: int) -> RegionData:
	for region: RegionData in regions:
		for room: RoomData in region.rooms:
			if room.node_id == node_id:
				return region
	return null


func start_room() -> RoomData:
	if regions.is_empty() or regions[0].rooms.is_empty():
		return null
	return regions[0].rooms[0]


func room_count() -> int:
	return rooms.size()


## 注意：不能叫 connect，会和 Object.connect 冲突。
func link_rooms(from_node: int, to_node: int) -> void:
	_link(from_node, to_node)
	_link(to_node, from_node)


func neighbours(node_id: int) -> PackedInt32Array:
	return links.get(node_id, PackedInt32Array())


## 广度优先：从起点可达的所有房间 node_id。
func reachable_from(node_id: int) -> PackedInt32Array:
	var visited := PackedInt32Array()
	var queue: Array[int] = [node_id]
	var seen: Dictionary = {node_id: true}
	while not queue.is_empty():
		var current: int = queue.pop_front()
		visited.append(current)
		for next_node: int in neighbours(current):
			if not seen.has(next_node):
				seen[next_node] = true
				queue.append(next_node)
	return visited


func is_fully_connected() -> bool:
	if rooms.is_empty():
		return true
	return reachable_from(rooms[0].node_id).size() == rooms.size()


func _link(from_node: int, to_node: int) -> void:
	var current: PackedInt32Array = links.get(from_node, PackedInt32Array())
	if not current.has(to_node):
		current.append(to_node)
	links[from_node] = current


func to_dict() -> Dictionary:
	var region_dicts: Array[Dictionary] = []
	for region: RegionData in regions:
		region_dicts.append(region.to_dict())
	return {
		"floor_index": floor_index,
		"regions": region_dicts,
		"boss_room": boss_room.to_dict() if boss_room != null else {},
		"links": links,
	}
