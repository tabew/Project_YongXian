class_name TrappedChestEvent
extends WorldEvent

## 陷阱宝箱：先检查，再拆机关。
## 拆除成功给一瓶药水和材料；失败会受到一次伤害。

var _inspected: bool = false


func bind(id_value: StringName, seed_value: int) -> void:
	super.bind(id_value, seed_value)
	_inspected = false


func prompt_text() -> String:
	return "E · 拆除机关" if _inspected else "E · 检查陷阱宝箱"


func interact(player: PlayerCharacter) -> bool:
	if not can_interact(player):
		return false
	if not _inspected:
		_inspected = true
		_notify("发现一根连着锁孔的细线")
		queue_redraw()
		return true
	if _rng.randf() < 0.7:
		_give_potion(player, "宝箱里找到一瓶")
		var item_id: int = MATERIAL_POOL[_rng.randi_range(0, MATERIAL_POOL.size() - 1)]
		_give_item(player, item_id, 2, "宝箱里还有")
	else:
		player.take_damage(6.0, self)
		_notify("机关触发，受到 6 点伤害")
	_finish()
	return true


func _draw() -> void:
	draw_rect(Rect2(-14, 7, 28, 5), Color("1f241d", 0.25))
	# 箱体
	draw_rect(Rect2(-12, -8, 24, 17), Color("3e3027"))
	draw_rect(Rect2(-10, -6, 20, 13), Color("95603c"))
	draw_rect(Rect2(-9, -5, 18, 3), Color("bc8c51"))
	draw_line(Vector2(-10, 0), Vector2(10, 0), Color("493427"), 2.0)
	for x: int in [-8, 6]:
		draw_rect(Rect2(x, -7, 3, 15), Color("b6b69c"))
	# 锁扣与红宝石
	draw_rect(Rect2(-3, -3, 6, 7), Color("d8c58c"))
	draw_circle(Vector2(0, 0), 2.0, Color("c44a3f") if _inspected else Color("7b3b35"))
	if _inspected:
		draw_line(Vector2(0, 4), Vector2(14, 12), Color("d8c58c"), 1.0)
		draw_circle(Vector2(14, 12), 1.5, Color("e35b4f"))
	if _highlighted:
		draw_rect(Rect2(-15, -11, 30, 24), Color("ffe6a0"), false, 1.2)