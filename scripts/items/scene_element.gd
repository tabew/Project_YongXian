class_name SceneElement
extends Node2D

## 可吸附场景元素：靠近后长按吸附键产出主题材料，随后进入冷却再长回来。
##
## 与地面材料的分工：
## - 地面材料（GroundPickup）是一次性的，捡完就没有；
## - 场景元素是可再生来源，只要待在房间里就能反复吸附，鼓励玩家在房间里多停留。
##
## 本节点只管"被靠近 / 被吸附 / 冷却"，材料入包由 GameWorld 调炼金台完成。

## 吸附完成：携带元素 id、产出的材料与数量。
signal absorbed(element_id: StringName, material_id: int, amount: int)

## 可交互半径（像素）。
const INTERACT_RADIUS: float = 46.0
## 长按多久完成一次吸附（秒）。
const HOLD_SECONDS: float = 0.7
## 吸附后的冷却（秒）；冷却结束自动长回。
const COOLDOWN_SECONDS: float = 9.0

var element_id: StringName = &""
var display_name: String = ""
var material_id: int = -1
var amount: int = 1
var traits: Array[StringName] = []

var _hold: float = 0.0
var _cooldown: float = 0.0
var _highlighted: bool = false
var _time: float = 0.0


func _ready() -> void:
	add_to_group("scene_elements")
	z_index = 3
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
		if _cooldown <= 0.0:
			_hold = 0.0
			queue_redraw()
		else:
			queue_redraw()
	elif _highlighted:
		queue_redraw()


## 由规划器给出的一条点位数据。
func bind(entry: Dictionary) -> void:
	element_id = StringName(entry.get("id", &""))
	display_name = SceneElementCatalog.name_of(element_id)
	material_id = int(entry.get("material_id", -1))
	amount = maxi(int(entry.get("amount", 1)), 1)
	traits.clear()
	for trait_id: Variant in entry.get("traits", []):
		traits.append(StringName(trait_id))
	_hold = 0.0
	_cooldown = 0.0
	queue_redraw()


## 是否在可交互半径内。
func can_interact_from(position: Vector2) -> bool:
	return is_ready_to_absorb() and global_position.distance_to(position) <= INTERACT_RADIUS


## 冷却结束才可再次吸附。
func is_ready_to_absorb() -> bool:
	return _cooldown <= 0.0


func cooldown_ratio() -> float:
	return clampf(_cooldown / COOLDOWN_SECONDS, 0.0, 1.0)


func hold_ratio() -> float:
	return clampf(_hold / HOLD_SECONDS, 0.0, 1.0)


func set_highlighted(value: bool) -> void:
	if _highlighted == value:
		return
	_highlighted = value
	if not _highlighted:
		_hold = 0.0
	queue_redraw()


func is_highlighted() -> bool:
	return _highlighted


## 推进长按；进度满时吸附一次并返回产出的材料（未完成返回空字典）。
func advance_hold(delta: float) -> Dictionary:
	if not is_ready_to_absorb():
		return {}
	_hold += delta
	if _hold < HOLD_SECONDS:
		queue_redraw()
		return {}
	_hold = 0.0
	_cooldown = COOLDOWN_SECONDS
	queue_redraw()
	absorbed.emit(element_id, material_id, amount)
	return {"material_id": material_id, "amount": amount}


## 元素主题色：按第一个词条取色，没有词条时用中性色。
func _trait_color() -> Color:
	if traits.is_empty():
		return Color(0.72, 0.74, 0.78)
	match traits[0]:
		&"fire":
			return Color(0.95, 0.44, 0.22)
		&"poison":
			return Color(0.52, 0.80, 0.28)
		&"ice":
			return Color(0.52, 0.82, 0.94)
		&"electric":
			return Color(0.98, 0.86, 0.32)
		&"acid":
			return Color(0.72, 0.92, 0.26)
		&"magnet":
			return Color(0.62, 0.66, 0.86)
		&"soul":
			return Color(0.62, 0.72, 0.92)
		&"bone":
			return Color(0.88, 0.86, 0.76)
		&"blood":
			return Color(0.82, 0.24, 0.30)
		&"wind":
			return Color(0.72, 0.90, 0.84)
		&"sand":
			return Color(0.86, 0.76, 0.50)
		&"light":
			return Color(0.98, 0.95, 0.72)
		&"dark":
			return Color(0.42, 0.36, 0.58)
	return Color(0.66, 0.80, 0.62)


func _draw() -> void:
	var ready: bool = is_ready_to_absorb()
	var color: Color = _trait_color()
	var body: Color = color if ready else color.darkened(0.62)
	draw_rect(Rect2(-9.0, 3.0, 18.0, 3.0), Color(0.06, 0.07, 0.05, 0.32))
	# 菱形主体：与圆形的地面材料区分开，一眼能看出是可交互场景物。
	var points := PackedVector2Array([
		Vector2(0.0, -12.0), Vector2(9.0, -3.0), Vector2(0.0, 6.0), Vector2(-9.0, -3.0),
	])
	draw_colored_polygon(points, body)
	draw_polyline(points + PackedVector2Array([points[0]]), color.lightened(0.25), 1.0)
	if not ready:
		# 冷却中：底部画一条回满进度，玩家知道还要等多久。
		draw_rect(Rect2(-9.0, 7.0, 18.0, 2.0), Color(0.10, 0.11, 0.13, 0.85))
		draw_rect(Rect2(-9.0, 7.0, 18.0 * (1.0 - cooldown_ratio()), 2.0), color)
		return
	if _highlighted:
		var pulse: float = 15.0 + sin(_time * 4.0) * 2.0
		draw_arc(Vector2.ZERO, pulse, 0.0, TAU, 28, Color(1.0, 0.92, 0.58, 0.85), 1.5)
		if _hold > 0.0:
			draw_arc(Vector2.ZERO, pulse + 3.0, -PI * 0.5, -PI * 0.5 + TAU * hold_ratio(), 28, Color(0.62, 0.94, 0.72, 0.95), 2.5)
