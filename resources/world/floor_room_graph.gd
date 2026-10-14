class_name FloorRoomGraph
extends RoomGraph

## 把局内地图（FloorData：层 → 区域 → 房间）适配成 WorldGenerator 认识的房间图。
##
## 编号规则：深度 = 房间在「区域顺序 + 区域内顺序」上的线性序号（跨区域连续递增），
## 于是每条向前的边都从浅到深，世界生成器可以继续沿用旧的「层 × 2 + 变体」编号。
## 普通房间占变体 0；秘密房与宿主同深度，占变体 1（世界生成器会把它摆到主线上下方）。
##
## 房间类型由 RunMapGenerator 决定（纯逻辑、可单测）；本类只做编号与类型翻译，
## 并保留「世界编号 ↔ 房间数据」的双向表，供 UI 与运行时查询。

## 新房间类型 → 旧 RoomType：世界生成器按旧类型挑区域模板。
const KIND_TO_LEGACY: Dictionary = {
	RoomKind.Kind.COMBAT: RoomType.Kind.COMBAT,
	RoomKind.Kind.ELITE: RoomType.Kind.COMBAT,
	RoomKind.Kind.BOSS: RoomType.Kind.BOSS,
	RoomKind.Kind.EVENT: RoomType.Kind.EVENT,
	RoomKind.Kind.SHOP: RoomType.Kind.SHOP,
	RoomKind.Kind.TREASURE: RoomType.Kind.REWARD,
	RoomKind.Kind.ALCHEMY: RoomType.Kind.REST,
	RoomKind.Kind.REST: RoomType.Kind.REST,
	RoomKind.Kind.CHALLENGE: RoomType.Kind.COMBAT,
	RoomKind.Kind.SECRET: RoomType.Kind.REWARD,
}

## 区域主题 → 生物群系：主题决定地形调色板，与旧群系表一一对应。
const THEME_BIOME: Dictionary = {
	&"poison_swamp": Biome.Kind.SWAMP,
	&"mine": Biome.Kind.ALPINE,
	&"graveyard": Biome.Kind.TAIGA,
	&"mechanical_ruins": Biome.Kind.GRASSLAND,
	&"thunder_field": Biome.Kind.SAVANNA,
	&"acid_pool": Biome.Kind.TUNDRA,
	&"ice_zone": Biome.Kind.SNOWY_PLAINS,
	&"fire_zone": Biome.Kind.MOUNTAIN,
	&"desert": Biome.Kind.DESERT,
	&"forest": Biome.Kind.FOREST,
	&"blood_altar": Biome.Kind.TROPICAL_RAINFOREST,
	&"light_palace": Biome.Kind.GRASSLAND,
	&"abyss": Biome.Kind.TAIGA,
}

## 本图对应的局内地图。
var floor: FloorData = null
## 世界 node_id -> FloorData node_id。
var _data_node_of_world: Dictionary = {}
## FloorData node_id -> 世界 node_id。
var _world_node_of_data: Dictionary = {}
## 世界 node_id -> RoomData。
var _room_of_world: Dictionary = {}
## 世界 node_id -> Biome.Kind。
var _biome_of_world: Dictionary = {}
## 世界宿主 node_id -> 同层秘密房的世界 node_id。
var _secret_children: Dictionary = {}


## 从一层局内地图规划骨架；不调用旧的 _build_plan()。
static func plan_from_floor(source: FloorData, map_config: MapConfig = null, seed_value: int = 0) -> FloorRoomGraph:
	var graph := FloorRoomGraph.new()
	graph.floor = source
	graph.config = map_config if map_config != null else MapConfig.new()
	graph.plan_seed = seed_value
	graph.planned_from_floor = true
	graph._build_from_floor()
	return graph


## 世界 node_id 对应的完整房间数据；越界返回 null。
func room_data(world_node_id: int) -> RoomData:
	return _room_of_world.get(world_node_id, null)


func biome_of(node_id: int) -> int:
	return int(_biome_of_world.get(node_id, -1))


func kind_name_of(node_id: int) -> String:
	var room: RoomData = room_data(node_id)
	return room.kind_name() if room != null else RoomType.name_of(type_of(node_id))


func data_node_of(node_id: int) -> int:
	return int(_data_node_of_world.get(node_id, -1))


func world_node_of(data_node_id: int) -> int:
	return int(_world_node_of_data.get(data_node_id, -1))


## 局内地图的文字描述（供调试与 HUD 使用）。
func describe_rooms() -> String:
	return RunMapGenerator.describe(floor)


## 进入房间时的提示文字：房间类型 + 区域主题。
func describe(node_id: int) -> String:
	var room: RoomData = room_data(node_id)
	if room == null:
		return "未知房间"
	return "%s · %s" % [room.kind_name(), room.theme_name()]


## 房间类型缩写序列，按深度顺序；调试与批量统计用。
func rhythm() -> PackedStringArray:
	var result := PackedStringArray()
	for depth: int in floors.size():
		for node_id: int in floors[depth]:
			var room: RoomData = room_data(node_id)
			result.append(room.kind_name() if room != null else "?")
	return result


# ------------------------------------------------------------ 构建

func _build_from_floor() -> void:
	floors.clear()
	next_nodes.clear()
	types.clear()
	key_nodes.clear()
	main_path.clear()
	branch_nodes.clear()
	_data_node_of_world.clear()
	_world_node_of_data.clear()
	_room_of_world.clear()
	_biome_of_world.clear()
	_secret_children.clear()
	if floor == null or floor.rooms.is_empty():
		return

	var depths: Dictionary = _assign_depths()
	var max_depth: int = 0
	for data_node: int in depths:
		max_depth = maxi(max_depth, int(depths[data_node]))
	for depth: int in max_depth + 1:
		floors.append(PackedInt32Array())

	# 深度优先按 node_id 排序，保证同深度内变体编号稳定、可复现。
	var ordered: Array[int] = []
	for data_node: int in depths:
		ordered.append(data_node)
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var depth_a: int = int(depths[a])
		var depth_b: int = int(depths[b])
		return depth_a < depth_b if depth_a != depth_b else a < b
	)
	for data_node: int in ordered:
		var depth: int = int(depths[data_node])
		var ids: PackedInt32Array = floors[depth]
		var world_id: int = RunGraph.node_id(depth, ids.size())
		ids.append(world_id)
		floors[depth] = ids
		_register(world_id, data_node, floor.room_of(data_node))

	_index_secret_children()
	_build_links()
	_collect_floor_keys()


## 深度 = 区域顺序 + 区域内部顺序。秘密房与宿主同深度，排在宿主之后。
func _assign_depths() -> Dictionary:
	var depths: Dictionary = {}
	var cursor: int = 0
	for region: RegionData in floor.regions:
		for room: RoomData in region.rooms:
			if room.kind == RoomKind.Kind.SECRET:
				continue
			depths[room.node_id] = cursor
			cursor += 1
	if floor.boss_room != null:
		depths[floor.boss_room.node_id] = cursor
	# 秘密房与宿主同深度；宿主缺失时退到最深一层。
	for room: RoomData in floor.rooms:
		if room.kind != RoomKind.Kind.SECRET:
			continue
		var host: int = _secret_host(room)
		depths[room.node_id] = int(depths.get(host, cursor))
	return depths


## 秘密房的宿主：生成器把秘密房挂在宿主上，两者互为唯一邻居。
func _secret_host(room: RoomData) -> int:
	var neighbours: PackedInt32Array = floor.neighbours(room.node_id)
	for neighbour: int in neighbours:
		if neighbour != room.node_id:
			return neighbour
	return -1


func _register(world_id: int, data_node: int, room: RoomData) -> void:
	_data_node_of_world[world_id] = data_node
	_world_node_of_data[data_node] = world_id
	_room_of_world[world_id] = room
	if room == null:
		return
	types[world_id] = int(KIND_TO_LEGACY.get(room.kind, RoomType.Kind.COMBAT))
	_biome_of_world[world_id] = int(THEME_BIOME.get(room.theme_id, Biome.Kind.FOREST))


## 秘密房没有普通门：把宿主 -> 秘密房登记下来，世界层的宿主出口要留一格给它。
func _index_secret_children() -> void:
	for room: RoomData in floor.rooms:
		if room.kind != RoomKind.Kind.SECRET:
			continue
		var host: int = world_node_of(_secret_host(room))
		var secret: int = world_node_of(room.node_id)
		if host < 0 or secret < 0:
			continue
		var children: PackedInt32Array = _secret_children.get(host, PackedInt32Array())
		children.append(secret)
		_secret_children[host] = children


## 只保留向前的边：世界生成器的出口是单向推进的，回程由物理门自身双向处理。
## 秘密房与宿主同层，是唯一的例外：它是宿主的一条侧门，必须由宿主开出来，
## 否则它永远不可达（旧骨架里这一格由"同层岔路"承担）。
func _build_links() -> void:
	for world_id: int in _room_of_world:
		var room: RoomData = _room_of_world[world_id]
		var targets := PackedInt32Array()
		var depth: int = RunGraph.floor_of(world_id)
		if room != null:
			for door: DoorInfo in room.doors:
				var target: int = world_node_of(door.to_node)
				if target >= 0 and RunGraph.floor_of(target) > depth and not targets.has(target):
					targets.append(target)
		for secret: int in _secret_children.get(world_id, PackedInt32Array()):
			if not targets.has(secret):
				targets.append(secret)
		# 秘密房自身回落到宿主，避免被判成死路。
		if targets.is_empty() and room != null and room.kind == RoomKind.Kind.SECRET:
			var host: int = world_node_of(_secret_host(room))
			if host >= 0:
				targets.append(host)
		next_nodes[world_id] = targets


## 主线 = 每个深度的变体 0；变体 1 是秘密房，算作岔路。
func _collect_floor_keys() -> void:
	for depth: int in floors.size():
		var ids: PackedInt32Array = floors[depth]
		if ids.is_empty():
			continue
		main_path.append(ids[0])
		if ids.size() > 1:
			branch_nodes.append(ids[1])
	for kind: int in RoomType.KEY_KINDS:
		key_nodes[kind] = PackedInt32Array()
	for node_id: int in types.keys():
		var kind: int = types[node_id]
		if not RoomType.is_key(kind):
			continue
		var list: PackedInt32Array = key_nodes[kind]
		list.append(node_id)
		key_nodes[kind] = list
