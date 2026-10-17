class_name LightningStrike
extends Node2D

## 落雷：从上方劈下的一道雷，落地瞬间对半径内的目标各造成一次伤害。

##雷柱长度(像素)
@export var bolt_length: float = 140.0
##闪一下持续多久
@export var flash_seconds: float = 0.18
##检测层：1=玩家 2=怪物。按角色身体判定，不查受击盒
@export var hit_mask: int = 7

##落雷的影响半径(像素)
var radius: float = 44.0
##本次伤害
var damage: float = 0.0

var _left: float = 0.0
var _bolt: PackedVector2Array = PackedVector2Array()


##在 at 处落一道雷。exempt：这道雷不劈的对象（护己的使用者）
func strike(at: Vector2, amount: float, strike_radius: float, exempt: Node = null) -> void:
	global_position = at
	damage = maxf(amount, 0.0)
	radius = maxf(strike_radius, 1.0)
	_left = flash_seconds
	_roll_bolt()
	_deal_damage(exempt)
	queue_redraw()


func _process(delta: float) -> void:
	_left -= delta
	modulate.a = clampf(_left / maxf(flash_seconds, 0.01), 0.0, 1.0)
	if _left <= 0.0:
		queue_free()
	queue_redraw()


##掷一道带随机偏移的锯齿雷柱（纯视觉）
func _roll_bolt() -> void:
	_bolt = PackedVector2Array()
	var steps: int = 6

	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var offset: float = 0.0

		if i > 0 and i < steps:
			offset = randf_range(-7.0, 7.0)
		_bolt.append(Vector2(offset, -bolt_length * (1.0 - t)))


##落地伤害：半径内每个角色各结算一次，跳过 exempt（连着它下面的节点）
func _deal_damage(exempt: Node) -> void:
	if damage <= 0.0 or not is_inside_tree():
		return

	var shape: CircleShape2D = CircleShape2D.new()

	shape.radius = radius

	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()

	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = hit_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var done: Dictionary = {}

	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query):
		var target: Node = hit["collider"] as Node

		if target == null or done.has(target.get_instance_id()):
			continue
		if exempt != null and is_instance_valid(exempt) and (target == exempt or exempt.is_ancestor_of(target)):
			continue
		done[target.get_instance_id()] = true
		Buffs.hurt_entity(target, damage)


func _draw() -> void:
	if _bolt.size() < 2:
		return
	var alpha: float = clampf(_left / maxf(flash_seconds, 0.01), 0.0, 1.0)

	draw_circle(Vector2.ZERO, radius, Color(0.72, 0.86, 1.0, 0.10 * alpha))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(0.85, 0.94, 1.0, 0.45 * alpha), 1.0)
	draw_polyline(_bolt, Color(0.80, 0.92, 1.0, 0.85 * alpha), 4.0)
	draw_polyline(_bolt, Color(1.0, 1.0, 1.0, 0.95 * alpha), 1.5)
