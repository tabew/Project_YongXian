class_name RunSettlementPanel
extends Control

## 通关结算界面（贤者之石）：展示灵感明细，确认后回工坊。
##
## 数据全部来自 InspirationManager.finish_run() 的返回值，本面板只负责排版与确认。
## 打开期间世界暂停，避免结算读条时被偷袭。

signal confirmed

const PANEL_WIDTH: float = 520.0
const PANEL_HEIGHT: float = 440.0
const MARGIN: float = 20.0

var _root: PanelContainer = null
var _list: VBoxContainer = null
var _result: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 结算面板是模态界面：世界暂停后仍要能收输入。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	_root = PanelContainer.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.12, 0.97)
	style.border_color = Color(0.46, 0.40, 0.24, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(MARGIN)
	_root.add_theme_stylebox_override("panel", style)
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_root.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_root.offset_left = -PANEL_WIDTH * 0.5
	_root.offset_top = -PANEL_HEIGHT * 0.5
	_root.offset_right = PANEL_WIDTH * 0.5
	_root.offset_bottom = PANEL_HEIGHT * 0.5

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	_root.add_child(column)

	var title := Label.new()
	title.text = "贤者之石 · 通关结算"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f2d98a"))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "材料在贤者之石中化作永久灵感。"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.66, 0.70, 0.78))
	column.add_child(subtitle)

	column.add_child(HSeparator.new())

	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	column.add_child(_list)

	column.add_child(HSeparator.new())

	var button := Button.new()
	button.name = "Confirm"
	button.text = "收下灵感 · 回到炼金工坊"
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.pressed.connect(_on_confirm)
	column.add_child(button)


## 展示一次结算结果。
func show_result(result: Dictionary) -> void:
	_result = result.duplicate()
	_fill_rows()
	visible = true
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = true


func hide_panel() -> void:
	visible = false
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false


func is_showing() -> bool:
	return visible


func row_count() -> int:
	return _list.get_child_count() if _list != null else 0


func final_value() -> int:
	return int(_result.get("final", 0))


func _on_confirm() -> void:
	hide_panel()
	confirmed.emit()


func _fill_rows() -> void:
	if _list == null:
		return
	for child: Node in _list.get_children():
		# 立刻摘下来再释放，避免紧接着统计行数时算上旧行。
		_list.remove_child(child)
		child.queue_free()
	_add_row("局内灵感", "%d" % int(_result.get("run", 0)))
	_add_row("贤者之石", "+%d" % int(_result.get("sage_stone", 0)))
	_add_row("材料转化", "+%d" % int(_result.get("materials", 0)))
	_add_row("表现加成", "+%d" % int(_result.get("performance", 0)))
	_add_row("小计", "%d" % int(_result.get("base", 0)))
	_add_row("难度倍率", "×%.2f" % float(_result.get("difficulty", 1.0)))
	var codex: float = float(_result.get("codex_bonus", 0.0))
	if codex > 0.0:
		_add_row("图鉴加成", "+%d%%" % roundi(codex * 100.0))
	_add_row("最终灵感", "%d" % final_value(), Color("ffd76a"))


func _add_row(description: String, value: String, color: Color = Color(0.80, 0.84, 0.90)) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = description
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)
	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 16)
	value_label.add_theme_color_override("font_color", color)
	row.add_child(value_label)
	_list.add_child(row)
