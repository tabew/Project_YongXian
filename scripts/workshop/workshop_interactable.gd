class_name WorkshopInteractable
extends Node2D

## 工坊交互点：靠近后按 E 打开对应界面。
## 只负责"被靠近 / 被高亮 / 被触发"，具体界面由 Workshop 决定。

signal interacted(id: StringName)

@export var id: StringName = &""
@export var display_name: String = ""
@export var panel_id: StringName = &""
## 玩家进入这个半径内即可按 E。
@export var interact_radius: float = 58.0
## 只留接口、本期不实现具体内容的交互点：仍可交互，但只给提示。
@export var placeholder: bool = false

var _highlighted: bool = false
var _time: float = 0.0


func _ready() -> void:
	z_index = 10


func _process(delta: float) -> void:
	if not _highlighted:
		return
	_time += delta
	queue_redraw()


func can_interact_from(position: Vector2) -> bool:
	return global_position.distance_to(position) <= interact_radius


func set_highlighted(value: bool) -> void:
	if _highlighted == value:
		return
	_highlighted = value
	queue_redraw()


func is_highlighted() -> bool:
	return _highlighted


func interact() -> void:
	interacted.emit(id)


func _draw() -> void:
	var body: Color = Color(0.30, 0.36, 0.48, 0.95)
	if placeholder:
		body = Color(0.24, 0.26, 0.32, 0.85)
	if _highlighted:
		body = Color(0.96, 0.78, 0.32, 1.0)
	draw_circle(Vector2.ZERO, 20.0, body)
	draw_circle(Vector2.ZERO, 13.0, Color(0.10, 0.12, 0.17, 1.0))
	if _highlighted:
		var pulse: float = 24.0 + sin(_time * 4.0) * 3.0
		draw_arc(Vector2.ZERO, pulse, 0.0, TAU, 40, Color(1.0, 0.90, 0.52, 0.85), 2.0)
