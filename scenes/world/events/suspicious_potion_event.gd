class_name SuspiciousPotionEvent
extends WorldEvent

## 可疑药水：先调查再决定拿不拿。
## 拿取后可能是真药水，也可能是药水小偷；被偷的物品可以再按 E 取回。

enum State {
	HIDDEN = 0,
	REVEALED = 1,
	STOLEN = 2,
}

var _state: int = State.HIDDEN
var _stolen_item_id: int = -1
var _stolen_amount: int = 0


func bind(id_value: StringName, seed_value: int) -> void:
	super.bind(id_value, seed_value)
	_state = State.HIDDEN
	_stolen_item_id = -1
	_stolen_amount = 0


func prompt_text() -> String:
	match _state:
		State.HIDDEN:
			return "E · 调查可疑药水"
		State.REVEALED:
			return "E · 拿走可疑药水"
		State.STOLEN:
			return "E · 取回被偷物品"
	return "E · 调查"


func interact(player: PlayerCharacter) -> bool:
	if not can_interact(player):
		return false
	match _state:
		State.HIDDEN:
			_state = State.REVEALED
			_notify("瓶子里似乎有东西在动……")
			queue_redraw()
			return true
		State.REVEALED:
			if _rng.randf() < 0.65:
				_give_potion(player, "拿到一瓶")
				_finish()
			else:
				var stolen: Dictionary = _steal_random(player)
				if stolen.is_empty():
					_notify("药水化作一团烟雾消失了")
					_finish()
				else:
					_stolen_item_id = int(stolen["item_id"])
					_stolen_amount = int(stolen["amount"])
					_state = State.STOLEN
					_notify("药水小偷抢走了 %s ×%d，按 E 取回" % [
						_item_name(_stolen_item_id), _stolen_amount
					])
					queue_redraw()
			return true
		State.STOLEN:
			_restore_item(player, _stolen_item_id, _stolen_amount)
			_notify("你取回了 %s ×%d" % [_item_name(_stolen_item_id), _stolen_amount])
			_finish()
			return true
	return false


func _draw() -> void:
	var bob: float = sin(_time * 2.6) * 1.5
	var bottle := Vector2(0, -3 + bob)
	draw_circle(Vector2(0, 6), 10.0, Color("2a1b2d", 0.25))
	if _state == State.STOLEN:
		# 小赃物袋
		draw_circle(Vector2(0, -2 + bob), 8.0, Color("6f5134"))
		draw_circle(Vector2(0, -2 + bob), 6.0, Color("9a7447"))
		draw_line(Vector2(-5, -9 + bob), Vector2(5, -9 + bob), Color("d8b56a"), 2.0)
		draw_line(Vector2(-4, -8 + bob), Vector2(0, -13 + bob), Color("d8b56a"), 1.5)
		draw_line(Vector2(4, -8 + bob), Vector2(0, -13 + bob), Color("d8b56a"), 1.5)
	else:
		var liquid: Color = Color("9b68d6") if _state == State.HIDDEN else Color("d66a8f")
		draw_rect(Rect2(bottle + Vector2(-4, -2), Vector2(8, 9)), Color("4d3b33"))
		draw_rect(Rect2(bottle + Vector2(-3, -1), Vector2(6, 6)), liquid)
		draw_rect(Rect2(bottle + Vector2(-1, -5), Vector2(2, 4)), Color("d7d0b4"))
		draw_circle(bottle + Vector2(0, 2), 1.4, Color("f3d6ff"))
	var pulse: float = 0.4 + sin(_time * 3.4) * 0.2
	if _state == State.REVEALED:
		draw_arc(Vector2(0, -2 + bob), 14.0, 0.0, TAU, 20, Color(1.0, 0.35, 0.35, pulse), 1.0)
	# 问号提示
	draw_line(Vector2(8, -17 + bob), Vector2(9, -19 + bob), Color(1.0, 0.9, 0.55, pulse), 2.0)
	draw_circle(Vector2(10, -16 + bob), 1.0, Color(1.0, 0.9, 0.55, pulse))
	if _highlighted:
		draw_arc(Vector2(0, 0), 18.0, 0.0, TAU, 24, Color("ffe6a0"), 1.2)