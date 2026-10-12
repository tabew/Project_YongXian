extends Node2D

## 占位猿猴外形放在 Visual 内，统一使用模板的姿态与全身闪红效果。
@onready var monster: GiveMonster = get_parent().get_parent() as GiveMonster


func _draw() -> void:
	var fur := Color(0.34, 0.24, 0.16)
	var light_fur := Color(0.56, 0.40, 0.25)
	var outline := Color(0.10, 0.08, 0.07)
	draw_line(Vector2(-6, 5), Vector2(-10, 11), outline, 4.0)
	draw_line(Vector2(6, 5), Vector2(10, 11), outline, 4.0)
	draw_line(Vector2(-5, -1), Vector2(-11, 3), fur, 4.0)
	draw_line(Vector2(5, -1), Vector2(11, 3), fur, 4.0)
	draw_circle(Vector2(0, 1), 8.0, fur)
	draw_circle(Vector2(0, -7), 6.5, fur)
	draw_circle(Vector2(0, -6), 4.0, light_fur)
	var attacking: bool = monster != null and monster.has_attack_intent()
	var eye_color := Color(0.95, 0.18, 0.12) if attacking else Color(0.08, 0.07, 0.06)
	draw_circle(Vector2(-2, -8), 1.0, eye_color)
	draw_circle(Vector2(2, -8), 1.0, eye_color)
	if attacking:
		draw_arc(Vector2.ZERO, 13.0, PI * 1.1, PI * 1.9, 16, Color(0.95, 0.20, 0.12), 1.5)
