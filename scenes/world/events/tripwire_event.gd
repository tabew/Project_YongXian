class_name TripwireEvent
extends WorldEvent

## 绊索：玩家或怪物经过会受伤；靠近按 E 拆掉，获得木棍。

const DAMAGE: float = 5.0
const AREA_SIZE: Vector2 = Vector2(34.0, 16.0)

var _sprung: bool = false
var _area: Area2D = null


func _ready() -> void:
	super._ready()
	_area = Area2D.new()
	_area.name = "Trigger"
	_area.collision_layer = 0
	_area.collision_mask = 3
	_area.monitoring = true
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = AREA_SIZE
	shape_node.shape = rectangle
	_area.add_child(shape_node)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)


func prompt_text() -> String:
	return "E · 拆除绊索"


func interact(player: PlayerCharacter) -> bool:
	if not can_interact(player):
		return false
	_give_item(player, 2, 2, "拆下绊索，获得")
	_finish()
	return true


func _on_body_entered(body: Node2D) -> void:
	if _sprung or not _is_damage_target(body):
		return
	_sprung = true
	if body is PlayerCharacter:
		(body as PlayerCharacter).take_damage(DAMAGE, self)
		_notify("绊索拉紧，受到 %d 点伤害" % int(DAMAGE))
	elif body is BaseMonster:
		(body as BaseMonster).apply_chain_damage(DAMAGE, self)
	queue_redraw()


func _finish() -> void:
	if _area != null:
		_area.set_deferred("monitoring", false)
	super._finish()


func _draw() -> void:
	draw_rect(Rect2(-17, 5, 34, 5), Color("1f241d", 0.22))
	# 两侧木桩
	for x: int in [-15, 15]:
		draw_rect(Rect2(float(x) - 2, -5, 4, 14), Color("6b4c33"))
		draw_rect(Rect2(float(x) - 3, -6, 6, 3), Color("a77a4d"))
	# 绊索
	if _sprung:
		draw_line(Vector2(-14, -1), Vector2(-4, 4), Color("8d9383"), 1.5)
		draw_line(Vector2(14, -1), Vector2(5, 5), Color("8d9383"), 1.5)
		draw_circle(Vector2(0, 5), 2.5, Color("5b5b50"))
	else:
		draw_line(Vector2(-14, -1), Vector2(14, -1), Color("d8c58c"), 1.5)
		draw_line(Vector2(-14, -1), Vector2(14, -1), Color("8d9383"), 0.8)
	# 小石块
	for point: Vector2 in [Vector2(-6, 7), Vector2(4, 8), Vector2(9, 6)]:
		draw_rect(Rect2(point - Vector2(2, 2), Vector2(4, 4)), Color("777b70"))
	if _highlighted:
		draw_rect(Rect2(-19, -10, 38, 24), Color("ffe6a0"), false, 1.2)