class_name DoorChoicePanel
extends Control

## 门选择 UI：清空房间后列出 2~3 条可选路线。
##
## 每条门显示：房间类型 + 区域主题 + 材料预告 + 敌人抗性 / 弱点，
## 玩家按当前炼金需求选路。面板不拦截移动，玩家也可以直接走进物理门。

## 选定一条门：携带局内地图的 node_id（由世界层换算成世界编号）。
signal door_chosen(data_node_id: int)

const PANEL_WIDTH: float = 560.0
const ROW_HEIGHT: float = 62.0
const ROW_SEPARATION: int = 8
const MARGIN: float = 18.0

var _root: PanelContainer = null
var _title: Label = null
var _list: VBoxContainer = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func _build() -> void:
	_root = PanelContainer.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.12, 0.94)
	style.border_color = Color(0.46, 0.40, 0.24, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(MARGIN)
	_root.add_theme_stylebox_override("panel", style)
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_root.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_root.offset_left = -PANEL_WIDTH * 0.5
	_root.offset_right = PANEL_WIDTH * 0.5
	_root.offset_top = 96.0

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", ROW_SEPARATION)
	_root.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color("f2d98a"))
	column.add_child(_title)

	_list = VBoxContainer.new()
	_list.name = "Doors"
	_list.add_theme_constant_override("separation", ROW_SEPARATION)
	column.add_child(_list)


## 列出某个房间的门；没有可选路线时自动隐藏。
func show_choices(room: RoomData) -> void:
	if room == null or room.doors.is_empty():
		hide_choices()
		return
	_title.text = "%s · %s　——　选择下一间" % [room.kind_name(), room.theme_name()]
	clear_rows()
	for index: int in room.doors.size():
		var door: DoorInfo = room.doors[index]
		_list.add_child(_build_row(door, index + 1))
	visible = true


func hide_choices() -> void:
	visible = false
	clear_rows()


func is_showing() -> bool:
	return visible


func row_count() -> int:
	return _list.get_child_count() if _list != null else 0


func clear_rows() -> void:
	if _list == null:
		return
	for child: Node in _list.get_children():
		# 立刻摘下来再释放：queue_free 是延迟的，紧接着统计行数会算上旧行。
		_list.remove_child(child)
		child.queue_free()


## 一行门：整行可点，内部用两个只读标签排版。
func _build_row(door: DoorInfo, order: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	button.pressed.connect(_on_row_pressed.bind(door))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 12.0
	column.offset_right = -12.0
	column.offset_top = 8.0
	column.offset_bottom = -8.0
	button.add_child(column)

	var head := Label.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.text = "%d. %s" % [order, door.describe()]
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color("ffe9a8"))
	column.add_child(head)

	var detail := Label.new()
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.text = _detail_text(door)
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color(0.76, 0.80, 0.86))
	column.add_child(detail)
	return button


## 材料预告 + 抗性 / 弱点：玩家按炼金需求选路的依据。
func _detail_text(door: DoorInfo) -> String:
	var materials := PackedStringArray()
	for material_id: int in door.material_preview:
		materials.append(MaterialCatalog.display_name_of(material_id))
	var material_text: String = "、".join(materials) if not materials.is_empty() else "无"
	return "材料 %s　·　抗性 %s　·　弱点 %s" % [
		material_text, _trait_names(door.resistance), _trait_names(door.weakness),
	]


func _trait_names(ids: Array[StringName]) -> String:
	if ids.is_empty():
		return "无"
	var names := PackedStringArray()
	for id: StringName in ids:
		names.append(TraitCatalog.display_name_of(id))
	return "、".join(names)


func _on_row_pressed(door: DoorInfo) -> void:
	door_chosen.emit(door.to_node)
