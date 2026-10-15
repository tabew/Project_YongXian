class_name MinimapLayout
extends RefCounted

## 房间小地图布局（纯逻辑，可单元测试）：把房间图折算成网格槽位、图例字符与配色。
##
## 只读 RoomGraph / RoomData，不建节点、不碰场景树；绘制由 scenes/ui/minimap.gd 负责。
## 布局约定：横轴是深度（越往右越深入），纵轴是同一深度内的序号（秘密房排在宿主之后）。

## 没进过的房间统一显示问号。
const UNKNOWN_GLYPH: String = "？"
## 没进过的房间底色；比已知房间暗，一眼能区分。
const UNKNOWN_COLOR: Color = Color(0.21, 0.23, 0.28)
## 没进过的房间描边色。
const UNKNOWN_BORDER: Color = Color(0.36, 0.39, 0.46)
## 当前所在房间的高亮描边。
const CURRENT_BORDER: Color = Color(1.0, 0.90, 0.35)
## 已知房间的描边；主题色偏暗，统一压暗一档当描边用。
const KNOWN_BORDER_DARKEN: float = 0.55

## 每种房间类型一个汉字：16px 的格子里也能认出来。
const GLYPHS: Dictionary = {
	RoomKind.Kind.COMBAT: "战",
	RoomKind.Kind.ELITE: "精",
	RoomKind.Kind.BOSS: "王",
	RoomKind.Kind.EVENT: "事",
	RoomKind.Kind.SHOP: "商",
	RoomKind.Kind.TREASURE: "宝",
	RoomKind.Kind.ALCHEMY: "炼",
	RoomKind.Kind.REST: "休",
	RoomKind.Kind.CHALLENGE: "挑",
	RoomKind.Kind.SECRET: "秘",
}

## 房间外形：形状 + 汉字双重区分，色弱玩家也能读图。
enum Shape {
	SQUARE = 0,
	DIAMOND = 1,
	CIRCLE = 2,
	HEX = 3,
	RING = 4,
}

const SHAPES: Dictionary = {
	RoomKind.Kind.COMBAT: Shape.SQUARE,
	RoomKind.Kind.ELITE: Shape.DIAMOND,
	RoomKind.Kind.BOSS: Shape.HEX,
	RoomKind.Kind.EVENT: Shape.CIRCLE,
	RoomKind.Kind.SHOP: Shape.SQUARE,
	RoomKind.Kind.TREASURE: Shape.RING,
	RoomKind.Kind.ALCHEMY: Shape.HEX,
	RoomKind.Kind.REST: Shape.CIRCLE,
	RoomKind.Kind.CHALLENGE: Shape.DIAMOND,
	RoomKind.Kind.SECRET: Shape.RING,
}

## 图例顺序：与 RoomKind 的枚举顺序一致，展开时按此列出全部房型。
const LEGEND_ORDER: Array[int] = [
	RoomKind.Kind.COMBAT, RoomKind.Kind.ELITE, RoomKind.Kind.BOSS,
	RoomKind.Kind.EVENT, RoomKind.Kind.SHOP, RoomKind.Kind.TREASURE,
	RoomKind.Kind.ALCHEMY, RoomKind.Kind.REST, RoomKind.Kind.CHALLENGE,
	RoomKind.Kind.SECRET,
]


# ------------------------------------------------------------ 槽位

## 房间 → 网格槽位 {node_id: Vector2i(深度, 同深度序号)}。
## 深度直接取房间图的分层，所以同一深度的秘密房会落在宿主旁边。
static func slots(graph: RoomGraph) -> Dictionary:
	var result: Dictionary = {}
	if graph == null:
		return result
	for depth: int in graph.floors.size():
		var ids: PackedInt32Array = graph.floors[depth]
		for index: int in ids.size():
			result[int(ids[index])] = Vector2i(depth, index)
	return result


## 槽位包围盒；空布局返回一个零尺寸矩形，调用方不用特判。
static func bounds(slot_map: Dictionary) -> Rect2i:
	if slot_map.is_empty():
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	var minimum := Vector2i(2147483647, 2147483647)
	var maximum := Vector2i(-2147483648, -2147483648)
	for slot: Vector2i in slot_map.values():
		minimum.x = mini(minimum.x, slot.x)
		minimum.y = mini(minimum.y, slot.y)
		maximum.x = maxi(maximum.x, slot.x)
		maximum.y = maxi(maximum.y, slot.y)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


## 同一深度里的最大房间数；用来算绘制时每列需要多高。
static func max_rows(slot_map: Dictionary) -> int:
	var rows: int = 0
	for slot: Vector2i in slot_map.values():
		rows = maxi(rows, slot.y + 1)
	return rows


## 指定房间子集的槽位包围盒；用于紧凑模式只画当前窗口。
static func bounds_of(slot_map: Dictionary, nodes: Array[int]) -> Rect2i:
	var subset: Dictionary = {}
	for node_id: int in nodes:
		if slot_map.has(node_id):
			subset[node_id] = slot_map[node_id]
	return bounds(subset)


## 紧凑模式可见的房间：与当前房间的深度差不超过 radius 的房间，加上它们之间的连线端点。
## 返回按 node_id 升序的数组，保证同输入同输出。
static func window_nodes(slot_map: Dictionary, current_node: int, radius: int) -> Array[int]:
	var result: Array[int] = []
	var center: Variant = slot_map.get(current_node)
	if center == null:
		return result
	var center_depth: int = (center as Vector2i).x
	for node_id: int in slot_map:
		var slot: Vector2i = slot_map[node_id]
		if absi(slot.x - center_depth) <= maxi(radius, 0):
			result.append(node_id)
	result.sort()
	return result


# ------------------------------------------------------------ 图例与配色

## 房间类型 → 图例汉字；没进过的一律问号。
static func glyph_for(kind: int, visited: bool) -> String:
	if not visited:
		return UNKNOWN_GLYPH
	return String(GLYPHS.get(kind, "?"))


## 房间类型 → 外形；没进过的统一方格，避免外形泄露房型。
static func shape_for(kind: int, visited: bool) -> int:
	if not visited:
		return Shape.SQUARE
	return int(SHAPES.get(kind, Shape.SQUARE))


## 房间底色：进过的用区域主题色，没进过的用暗色。
static func fill_color(kind: int, theme_id: StringName, visited: bool) -> Color:
	if not visited:
		return UNKNOWN_COLOR
	return RegionThemeCatalog.color_of(theme_id)


## 房间描边：主题色压暗一档；没进过的用中性描边。
static func border_color(kind: int, theme_id: StringName, visited: bool) -> Color:
	if not visited:
		return UNKNOWN_BORDER
	var base: Color = RegionThemeCatalog.color_of(theme_id)
	return Color(base.r * KNOWN_BORDER_DARKEN, base.g * KNOWN_BORDER_DARKEN, base.b * KNOWN_BORDER_DARKEN)


## 房间文字：没进过显示问号，进过显示「房型 · 主题」。
static func label_for(kind: int, theme_id: StringName, visited: bool) -> String:
	if not visited:
		return UNKNOWN_GLYPH
	return "%s · %s" % [RoomKind.name_of(kind), RegionThemeCatalog.name_of(theme_id)]


## 展开模式的图例：全部 10 种房型 + 未探索问号。
static func legend() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind: int in LEGEND_ORDER:
		result.append({
			"kind": kind,
			"glyph": String(GLYPHS.get(kind, "?")),
			"name": RoomKind.name_of(kind),
			"shape": int(SHAPES.get(kind, Shape.SQUARE)),
		})
	result.append({
		"kind": -1,
		"glyph": UNKNOWN_GLYPH,
		"name": "未探索",
		"shape": Shape.SQUARE,
	})
	return result


# ------------------------------------------------------------ 房间查询

static func kind_of(graph: RoomGraph, node_id: int) -> int:
	var room: RoomData = room_data_of(graph, node_id)
	return room.kind if room != null else RoomKind.Kind.COMBAT


static func theme_of(graph: RoomGraph, node_id: int) -> StringName:
	var room: RoomData = room_data_of(graph, node_id)
	return room.theme_id if room != null else &""


static func room_data_of(graph: RoomGraph, node_id: int) -> RoomData:
	return graph.room_data(node_id) if graph != null else null


## 该房间向外的连线目标；旧骨架与越界都返回空。
static func links_of(graph: RoomGraph, node_id: int) -> PackedInt32Array:
	if graph == null:
		return PackedInt32Array()
	return graph.next_nodes.get(node_id, PackedInt32Array())


## 该房间挂着的秘密房；宿主房用它画一条虚线侧门。
static func secret_targets_of(graph: RoomGraph, node_id: int) -> PackedInt32Array:
	if graph == null:
		return PackedInt32Array()
	return graph.secret_targets_of(node_id)
