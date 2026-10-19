extends AlchemicalData

class_name Explosive

var explode:PackedScene = preload("res://scenes/effects/explode.tscn")

##爆炸半径(像素)
@export_range(4.0, 400.0, 1.0) var explosion_radius: float = 30.0
##对敌人的伤害
@export_range(0.0, 1000.0, 1.0) var damage: float = 18.0
##对玩家的伤害
@export_range(0.0, 100.0, 1.0) var player_damage: float = 1.0
##击退强度
@export_range(0.0, 2000.0, 1.0) var knockback: float = 500

##受击盒所在层：和 weapon_definition.hit_mask 默认值一致(4 = EnemyHurtbox)
@export_flags_2d_physics var hit_mask: int = 7

func use_effect(object:Node = null) -> void:

	if object == null or not (object is Node2D):
		return

	var point: Node2D = object as Node2D
	var world: Node = point.get_parent()

	if world == null:
		return

	var effect: Node2D = explode.instantiate() as Node2D

	if effect == null:
		return

	#设置爆炸特效
	effect.set_script(ExplodeEffect)
	world.add_child(effect)
	effect.global_position = point.global_position
	effect.call("detonate", blast_radius(), enemy_damage(), player_damage_total(), knockback, point,hit_mask)

##本次爆炸的半径
func blast_radius() -> float:
	var effect_level:float = sqrt(level + 1)
	return explosion_radius * effect_level


##本次爆炸对敌人的伤害
##吃药水强度（Buffs.power_scale）：药水砸碎时由药水设置，武器附魔/其它路径读到的都是 1.0。
##半径与"对玩家自己的自伤"不放大——高级炸弹药水不该把自己炸得更惨。
func enemy_damage() -> float:
	var effect_level:float = sqrt(level + 1)
	return damage * effect_level * Buffs.power_scale()


##本次爆炸对玩家的伤害
func player_damage_total() -> float:
	var effect_level:float = sqrt(level + 1)
	return player_damage * effect_level


func _default_polarity() -> POLARITY:
	return POLARITY.NEGATIVE

