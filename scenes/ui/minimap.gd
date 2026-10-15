class_name Minimap
extends Control

## 房间小地图：把局内房间图画成一张带房型图标、区域主题色与未探索问号的图。
##
## 紧凑模式跟随当前房间显示前后几列；按 M 展开成整层房间图 + 图例。
## 两种模式都常驻显示当前炼金效果 + 倒计时 + 热量条。
##
## 布局、图例与配色都在 MinimapLayout（纯逻辑、可单测）里，本节点只负责画。
## 旧的按地形采样的小地图已废弃：局内已是「层 → 区域 → 房间」，逐格地形图不再有意义。

## 紧凑模式左右各显示几个深度。
const COMPACT_DEPTH_RADIUS: int = 2
## 紧凑模式的格子尺寸与间距。
const COMPACT_CELL: float = 26.0
const COMPACT_GAP: float = 9.0
## 展开模式的格子尺寸与间距。
const EXPANDED_CELL: float = 44.0
const EXPANDED_GAP: float = 22.0
const EXPANDED_MARGIN: float = 48.0
## 收起时恢复的锚点偏移（与 hud.tscn 里 Minimap 节点的值一致）。
const COMPACT_OFFSETS: Array[float] = [-178.0, 14.0, -14.0, 178.0]

const PANEL_COLOR: Color = Color(0.03, 0.04, 0.06, 0.76)
const EXPANDED_BACKGROUND: Color = Color(0.02, 0.03, 0.045, 0.95)
const BORDER_COLOR: Color = Color(0.78, 0.84, 0.92, 0.55)
const TEXT_COLOR: Color = Color(0.92, 0.94, 0.98)
const DIM_TEXT: Color = Color(0.70, 0.74, 0.82)
## 深色底上的图标字色。
const GLYPH_ON_DARK: Color = Color(0.88, 0.91, 0.96)
## 亮色底上的图标字色。
const GLYPH_ON_LIGHT: Color = Color(0.07, 0.08, 0.11)
const LINK_COLOR: Color = Color(0.52, 0.58, 0.70, 0.80)
const SECRET_LINK_COLOR: Color = Color(0.90, 0.74, 0.34, 0.90)
const HEAT_TRACK: Color = Color(0.15, 0.16, 0.20)
const HEAT_LOW: Color = Color(0.45, 0.78, 0.95)
const HEAT_MID: Color = Color(1.0, 0.78, 0.30)
const HEAT_HIGH: Color = Color(1.0, 0.36, 0.30)
const HEAT_MID_THRESHOLD: float = 0.5
const HEAT_HIGH_THRESHOLD: float = 0.75
const ALERT_COLOR: Color = Color(1.0, 0.45, 0.40)

## 本层房间图；未开局时为空。
var _graph: RoomGraph = null
var _player: Node2D = null
## node_id -> Vector2i(深度, 同深度序号)。
var _slots: Dictionary = {}
## 本局已进入的房间；没进过的画成问号。
var _visited: Dictionary = {}
var _current_node: int = -1
var _expanded: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


# ------------------------------------------------------------ 外部接口

## 由 GameWorld 调用：注入本层房间图与主角，重新开局时也会再调一次。
func bind_run(graph: RoomGraph, player: Node2D) -> void:
	_graph = graph
	_player = player
	_slots = MinimapLayout.slots(graph)
	# 存副本：GameWorld 的已探索表要一直持有，不能被这里清掉。
	_visited = {}
	_current_node = graph.start_node() if graph != null else -1
	queue_redraw()


## 进入房间时推送：当前房间 + 本局已进入的房间集合（GameWorld 持有）。
func set_room_state(current_node: int, visited: Dictionary) -> void:
	_current_node = current_node
	# 拷一份，避免和 GameWorld 的表共用同一个字典后被误清空。
	_visited = visited.duplicate()
	queue_redraw()


## 换图 / 换种子后同步；房间图由 bind_run 注入，这里只需重算槽位并重画。
func refresh_position() -> void:
	if _graph != null and _slots.is_empty():
		_slots = MinimapLayout.slots(_graph)
	queue_redraw()


func set_expanded(value: bool) -> void:
	if _expanded == value:
		return
	_expanded = value
	if _expanded:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		z_index = 100
	else:
		anchor_left = 1.0
		anchor_top = 0.0
		anchor_right = 1.0
		anchor_bottom = 0.0
		offset_left = COMPACT_OFFSETS[0]
		offset_top = COMPACT_OFFSETS[1]
		offset_right = COMPACT_OFFSETS[2]
		offset_bottom = COMPACT_OFFSETS[3]
		z_index = 0
	queue_redraw()


func is_expanded() -> bool:
	return _expanded


## 当前窗口里画出来的房间编号（紧凑模式 = 当前房间前后几列）；供测试与调试。
func visible_nodes() -> Array[int]:
	if _graph == null or _slots.is_empty():
		return []
	if _expanded:
		var all: Array[int] = []
		for node_id: int in _slots:
			all.append(node_id)
		all.sort()
		return all
	return MinimapLayout.window_nodes(_slots, _current_node, COMPACT_DEPTH_RADIUS)


func _process(_delta: float) -> void:
	# 只画几十个房间，直接每帧重画，省掉一套脏标记。
	queue_redraw()


# ------------------------------------------------------------ 绘制

func _draw() -> void:
	if _expanded:
		_draw_expanded()
	else:
		_draw_compact()


func _draw_compact() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, PANEL_COLOR)
	draw_rect(rect, BORDER_COLOR, false, 1.0)
	var font: Font = get_theme_default_font()

	draw_string(font, Vector2(8.0, 18.0), _current_room_title(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 13, TEXT_COLOR)

	var area := Rect2(Vector2(6.0, 26.0), Vector2(size.x - 12.0, maxf(size.y - 26.0 - 52.0, 10.0)))
	if _graph == null or _slots.is_empty():
		draw_string(font, area.position + Vector2(4.0, 18.0), "未开局", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, DIM_TEXT)
	else:
		_draw_graph(area, visible_nodes(), COMPACT_CELL, COMPACT_GAP, font, false)
	_draw_alchemy(rect, font)


func _draw_expanded() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, EXPANDED_BACKGROUND)
	var font: Font = get_theme_default_font()
	var title: String = "本层房间图　·　种子 %d　·　M 收起" % _graph.plan_seed if _graph != null else "本层房间图"
	draw_string(font, Vector2(EXPANDED_MARGIN, 40.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, TEXT_COLOR)
	if _graph == null or _slots.is_empty():
		draw_string(font, Vector2(EXPANDED_MARGIN, 84.0), "未开局", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, DIM_TEXT)
		return

	var legend_height: float = 58.0
	var alchemy_height: float = 52.0
	var area := Rect2(
		Vector2(EXPANDED_MARGIN, 62.0),
		Vector2(
			maxf(rect.size.x - EXPANDED_MARGIN * 2.0, 10.0),
			maxf(rect.size.y - 62.0 - legend_height - alchemy_height - 16.0, 10.0)
		)
	)
	_draw_graph(area, visible_nodes(), EXPANDED_CELL, EXPANDED_GAP, font, true)
	_draw_legend(Rect2(Vector2(EXPANDED_MARGIN, rect.size.y - legend_height - alchemy_height), Vector2(maxf(rect.size.x - EXPANDED_MARGIN * 2.0, 10.0), legend_height)), font)
	_draw_alchemy(rect, font)


## 画一批房间：先连线再画格子，保证线被格子盖住。
func _draw_graph(area: Rect2, nodes: Array[int], cell: float, gap: float, font: Font, with_labels: bool) -> void:
	if nodes.is_empty() or area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var sub: Rect2i = MinimapLayout.bounds_of(_slots, nodes)
	if sub.size == Vector2i.ZERO:
		return
	var step: float = cell + gap
	var graph_size := Vector2(sub.size) * step - Vector2(gap, gap)
	var scale: float = 1.0
	if graph_size.x > area.size.x or graph_size.y > area.size.y:
		scale = minf(area.size.x / maxf(graph_size.x, 1.0), area.size.y / maxf(graph_size.y, 1.0))
		scale = clampf(scale, 0.30, 1.0)
	var drawn: Vector2 = graph_size * scale
	var origin: Vector2 = area.position + (area.size - drawn) * 0.5 - Vector2(sub.position) * step * scale
	var drawn_cell: float = cell * scale
	var drawn_step: float = step * scale

	for node_id: int in nodes:
		var from: Vector2 = _cell_center(node_id, origin, drawn_step, drawn_cell)
		for target: int in MinimapLayout.links_of(_graph, node_id):
			if not nodes.has(target):
				continue
			draw_line(from, _cell_center(target, origin, drawn_step, drawn_cell), LINK_COLOR, maxf(1.0, 1.6 * scale), true)
	for node_id: int in nodes:
		var from: Vector2 = _cell_center(node_id, origin, drawn_step, drawn_cell)
		for target: int in MinimapLayout.secret_targets_of(_graph, node_id):
			if not nodes.has(target):
				continue
			draw_dashed_line(from, _cell_center(target, origin, drawn_step, drawn_cell), SECRET_LINK_COLOR, maxf(1.0, 1.6 * scale), 4.0, true)
	for node_id: int in nodes:
		_draw_room(_cell_center(node_id, origin, drawn_step, drawn_cell), drawn_cell, node_id, font, with_labels)


## 槽位 → 格子中心。origin 已经把窗口包围盒的偏移折算进去。
func _cell_center(node_id: int, origin: Vector2, step: float, cell: float) -> Vector2:
	var slot: Vector2i = _slots[node_id]
	return origin + Vector2(slot) * step + Vector2(cell, cell) * 0.5


func _draw_room(center: Vector2, cell: float, node_id: int, font: Font, with_labels: bool) -> void:
	var visited: bool = _visited.has(node_id)
	var kind: int = MinimapLayout.kind_of(_graph, node_id)
	var theme_id: StringName = MinimapLayout.theme_of(_graph, node_id)
	var fill: Color = MinimapLayout.fill_color(kind, theme_id, visited)
	var border: Color = MinimapLayout.border_color(kind, theme_id, visited)
	var radius: float = cell * 0.5
	_draw_shape(center, radius, MinimapLayout.shape_for(kind, visited), fill, border)
	if node_id == _current_node:
		draw_arc(center, radius + 3.0, 0.0, TAU, 28, MinimapLayout.CURRENT_BORDER, 2.0, true)

	var glyph: String = MinimapLayout.glyph_for(kind, visited)
	var font_size: int = int(maxf(cell * 0.56, 9.0))
	var glyph_size: Vector2 = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(
		font,
		center + Vector2(-glyph_size.x * 0.5, glyph_size.y * 0.32),
		glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
		GLYPH_ON_LIGHT if visited else GLYPH_ON_DARK
	)
	if not with_labels:
		return
	var label: String = MinimapLayout.label_for(kind, theme_id, visited)
	var label_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13)
	draw_string(
		font,
		center + Vector2(-label_size.x * 0.5, radius + 17.0),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13,
		TEXT_COLOR if visited else DIM_TEXT
	)


## 房型外形：形状 + 汉字双重区分，色弱也能读图。
func _draw_shape(center: Vector2, radius: float, shape: int, fill: Color, border: Color) -> void:
	match shape:
		MinimapLayout.Shape.CIRCLE:
			draw_circle(center, radius, fill)
			draw_arc(center, radius, 0.0, TAU, 28, border, 1.6, true)
		MinimapLayout.Shape.RING:
			draw_circle(center, radius, Color(fill.r, fill.g, fill.b, 0.35))
			draw_arc(center, radius - 1.0, 0.0, TAU, 28, border, 3.0, true)
		_:
			var points: PackedVector2Array = _shape_points(center, radius, shape)
			draw_colored_polygon(points, fill)
			var outline: PackedVector2Array = points.duplicate()
			outline.append(points[0])
			draw_polyline(outline, border, 1.6, true)


func _shape_points(center: Vector2, radius: float, shape: int) -> PackedVector2Array:
	match shape:
		MinimapLayout.Shape.DIAMOND:
			return PackedVector2Array([
				center + Vector2(0.0, -radius),
				center + Vector2(radius, 0.0),
				center + Vector2(0.0, radius),
				center + Vector2(-radius, 0.0),
			])
		MinimapLayout.Shape.HEX:
			var hex := PackedVector2Array()
			for index: int in 6:
				var angle: float = -PI * 0.5 + TAU * float(index) / 6.0
				hex.append(center + Vector2(cos(angle), sin(angle)) * radius)
			return hex
		_:
			var inset: float = radius * 0.94
			return PackedVector2Array([
				center + Vector2(-inset, -inset),
				center + Vector2(inset, -inset),
				center + Vector2(inset, inset),
				center + Vector2(-inset, inset),
			])


## 展开模式的图例：全部 10 种房型 + 未探索。
func _draw_legend(rect: Rect2, font: Font) -> void:
	var entries: Array[Dictionary] = MinimapLayout.legend()
	if entries.is_empty():
		return
	var per_row: int = 6
	var column_width: float = maxf(rect.size.x / float(per_row), 60.0)
	var swatch: float = 9.0
	for index: int in entries.size():
		var entry: Dictionary = entries[index]
		var row: int = index / per_row
		var column: int = index % per_row
		var base := rect.position + Vector2(float(column) * column_width, 12.0 + float(row) * 22.0)
		var visited: bool = int(entry["kind"]) >= 0
		var fill: Color = fill_color_for_legend(int(entry["kind"]), visited)
		_draw_shape(base + Vector2(swatch, 0.0), swatch, int(entry["shape"]), fill, BORDER_COLOR)
		draw_string(
			font, base + Vector2(swatch * 2.0 + 5.0, 4.0),
			"%s %s" % [String(entry["glyph"]), String(entry["name"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, TEXT_COLOR if visited else DIM_TEXT
		)


func fill_color_for_legend(kind: int, visited: bool) -> Color:
	if not visited:
		return MinimapLayout.UNKNOWN_COLOR
	return MinimapLayout.fill_color(kind, _legend_theme_id(kind), true)


## 图例用色：从本层房间图里找同类型房间的主题色，找不到就用中性色。
func _legend_theme_id(kind: int) -> StringName:
	for node_id: int in _slots:
		if MinimapLayout.kind_of(_graph, node_id) == kind:
			return MinimapLayout.theme_of(_graph, node_id)
	return &""


## 当前房间的标题：进过的显示「房型 · 主题」，没进过显示问号。
func _current_room_title() -> String:
	if _graph == null or _current_node < 0 or _slots.is_empty():
		return "房间图"
	var visited: bool = _visited.has(_current_node)
	return MinimapLayout.label_for(
		MinimapLayout.kind_of(_graph, _current_node),
		MinimapLayout.theme_of(_graph, _current_node),
		visited
	)


## 底部常驻：当前炼金效果 + 倒计时 + 热量条。只读炼金台的公开接口。
func _draw_alchemy(rect: Rect2, font: Font) -> void:
	var bar := Rect2(Vector2(8.0, rect.size.y - 22.0), Vector2(maxf(rect.size.x - 16.0, 10.0), 9.0))
	var swatch_pos := Vector2(8.0, rect.size.y - 46.0)

	var effect_color: Color = AlchemyStatusRing.IDLE_COLOR
	var effect_label: String = "无炼金效果"
	var remaining: float = 0.0
	var heat_ratio: float = 0.0
	var disabled: bool = false
	var station: AlchemyStation = _station()
	if station != null:
		var combo: BrewCombo = station.active_combo()
		effect_color = AlchemyStatusRing.effect_color(combo)
		if AlchemyStatusRing.is_active(combo):
			var element: StringName = AlchemyStatusRing.dominant_element(combo)
			effect_label = TraitCatalog.display_name_of(element) if element != &"" else combo.describe()
			remaining = station.session.duration.remaining
		heat_ratio = clampf(station.heat() / AlchemyRules.HEAT_MAX, 0.0, 1.0)
		disabled = station.session.weapon_disabled()

	draw_rect(Rect2(swatch_pos, Vector2(11.0, 11.0)), effect_color)
	draw_rect(Rect2(swatch_pos, Vector2(11.0, 11.0)), BORDER_COLOR, false, 1.0)
	var text: String = effect_label
	if remaining > 0.0:
		text = "%s　%.1fs" % [effect_label, remaining]
	if disabled:
		text = "武器失效"
	draw_string(font, swatch_pos + Vector2(16.0, 10.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, ALERT_COLOR if disabled else TEXT_COLOR)

	draw_rect(bar, HEAT_TRACK)
	if heat_ratio > 0.0:
		var heat_color: Color = HEAT_LOW
		if heat_ratio >= HEAT_HIGH_THRESHOLD:
			heat_color = HEAT_HIGH
		elif heat_ratio >= HEAT_MID_THRESHOLD:
			heat_color = HEAT_MID
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * heat_ratio, bar.size.y)), heat_color)
	draw_rect(bar, BORDER_COLOR, false, 1.0)


## 主角的随身炼金台；没有时返回 null。
func _station() -> AlchemyStation:
	if _player is PlayerCharacter:
		return (_player as PlayerCharacter).alchemy_station
	return null
