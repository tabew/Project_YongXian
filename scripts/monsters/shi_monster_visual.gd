extends Node2D

@onready var host: ShiMonster = get_parent().get_parent() as ShiMonster


func _draw() -> void:
	if host == null:
		return
	if host.is_group_leader():
		for index: int in 3:
			var angle: float = host.spin_phase + index * TAU / 3.0
			_draw_slime(Vector2.RIGHT.rotated(angle) * 11.0, index)
	else:
		_draw_slime(Vector2.ZERO, 0)


func _draw_slime(center: Vector2, variant: int) -> void:
	var fill := Color("6cae70") if variant != 1 else Color("84ba75")
	draw_set_transform(center)
	draw_circle(Vector2(0, 0), 9.0, Color("244835"))
	draw_circle(Vector2(0, -1), 8.0, fill)
	draw_rect(Rect2(-8, 1, 16, 5), fill)
	draw_arc(Vector2(0, -1), 5.5, PI * 1.1, PI * 1.8, 12, Color("b6e3a9"), 2.0)
	draw_circle(Vector2(-3, 0), 1.4, Color("1f382b"))
	draw_circle(Vector2(3, 0), 1.4, Color("1f382b"))
	draw_line(Vector2(-1, 3), Vector2(1, 3), Color("274d34"), 1.0)
	draw_set_transform(Vector2.ZERO)
