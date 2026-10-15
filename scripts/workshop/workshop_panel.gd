class_name WorkshopPanel
extends PanelContainer

## 工坊界面基类：统一的标题栏 + 内容区 + 底部提示。
## 子类只需要实现 _build_content() 与 refresh()。
## 打开时完全暂停世界（与炼金台一致），Esc 关闭。

signal close_requested

const PANEL_SIZE: Vector2 = Vector2(640.0, 460.0)
const ROW_SEPARATION: int = 6

var manager: InspirationManager = null

var _title_label: Label = null
var _subtitle_label: Label = null
var _content: VBoxContainer = null
var _footer: Label = null


func setup(mgr: InspirationManager) -> void:
	manager = mgr


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_frame()


func _build_frame() -> void:
	var panel_size: Vector2 = self.panel_size()
	custom_minimum_size = panel_size
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -panel_size.x * 0.5
	offset_top = -panel_size.y * 0.5
	offset_right = panel_size.x * 0.5
	offset_bottom = panel_size.y * 0.5

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.12, 0.97)
	style.border_color = Color(0.46, 0.40, 0.24, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18.0)
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color("f2d98a"))
	column.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override("font_size", 14)
	_subtitle_label.add_theme_color_override("font_color", Color(0.66, 0.70, 0.78))
	column.add_child(_subtitle_label)

	var separator := HSeparator.new()
	column.add_child(separator)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", ROW_SEPARATION)
	scroll.add_child(_content)

	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.add_theme_color_override("font_color", Color(0.60, 0.64, 0.72))
	column.add_child(_footer)
	_footer.text = "Esc 关闭"

	_build_content(_content)


## 面板尺寸：子类可覆写（内容多的面板用更大的尺寸）。
func panel_size() -> Vector2:
	return PANEL_SIZE


## 子类重写：构建内容区。
func _build_content(_parent: VBoxContainer) -> void:
	pass


## 子类重写：面板打开或数据变化时刷新。
func refresh() -> void:
	pass


func open() -> void:
	visible = true
	# 面板自己持有暂停权：无论从工坊交互点打开，还是被测试 / 工具直接 open()，
	# 世界都会一致地暂停。process_mode 在 _ready 里设为 ALWAYS，暂停后仍能收到 Esc。
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = true
	refresh()


func close() -> void:
	visible = false
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	close_requested.emit()


func is_open() -> bool:
	return visible


func set_titles(title: String, subtitle: String) -> void:
	if _title_label != null:
		_title_label.text = title
	if _subtitle_label != null:
		_subtitle_label.text = subtitle


func content() -> VBoxContainer:
	return _content


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("alchemy_cancel") and not event.is_echo():
		play_sfx(&"ui_back")
		close()
		get_viewport().set_input_as_handled()


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载（与 player.gd 一致）。
func play_sfx(id: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.call("play_sfx", id)


# ------------------------------------------------------------ 行构件

## 一行：左侧说明 + 右侧按钮。
func make_row(description: String, button_text: String, pressed: Callable, enabled: bool = true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = description
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	row.add_child(label)
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(150.0, 30.0)
	button.disabled = not enabled
	button.pressed.connect(pressed)
	button.mouse_entered.connect(func() -> void: play_sfx(&"ui_hover"))
	row.add_child(button)
	return row


## 一行：左侧说明 + 右侧纯文本（用于展示已购等级等）。
func make_info_row(description: String, value: String, color: Color = Color(0.80, 0.84, 0.90)) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = description
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	row.add_child(label)
	var value_label := Label.new()
	value_label.text = value
	value_label.custom_minimum_size = Vector2(150.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", color)
	row.add_child(value_label)
	return row


func make_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color("c9b26a"))
	return label


func clear_content() -> void:
	for child: Node in _content.get_children():
		# 立刻摘下来再释放：queue_free 是延迟的，
		# 如果只调 queue_free，紧接着统计子节点数量会算上还没被回收的旧行。
		_content.remove_child(child)
		child.queue_free()
