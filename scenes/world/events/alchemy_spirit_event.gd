class_name AlchemySpiritEvent
extends WorldEvent

## 炼金残影：送一瓶随机药水，偶尔再留下一点材料。


func prompt_text() -> String:
	return "E · 接受炼金残影的赠礼"


func interact(player: PlayerCharacter) -> bool:
	if not can_interact(player):
		return false
	if not _give_potion(player, "炼金残影送给你一瓶"):
		_notify("残影散开了")
	else:
		if _rng.randf() < 0.35:
			var item_id: int = MATERIAL_POOL[_rng.randi_range(0, MATERIAL_POOL.size() - 1)]
			_give_item(player, item_id, 2, "残影还留下了")
	_finish()
	return true


func _draw() -> void:
	var bob: float = sin(_time * 2.2) * 2.0
	draw_circle(Vector2(0, 6), 11.0, Color("10251f", 0.25))
	# 半透明残影
	draw_circle(Vector2(0, -7 + bob), 11.0, Color("65d6c4", 0.22))
	draw_circle(Vector2(0, -8 + bob), 7.0, Color("a6f0dd", 0.55))
	draw_circle(Vector2(-3, -10 + bob), 1.2, Color("163a34"))
	draw_circle(Vector2(3, -10 + bob), 1.2, Color("163a34"))
	draw_line(Vector2(-2, -5 + bob), Vector2(2, -5 + bob), Color("2a6d60"), 1.0)
	# 手中的药水
	var bottle := Vector2(10, -4 + bob)
	draw_rect(Rect2(bottle + Vector2(-3, -2), Vector2(6, 8)), Color("4d3b33"))
	draw_rect(Rect2(bottle + Vector2(-2, -1), Vector2(4, 5)), Color("8fd6c0"))
	draw_rect(Rect2(bottle + Vector2(-1, -5), Vector2(2, 4)), Color("d7d0b4"))
	# 漂浮光点
	var pulse: float = 0.45 + sin(_time * 3.2) * 0.2
	draw_circle(Vector2(-11, -18 + bob), 1.5, Color(0.75, 1.0, 0.9, pulse))
	draw_circle(Vector2(12, -20 + bob), 1.2, Color(0.75, 1.0, 0.9, pulse))
	if _highlighted:
		draw_arc(Vector2(0, 0), 20.0, 0.0, TAU, 24, Color("ffe6a0"), 1.2)