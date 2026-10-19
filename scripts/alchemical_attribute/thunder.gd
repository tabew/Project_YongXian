
class_name Thunder
extends AlchemicalData

## 雷，在目标位置落下一道雷，对落点半径内的目标造成伤害。

##每次落雷的伤害
@export var damage: float = 5.0
##每级追加的伤害
@export var damage_per_level: float = 2.0
##落雷的影响半径(像素)
@export_range(8.0, 400.0, 1.0) var strike_radius: float = 44.0
##作用圈每隔多久落一道雷(秒)
@export_range(0.1, 10.0, 0.1) var strike_interval: float = 1.0
##落雷特效场景
@export var strike_scene: PackedScene = preload("res://scenes/effects/lightning_strike.tscn")


##本次落雷的伤害
func damage_total() -> float:
	return damage + damage_per_level * float(maxi(level, 0))


##作用圈用这个间隔决定多久落一道雷
func zone_interval() -> float:
	return strike_interval


##就地落一道雷。object 是落点

func use_effect(object: Node = null) -> void:
	if object == null or not is_instance_valid(object) or not (object is Node2D):
		return

	var point: Node2D = object as Node2D
	var world: Node = point.get_parent()

	if world == null or strike_scene == null:
		return

	var strike: Node2D = strike_scene.instantiate() as Node2D

	if strike == null:
		return

	var exempt: Node = null

	if object.has_meta(SelfExempt.EXEMPT_META):
		exempt = object.get_meta(SelfExempt.EXEMPT_META)
	world.add_child(strike)
	strike.call("strike", point.global_position, damage_total(), strike_radius, exempt)


##落雷是负面效果
func _default_polarity() -> POLARITY:
	return POLARITY.NEGATIVE
