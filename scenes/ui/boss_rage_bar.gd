class_name BossRageBar
extends Control

const SEGMENT_COUNT: int = 10
const RAGE_PER_SEGMENT: int = 100

var current_rage: int = 0
var charging: bool = false


func set_rage(value: int, is_charging: bool) -> void:
	if current_rage == value and charging == is_charging:
		return
	current_rage = clampi(value, 0, SEGMENT_COUNT * RAGE_PER_SEGMENT)
	charging = is_charging
	queue_redraw()


func _draw() -> void:
	var gap: float = 3.0
	var width: float = (size.x - 2.0 - gap * float(SEGMENT_COUNT - 1)) / float(SEGMENT_COUNT)
	if width <= 2.0 or size.y <= 4.0:
		return
	var fill: Color = Color("f06442") if charging else Color("f0a04d")
	for index: int in SEGMENT_COUNT:
		var x: float = 1.0 + float(index) * (width + gap)
		draw_rect(Rect2(x, 1.0, width, size.y - 2.0), Color("282329"))
		var portion: float = clampf(float(current_rage - index * RAGE_PER_SEGMENT) / float(RAGE_PER_SEGMENT), 0.0, 1.0)
		if portion > 0.0:
			draw_rect(Rect2(x + 1.0, 2.0, (width - 2.0) * portion, size.y - 4.0), fill)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
