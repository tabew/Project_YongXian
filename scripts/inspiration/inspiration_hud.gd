class_name InspirationHud
extends Control

## 灵感 UI：右上角计数 + 飘字。
## 计数读 InspirationManager 的局内账本；飘字由世界层在光点飞入时调用 show_gain()。

const FLOAT_DURATION: float = 1.1
const FLOAT_RISE: float = 34.0
const FLOAT_WIDTH: float = 170.0
const FLOAT_HEIGHT: float = 26.0
const FLOAT_LINE_SPACING: float = 24.0
## 同时最多显示几条飘字，超出先回收最旧的。
const FLOAT_LIMIT: int = 6

var _manager: InspirationManager = null
var _counter: Label = null
## 活动飘字：{ "label": Label, "life": float }。用剩余寿命在 _process 里回收，
## 不用补间回调——回调在场景释放时仍会被步进一次，容易碰到已失效的节点。
var _floats: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_counter()


func _build_counter() -> void:
	_counter = Label.new()
	_counter.name = "InspirationCounter"
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.add_theme_color_override("font_color", Color("ffd76a"))
	_counter.add_theme_color_override("font_shadow_color", Color("2b2110"))
	_counter.add_theme_constant_override("shadow_offset_x", 2)
	_counter.add_theme_constant_override("shadow_offset_y", 2)
	_counter.add_theme_font_size_override("font_size", 20)
	add_child(_counter)
	_counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_counter.offset_left = -260.0
	_counter.offset_top = 14.0
	_counter.offset_right = -14.0
	_counter.offset_bottom = 44.0
	_counter.text = "[灵感] 0"


## 绑定灵感单例；重复绑定会先断开旧的。
func bind(manager: InspirationManager) -> void:
	if _manager != null and _manager.run_changed.is_connected(_on_run_changed):
		_manager.run_changed.disconnect(_on_run_changed)
	_manager = manager
	if manager != null:
		manager.run_changed.connect(_on_run_changed)
		_on_run_changed(manager.run.gained, manager.run.in_flight)


func _on_run_changed(gained: int, in_flight: int) -> void:
	if _counter == null:
		return
	if in_flight > 0:
		_counter.text = "[灵感] %d  (+%d)" % [gained, in_flight]
	else:
		_counter.text = "[灵感] %d" % gained


## 光点飞入：弹出 +N 灵感。
func show_gain(amount: int, source: int) -> void:
	if amount <= 0:
		return
	_push_float("+%d 灵感" % amount, Color("ffd76a"))


## 死亡：弹出 -N 灵感。
func show_loss(amount: int) -> void:
	if amount <= 0:
		return
	_push_float("-%d 灵感" % amount, Color("ff7a6b"))


## 结算：弹出总额。
func show_total(amount: int) -> void:
	if amount <= 0:
		return
	_push_float("+%d 灵感" % amount, Color("fff3c4"))


func float_count() -> int:
	return _floats.size()


## 飘字寿命到期就摘掉，避免补间回调在节点释放后仍被调用。
func _process(delta: float) -> void:
	if _floats.is_empty():
		return
	for index: int in range(_floats.size() - 1, -1, -1):
		var entry: Dictionary = _floats[index]
		entry["life"] = float(entry["life"]) - delta
		if float(entry["life"]) > 0.0:
			continue
		var label: Label = entry["label"]
		if is_instance_valid(label):
			label.queue_free()
		_floats.remove_at(index)


func _push_float(text: String, color: Color) -> void:
	while _floats.size() >= FLOAT_LIMIT:
		var oldest: Label = _floats.pop_front()["label"]
		if is_instance_valid(oldest):
			oldest.queue_free()

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color("241c0c"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_font_size_override("font_size", 18)
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	var line: int = _floats.size()
	label.offset_left = -FLOAT_WIDTH - 14.0
	label.offset_right = -14.0
	label.offset_top = 46.0 + float(line) * FLOAT_LINE_SPACING
	label.offset_bottom = label.offset_top + FLOAT_HEIGHT
	_floats.append({"label": label, "life": FLOAT_DURATION})

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "offset_top", label.offset_top - FLOAT_RISE, FLOAT_DURATION)
	tween.tween_property(label, "modulate:a", 0.0, FLOAT_DURATION).set_delay(FLOAT_DURATION * 0.35)
