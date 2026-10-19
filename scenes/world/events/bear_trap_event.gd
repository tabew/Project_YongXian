class_name BearTrapEvent
extends WorldEvent

## 捕兽夹：玩家或怪物踩到会受伤；靠近按 E 可以拆解，获得石头。

const DAMAGE: float = 8.0
const TRIGGER_RADIUS: float = 14.0

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
	var circle := CircleShape2D.new()
	circle.radius = TRIGGER_RADIUS
	shape_node.shape = circle
	_area.add_child(shape_node)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)


func prompt_text() -> String:
	return "E · 拆解捕兽夹"


func interact(player: PlayerCharacter) -> bool:
	if not can_interact(player):
		return false
	_give_item(player, 1, 2, "拆下捕兽夹，获得")
	_finish()
	return true


func _on_body_entered(body: Node2D) -> void:
	if _sprung or not _is_damage_target(body):
		return
	_sprung = true
	if body is PlayerCharacter:
		(body as PlayerCharacter).take_damage(DAMAGE, self)
		_notify("捕兽夹合拢，受到 %d 点伤害" % int(DAMAGE))
	elif body is BaseMonster:
		(body as BaseMonster).apply_chain_damage(DAMAGE, self)
	queue_redraw()


func _finish() -> void:
	if _area != null:
		_area.set_deferred("monitoring", false)
	super._finish()


func _draw() -> void:
	draw_circle(Vector2(0, 5), 15.0, Color("1f241d", 0.28))
	# 底座
	draw_circle(Vector2(0, 0), 13.0, Color("3b3f3a"))
	draw_circle(Vector2(0, 0), 10.0, Color("5b6157"))
	# 上下夹齿
	for side: int in [-1, 1]:
		var y: float = float(side) * 8.0
		draw_line(Vector2(-12, y), Vector2(12, y), Color("9da493"), 3.0)
		for index: int in 5:
			var x: float = -8.0 + float(index) * 4.0
			draw_line(Vector2(x, y), Vector2(x, y - float(side) * 5.0), Color("d0d5c1"), 1.5)
	# 中央弹簧
	draw_circle(Vector2(0, 0), 4.0, Color("7b5f3d"))
	draw_circle(Vector2(0, 0), 2.0, Color("c49a61"))
	if _sprung:
		draw_line(Vector2(-8, 0), Vector2(8, 0), Color("c44a3f"), 2.0)
		draw_circle(Vector2(0, 0), 2.5, Color("e35b4f"))
	if _highlighted:
		draw_arc(Vector2(0, 0), 19.0, 0.0, TAU, 24, Color("ffe6a0"), 1.2)