extends SceneTree

## 小地图布局（MinimapLayout）单元测试：槽位、窗口、图例字符 / 外形 / 配色。
##
## godot --headless --path . --script res://tests/test_minimap_layout.gd
##
## 全是纯逻辑断言：不建节点、不读场景树，只把房间图折算成网格与配色。

const SEEDS: Array[int] = [1, 42, 777, 20261014]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_test_slots()
	_test_bounds()
	_test_window()
	_test_unknown_rooms()
	_test_known_rooms()
	_test_colors()
	_test_legend()
	_test_graph_queries()
	_test_theme_colors()
	print("MINIMAP LAYOUT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _graph(seed_value: int, floor_index: int = 0) -> FloorRoomGraph:
	var floor: FloorData = RunMapGenerator.generate(seed_value, floor_index, RunMapConfig.prototype())
	return FloorRoomGraph.plan_from_floor(floor, MapConfig.new(), seed_value)


## 槽位：每个房间恰好一格，横轴是深度，纵轴是同深度内的序号，且同输入同输出。
func _test_slots() -> void:
	for seed_value: int in SEEDS:
		var graph: FloorRoomGraph = _graph(seed_value)
		var slots: Dictionary = MinimapLayout.slots(graph)
		_check(slots.size() == graph.types.size(), "种子 %d 每个房间都有槽位" % seed_value)
		_check(slots == MinimapLayout.slots(graph), "种子 %d 槽位可复现" % seed_value)
		var occupied: Dictionary = {}
		for depth: int in graph.floors.size():
			var ids: PackedInt32Array = graph.floors[depth]
			for index: int in ids.size():
				var node_id: int = ids[index]
				_check(slots.get(node_id) == Vector2i(depth, index), "槽位 = (深度, 序号)")
				_check(not occupied.has(slots[node_id]), "种子 %d 槽位不重叠" % seed_value)
				occupied[slots[node_id]] = true
		var box: Rect2i = MinimapLayout.bounds(slots)
		_check(box.position.x == 0 and box.size.x == graph.floors.size(), "包围盒覆盖全部深度")
		_check(MinimapLayout.max_rows(slots) == box.size.y, "最大行数 = 包围盒高度")
	_check(MinimapLayout.slots(null).is_empty(), "空图没有槽位")


func _test_bounds() -> void:
	_check(MinimapLayout.bounds({}) == Rect2i(Vector2i.ZERO, Vector2i.ZERO), "空布局返回零矩形")
	var slots: Dictionary = {1: Vector2i(2, 3), 2: Vector2i(5, 1)}
	var box: Rect2i = MinimapLayout.bounds(slots)
	_check(box.position == Vector2i(2, 1) and box.size == Vector2i(4, 3), "包围盒取最小 / 最大槽位")
	_check(MinimapLayout.bounds_of(slots, [2]) == Rect2i(Vector2i(5, 1), Vector2i.ONE), "子集包围盒只算指定房间")
	_check(MinimapLayout.bounds_of(slots, [99]).size == Vector2i.ZERO, "越界房间不进包围盒")
	_check(MinimapLayout.max_rows(slots) == 4, "最大行数取纵轴最大值 + 1")
	_check(MinimapLayout.max_rows({}) == 0, "空布局没有行")


## 紧凑模式只画当前深度前后各 radius 列，结果按 node_id 升序，保证同输入同输出。
func _test_window() -> void:
	for seed_value: int in SEEDS:
		var graph: FloorRoomGraph = _graph(seed_value)
		var slots: Dictionary = MinimapLayout.slots(graph)
		var current: int = graph.start_node()
		var nodes: Array[int] = MinimapLayout.window_nodes(slots, current, 2)
		_check(nodes.has(current), "种子 %d 窗口包含当前房间" % seed_value)
		_check(nodes == MinimapLayout.window_nodes(slots, current, 2), "窗口可复现")
		_check(nodes.size() <= slots.size(), "窗口不会超出整层")
		var sorted_copy: Array[int] = nodes.duplicate()
		sorted_copy.sort()
		_check(nodes == sorted_copy, "窗口按 node_id 升序")
		var center_depth: int = slots[current].x
		for node_id: int in nodes:
			_check(absi(slots[node_id].x - center_depth) <= 2, "窗口只含前后 2 列")
		for node_id: int in slots:
			if absi(slots[node_id].x - center_depth) <= 2:
				_check(nodes.has(node_id), "窗口不漏房间")
		for node_id: int in MinimapLayout.window_nodes(slots, current, 0):
			_check(slots[node_id].x == center_depth, "radius 0 只留当前深度")
	_check(MinimapLayout.window_nodes({}, 0, 2).is_empty(), "空布局没有窗口")
	_check(MinimapLayout.window_nodes({1: Vector2i(0, 0)}, -1, 2).is_empty(), "当前房间不在图里时窗口为空")


## 没进过的房间：问号 + 统一外形 + 暗色底，不泄露房型与主题。
func _test_unknown_rooms() -> void:
	_check(MinimapLayout.UNKNOWN_GLYPH == "？", "未探索用问号")
	for kind: int in RoomKind.COUNT:
		var name: String = RoomKind.name_of(kind)
		_check(MinimapLayout.glyph_for(kind, false) == MinimapLayout.UNKNOWN_GLYPH, "未探索一律问号：%s" % name)
		_check(MinimapLayout.shape_for(kind, false) == MinimapLayout.Shape.SQUARE, "未探索统一方格：%s" % name)
		_check(MinimapLayout.fill_color(kind, &"fire_zone", false) == MinimapLayout.UNKNOWN_COLOR, "未探索统一暗底：%s" % name)
		_check(MinimapLayout.border_color(kind, &"fire_zone", false) == MinimapLayout.UNKNOWN_BORDER, "未探索统一描边：%s" % name)
		_check(MinimapLayout.label_for(kind, &"fire_zone", false) == MinimapLayout.UNKNOWN_GLYPH, "未探索不显示房型与主题：%s" % name)


## 进过的房间：房型汉字 + 专属外形 + 「房型 · 主题」标签。
func _test_known_rooms() -> void:
	var seen_glyphs: Dictionary = {}
	for kind: int in RoomKind.COUNT:
		var name: String = RoomKind.name_of(kind)
		var glyph: String = MinimapLayout.glyph_for(kind, true)
		_check(not glyph.is_empty() and glyph != MinimapLayout.UNKNOWN_GLYPH, "进过的房间有汉字：%s" % name)
		_check(not seen_glyphs.has(glyph), "房型汉字互不重复：%s" % glyph)
		seen_glyphs[glyph] = true
		_check(MinimapLayout.shape_for(kind, true) == MinimapLayout.SHAPES[kind], "进过的房间用配置外形：%s" % name)
		var label: String = MinimapLayout.label_for(kind, &"mine", true)
		_check(label.contains(name), "标签含房型：%s" % label)
		_check(label.contains(RegionThemeCatalog.name_of(&"mine")), "标签含主题：%s" % label)
	_check(seen_glyphs.size() == RoomKind.COUNT, "10 种房型各有自己的汉字")
	# 事件房 / 挑战房 / 宝箱房 / 秘密房必须有独立图标，不能退化成同一个字。
	_check(MinimapLayout.glyph_for(RoomKind.Kind.EVENT, true) == "事", "事件房图标")
	_check(MinimapLayout.glyph_for(RoomKind.Kind.CHALLENGE, true) == "挑", "挑战房图标")
	_check(MinimapLayout.glyph_for(RoomKind.Kind.TREASURE, true) == "宝", "宝箱房图标")
	_check(MinimapLayout.glyph_for(RoomKind.Kind.SECRET, true) == "秘", "秘密房图标")
	_check(MinimapLayout.glyph_for(RoomKind.Kind.SHOP, true) == "商", "商店房图标")
	_check(MinimapLayout.glyph_for(RoomKind.Kind.REST, true) == "休", "休息房图标")
	_check(MinimapLayout.glyph_for(RoomKind.Kind.ALCHEMY, true) == "炼", "炼金房图标")


## 进过的房间用区域主题色，描边比底色暗一档；未配置主题回落到中性色。
func _test_colors() -> void:
	var fill: Color = MinimapLayout.fill_color(RoomKind.Kind.COMBAT, &"fire_zone", true)
	_check(fill == RegionThemeCatalog.color_of(&"fire_zone"), "底色 = 区域主题色")
	var border: Color = MinimapLayout.border_color(RoomKind.Kind.COMBAT, &"fire_zone", true)
	_check(border.r < fill.r and border.g < fill.g and border.b < fill.b, "描边比底色暗")
	_check(MinimapLayout.fill_color(RoomKind.Kind.COMBAT, &"no_such_theme", true) == RegionThemeCatalog.color_of(&"no_such_theme"), "未知主题用兜底色")


## 展开图例：10 种房型 + 未探索，顺序与枚举一致。
func _test_legend() -> void:
	var entries: Array[Dictionary] = MinimapLayout.legend()
	_check(entries.size() == RoomKind.COUNT + 1, "图例 = 10 种房型 + 未探索")
	if entries.size() != RoomKind.COUNT + 1:
		return
	for index: int in RoomKind.COUNT:
		var kind: int = int(entries[index]["kind"])
		_check(kind == MinimapLayout.LEGEND_ORDER[index], "图例顺序与枚举一致")
		_check(String(entries[index]["glyph"]) == MinimapLayout.glyph_for(kind, true), "图例汉字与房间一致")
		_check(String(entries[index]["name"]) == RoomKind.name_of(kind), "图例名字与房型一致")
	var unknown: Dictionary = entries[RoomKind.COUNT]
	_check(int(unknown["kind"]) == -1 and String(unknown["glyph"]) == MinimapLayout.UNKNOWN_GLYPH, "图例最后是未探索问号")


## 房间查询：类型 / 主题 / 连线 / 秘密房；空图与越界都退回安全默认值。
func _test_graph_queries() -> void:
	var graph: FloorRoomGraph = _graph(20261014)
	var start: int = graph.start_node()
	_check(MinimapLayout.kind_of(graph, start) == graph.room_data(start).kind, "类型取自房间数据")
	_check(MinimapLayout.theme_of(graph, start) == graph.room_data(start).theme_id, "主题取自房间数据")
	_check(MinimapLayout.links_of(graph, start) == graph.next_nodes[start], "连线取自房间图")
	_check(MinimapLayout.room_data_of(graph, -1) == null, "越界房间返回 null")
	_check(MinimapLayout.kind_of(graph, -1) == RoomKind.Kind.COMBAT, "越界类型退回战斗房")
	_check(MinimapLayout.links_of(graph, -1).is_empty(), "越界没有连线")
	_check(MinimapLayout.kind_of(null, 0) == RoomKind.Kind.COMBAT, "空图退回战斗房")
	_check(MinimapLayout.links_of(null, 0).is_empty(), "空图没有连线")
	var host: int = -1
	var secret: int = -1
	for node_id: int in graph.types.keys():
		var targets: PackedInt32Array = MinimapLayout.secret_targets_of(graph, node_id)
		if not targets.is_empty():
			host = node_id
			secret = int(targets[0])
			break
	_check(host >= 0 and secret >= 0, "本局有秘密房宿主")
	if host >= 0:
		_check(MinimapLayout.kind_of(graph, secret) == RoomKind.Kind.SECRET, "宿主挂着秘密房")


## 13 个区域主题都要有各自代表色，否则小地图会画成一片灰。
func _test_theme_colors() -> void:
	var ids: Array[StringName] = RegionThemeCatalog.ids()
	_check(ids.size() == 13, "13 个区域主题")
	var seen: Dictionary = {}
	for theme_id: StringName in ids:
		var color: Color = RegionThemeCatalog.color_of(theme_id)
		_check(not seen.has(color), "主题代表色互不重复：%s" % String(theme_id))
		seen[color] = true
		_check(RegionThemeCatalog.create(theme_id).color == color, "RegionTheme 与配置表同色：%s" % String(theme_id))
	_check(seen.size() == ids.size(), "每个主题一种颜色")
