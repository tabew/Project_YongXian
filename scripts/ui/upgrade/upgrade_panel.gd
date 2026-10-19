class_name UpgradePanel
extends Control

## 升级三选一面板：打开时暂停游戏，选完（可能连续多级）再继续。
##
## 面板本身只管显示与点击；抽卡规则在 UpgradePool，层数与等级在 RunProgress。

signal card_chosen(card_id: StringName)

const CARD_MIN_SIZE: Vector2 = Vector2(250.0, 150.0)

const RARITY_COLORS: Array[Color] = [
	Color(0.72, 0.76, 0.82),
	Color(0.45, 0.78, 0.95),
	Color(0.98, 0.78, 0.36),
]

var _title: Label = null
var _subtitle: Label = null
var _row: HBoxContainer = null
var _center: VBoxContainer = null
var _cards: Array[UpgradeCard] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_center = VBoxContainer.new()
	_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_center.add_theme_constant_override("separation", 12)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

	_title = Label.new()
	_title.text = "升 级"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78))
	_center.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 15)
	_subtitle.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	_center.add_child(_subtitle)

	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 14)
	_center.add_child(_row)

	# 面板是满屏 Control，内容盒需要按实际尺寸手动居中。
	_center.resized.connect(_recenter)
	get_viewport().size_changed.connect(_recenter)


func _recenter() -> void:
	if _center == null:
		return
	_center.position = (get_viewport_rect().size - _center.size) * 0.5


## 展示一轮三选一。空列表表示没有可选卡，直接放行。
func show_choices(cards: Array[UpgradeCard], level: int) -> void:
	_cards = cards
	_clear_row()
	if cards.is_empty():
		visible = false
		get_tree().paused = false
		return
	_subtitle.text = _subtitle_text(level)
	for index: int in cards.size():
		_row.add_child(_make_card_button(cards[index], index))
	visible = true
	get_tree().paused = true
	await get_tree().process_frame
	_recenter()


## 副标题：等级、等级自带的成长（每级 +X%，加算），再提示选卡。
## 这一行是玩家唯一能看见"升级本身就变强"的地方，别删。
func _subtitle_text(level: int) -> String:
	var progress: Node = get_node_or_null("/root/RunProgress")
	if progress == null:
		return "等级 %d　·　选择一项加成" % level
	var per_level: int = roundi(float(progress.level_growth_per_level()) * 100.0)
	var total: int = roundi(float(progress.level_growth()) * 100.0)
	return "等级 %d　·　生命 / 伤害 / 药水效果 +%d%%（每级 +%d%%）　·　选择一项加成" % [
		level, total, per_level
	]


func _clear_row() -> void:
	for child: Node in _row.get_children():
		child.queue_free()


func _make_card_button(card: UpgradeCard, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD_MIN_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.text = "%d. %s\n\n%s" % [index + 1, card.display_name, card.description]
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", RARITY_COLORS[clampi(card.rarity, 0, RARITY_COLORS.size() - 1)])
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	button.pressed.connect(_on_card_pressed.bind(card.id))
	button.mouse_entered.connect(func() -> void:
		var manager: Node = get_node_or_null("/root/AudioManager")
		if manager != null:
			manager.call("play_sfx", &"ui_hover")
	)
	return button


func _on_card_pressed(card_id: StringName) -> void:
	var manager: Node = get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.call("play_sfx", &"ui_click")
	card_chosen.emit(card_id)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.echo or not key_event.pressed:
			return
		var slot: int = key_event.keycode - KEY_1
		if slot >= 0 and slot < _cards.size():
			_on_card_pressed(_cards[slot].id)
			get_viewport().set_input_as_handled()