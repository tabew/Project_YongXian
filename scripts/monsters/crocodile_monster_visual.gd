extends Node2D

@onready var host: CrocodileMonster = get_parent().get_parent() as CrocodileMonster
var _wet: bool = false

func _process(_delta: float) -> void:
	if host == null:
		return
	var wet: bool = host.is_in_water()
	if wet != _wet:
		_wet = wet
		queue_redraw()

func _draw() -> void:
	if host == null:
		return
	var wet: bool = host.is_in_water()
	var skin := Color("566d38")
	var dark := Color("283f2c")
	if wet:
		draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 24, Color(0.40, 0.72, 0.65, 0.50), 1.0)
		skin = Color("415b3d")
	# 水中左右摆尾，陆地四足交替爬行；动画图驱动相位，不每帧重建静止外形。
	var tail_sway: float = sin(host.gait_phase) * (5.0 if wet else 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-9,-5),Vector2(-29,tail_sway),Vector2(-9,5)]), dark)
	draw_rect(Rect2(-12,-7,24,14), dark)
	draw_rect(Rect2(-10,-5,20,10), skin)
	for x: int in [-7, -1, 5]:
		draw_rect(Rect2(x,-3,3,6), Color("80904b"))
	if not wet:
		for index: int in 2:
			var x: float = -8.0 if index == 0 else 6.0
			var step: float = sin(host.gait_phase + index * PI) * 3.0
			draw_line(Vector2(x,-5),Vector2(x-3+step,-10),dark,3.0)
			draw_line(Vector2(x,5),Vector2(x-3-step,10),dark,3.0)
	var gape: float = host.jaw_open * 8.0
	draw_rect(Rect2(9,-5-gape,17,5), skin)
	draw_rect(Rect2(9,gape,17,5), skin)
	for x: int in [13,18,23]:
		draw_colored_polygon(PackedVector2Array([Vector2(x,-gape),Vector2(x+2,-gape),Vector2(x+1,3-gape)]),Color("eee7c9"))
		draw_colored_polygon(PackedVector2Array([Vector2(x,gape),Vector2(x+2,gape),Vector2(x+1,gape-3)]),Color("eee7c9"))
	draw_circle(Vector2(10,-6-gape),2.0,Color("dccb62"))
	draw_circle(Vector2(10,-6-gape),1.0,Color("171d12"))
