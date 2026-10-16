extends Node2D
@onready var host: ShabeiMonster = get_parent().get_parent() as ShabeiMonster
func _process(_delta: float) -> void:
	if host.blackboard != null:
		scale.x = absf(scale.x) * (-1.0 if host.blackboard.facing.x < 0.0 else 1.0)
func _draw() -> void:
	var fur := Color("eef4f8")
	var edge := Color("75899b")
	draw_circle(Vector2(-9,0),4.0,edge)
	draw_circle(Vector2(-9,-1),3.0,fur)
	draw_ellipse_body(Vector2(-2,-3),Vector2(9,7),edge)
	draw_ellipse_body(Vector2(-2,-4),Vector2(8,6),fur)
	draw_rect(Rect2(-5,-23,4,15),edge)
	draw_rect(Rect2(2,-25,4,16),edge)
	draw_rect(Rect2(-4,-22,2,12),Color("e9bac9"))
	draw_rect(Rect2(3,-24,2,13),Color("e9bac9"))
	draw_circle(Vector2(5,-8),6.0,edge)
	draw_circle(Vector2(5,-9),5.0,fur)
	draw_circle(Vector2(7,-10),1.3,Color("8d344a"))
	draw_circle(Vector2(10,-7),1.0,Color("d588a0"))
	draw_circle(Vector2(8,-4),1.0+host.mouth_open*2.0,Color("4c344e"))
	draw_line(Vector2(-7,4),Vector2(-1,4),edge,2.0)
	draw_line(Vector2(3,3),Vector2(8,3),edge,2.0)
func draw_ellipse_body(center: Vector2,size: Vector2,color: Color) -> void:
	draw_set_transform(center,0.0,size)
	draw_circle(Vector2.ZERO,1.0,color)
	draw_set_transform(Vector2.ZERO)
