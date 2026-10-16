
class_name BuffBar
extends Control

## 玩家当前生效 buff 的图标条。
## 自己按分组找玩家、再找它身上的 BuffHolder，所以 HUD 脚本不需要任何改动。

const SLOT_SIZE: float = 28.0
const TIME_BAR_HEIGHT: float = 3.0
##绑定失败时的重试间隔
const BIND_RETRY: float = 0.5
##剩余时间条刷新间隔
const REFRESH_INTERVAL: float = 0.1

var _slots: HBoxContainer = null
var _holder: BuffHolder = null
var _views: Dictionary = {}
var _bind_timer: float = 0.0
var _refresh_timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots = get_node_or_null("Slots") as HBoxContainer
	if _slots == null:
		_slots = HBoxContainer.new()
		_slots.name = "Slots"
		add_child(_slots)
	_slots.add_theme_constant_override("separation", 4)


func _process(delta: float) -> void:
	if _holder == null or not is_instance_valid(_holder):
		_holder = null
		_bind_timer -= delta
		if _bind_timer <= 0.0:
			_bind_timer = BIND_RETRY
			_bind()
		return
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = REFRESH_INTERVAL
	_refresh_all()


func _bind() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var player: Node = tree.get_first_node_in_group("player")
	if player == null:
		return
	var holder: BuffHolder = Buffs.holder_of(player)
	if holder == null:
		return
	_holder = holder
	_holder.changed.connect(_rebuild)
	_holder.buff_applied.connect(_on_buff_applied)
	_holder.buff_upgraded.connect(_on_buff_upgraded)
	_holder.buff_expired.connect(_on_buff_expired)
	_rebuild()


##buff 集合变了：补齐新图标、扔掉结束的
func _rebuild() -> void:
	if _holder == null:
		return
	var alive: Dictionary = {}
	for entry in _holder.get_display_list():
		var buff: BuffData = entry["buff"]
		alive[buff.id] = true
		var view: Dictionary = _views.get(buff.id, {})
		if view.is_empty():
			view = _make_view(buff)
			_views[buff.id] = view
		_apply_view(view, entry)
	for key: StringName in _views.keys().duplicate():
		if alive.has(key):
			continue
		var view: Dictionary = _views[key]
		var node: Node = view.get("root")
		if node != null and is_instance_valid(node):
			node.queue_free()
		_views.erase(key)


func _refresh_all() -> void:
	if _holder == null:
		return
	for entry in _holder.get_display_list():
		var buff: BuffData = entry["buff"]
		var view: Dictionary = _views.get(buff.id, {})
		if not view.is_empty():
			_apply_view(view, entry)


func _make_view(buff: BuffData) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	root.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	root.mouse_filter = Control.MOUSE_FILTER_PASS

	var frame := ColorRect.new()
	frame.color = Color(0.26, 0.09, 0.11, 0.92) if buff.is_debuff else Color(0.10, 0.10, 0.13, 0.88)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)

	var icon := TextureRect.new()
	icon.texture = buff.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 2.0
	icon.offset_top = 2.0
	icon.offset_right = -2.0
	icon.offset_bottom = -2.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)

	var bar := ColorRect.new()
	bar.color = Color(0.92, 0.45, 0.45, 0.95) if buff.is_debuff else Color(0.55, 0.86, 0.61, 0.95)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

	var level := Label.new()
	level.add_theme_font_size_override("font_size", 11)
	level.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.96))
	level.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	level.add_theme_constant_override("shadow_offset_x", 1)
	level.add_theme_constant_override("shadow_offset_y", 1)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	level.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(level)

	_slots.add_child(root)
	return {"root": root, "bar": bar, "level": level}


func _apply_view(view: Dictionary, entry: Dictionary) -> void:
	var buff: BuffData = entry["buff"]
	var level: int = int(entry["level"])
	var remaining: float = float(entry["remaining"])
	var ratio: float = float(entry["ratio"])
	var root: Control = view["root"]
	var bar: ColorRect = view["bar"]
	var level_label: Label = view["level"]

	if buff.duration > 0.0:
		bar.visible = true
		bar.position = Vector2(0.0, maxf(root.size.y - TIME_BAR_HEIGHT, 0.0))
		bar.size = Vector2(maxf(root.size.x * ratio, 0.0), TIME_BAR_HEIGHT)
		root.tooltip_text = "%s（等级 %d）\n%s\n剩余 %.1f 秒" % [buff.display_name, level, buff.description, remaining]
	else:
		bar.visible = false
		root.tooltip_text = "%s（等级 %d）\n%s" % [buff.display_name, level, buff.description]
	level_label.text = str(level)
	level_label.visible = level > 0


func _on_buff_applied(buff: BuffData) -> void:
	_notify("获得效果：%s" % buff.display_name)


func _on_buff_upgraded(buff: BuffData) -> void:
	_notify("效果增强：%s" % buff.display_name)


func _on_buff_expired(buff: BuffData) -> void:
	_notify("效果结束：%s" % buff.display_name)


## 事件总线是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载。
func _notify(message: String) -> void:
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("notification"):
		bus.emit_signal("notification", message)
