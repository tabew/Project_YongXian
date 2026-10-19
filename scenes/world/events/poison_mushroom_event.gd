class_name PoisonMushroomEvent
extends WorldEvent

## 毒蘑菇：采集能得到材料，但有一半概率被孢子伤到。


func prompt_text() -> String:
	return "E · 采集毒蘑菇"


func interact(player: PlayerCharacter) -> bool:
	if not can_interact(player):
		return false
	_give_item(player, 0, 2, "采到毒蘑菇")
	if _rng.randf() < 0.5:
		player.take_damage(3.0, self)
		_notify("孢子散开，受到 3 点伤害")
	_finish()
	return true


func _draw() -> void:
	var bob: float = sin(_time * 2.0) * 1.0
	draw_circle(Vector2(0, 6), 10.0, Color("1f241d", 0.24))
	# 菌柄
	draw_rect(Rect2(-3, -2 + bob, 6, 10), Color("d8d0a8"))
	# 菌盖
	draw_circle(Vector2(0, -5 + bob), 10.0, Color("6f3d82"))
	draw_circle(Vector2(-3, -7 + bob), 8.0, Color("9350a8"))
	draw_circle(Vector2(-5, -9 + bob), 1.6, Color("e6c7ef"))
	draw_circle(Vector2(3, -10 + bob), 1.3, Color("e6c7ef"))
	draw_circle(Vector2(6, -6 + bob), 1.0, Color("e6c7ef"))
	# 孢子
	var pulse: float = 0.35 + sin(_time * 3.0) * 0.15
	draw_circle(Vector2(-11, -16 + bob), 1.3, Color(0.8, 0.55, 0.95, pulse))
	draw_circle(Vector2(9, -18 + bob), 1.0, Color(0.8, 0.55, 0.95, pulse))
	draw_circle(Vector2(0, -22 + bob), 0.9, Color(0.8, 0.55, 0.95, pulse))
	if _highlighted:
		draw_arc(Vector2(0, 0), 18.0, 0.0, TAU, 24, Color("ffe6a0"), 1.2)