class_name WorldBarrel
extends Node2D

## 野外木桶：一击打碎，掉出木棍。
## 受击盒挂在战斗层上，所以武器挥击、爆炸、闪电这些伤害源都能把它打碎。

signal broken(barrel: WorldBarrel)

## 一下就打碎；想更耐打调大它。
const MAX_HEALTH: float = 1.0
## 与怪物受击盒同一层（4），武器与范围伤害的 mask 都覆盖这一层。
const HURTBOX_LAYER: int = 4
const BODY_SIZE := Vector2(12.0, 14.0)

var item_id: int = 1
var amount: int = 1

var _health: HealthComponent = null
var _hurtbox: CombatHurtbox = null
var _broken: bool = false


func bind(item: int, count: int) -> void:
	item_id = item
	amount = maxi(count, 1)


func _ready() -> void:
	_health = HealthComponent.new()
	_health.name = "Health"
	_health.max_health = MAX_HEALTH
	add_child(_health)
	_health.set_current_health(MAX_HEALTH)
	_health.died.connect(_on_died)
	_hurtbox = CombatHurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.health = _health
	_hurtbox.team = 2
	_hurtbox.collision_layer = HURTBOX_LAYER
	_hurtbox.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = BODY_SIZE
	shape.shape = rect
	shape.position = Vector2(0.0, -5.0)
	_hurtbox.add_child(shape)
	add_child(_hurtbox)
	queue_redraw()


func _on_died(_hit: CombatHit) -> void:
	if _broken:
		return
	_broken = true
	broken.emit(self)
	queue_free()


## 桶身：鼓形木桶 + 两道铁箍 + 竖向木条，脚下一点阴影。
func _draw() -> void:
	const WOOD := Color("8a5a34")
	const WOOD_DARK := Color("5f3c22")
	const WOOD_LIGHT := Color("b07a48")
	const HOOP := Color("4a4a52")
	draw_rect(Rect2(-7, -2, 14, 3), Color(0, 0, 0, 0.22))
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-6, -17), Vector2(6, -17), Vector2(7, -8), Vector2(6, -1), Vector2(-6, -1),
			Vector2(-7, -8)
		]),
		WOOD
	)
	for index: int in 3:
		var x: float = -4.0 + float(index) * 4.0
		draw_line(Vector2(x, -16), Vector2(x, -2), WOOD_DARK, 1.0)
	draw_rect(Rect2(-7, -15, 14, 3), HOOP)
	draw_rect(Rect2(-7, -6, 14, 3), HOOP)
	draw_rect(Rect2(-6, -18, 12, 2), WOOD_DARK)
	draw_rect(Rect2(-6, -16, 2, 14), WOOD_LIGHT)
