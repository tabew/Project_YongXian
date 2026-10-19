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
	#药水/其它路径：按属性自己的自伤数值结算
	_detonate_at(object, player_damage_total())


##武器附魔命中时的爆炸：只炸敌人，不结算玩家自伤。
##近战贴脸时爆心就在自己脚下（半径 30 起步，几乎必然罩住玩家），
##附魔还带自伤就变成"每次命中都掉血"，所以附魔这一路固定不自伤。
func apply_weapon_enchant(target: Node, _hit: CombatHit) -> void:
	_detonate_at(target, 0.0)


##在 object 的位置炸一次；self_damage <= 0 表示完全不碰玩家（不扣血也不推人）
func _detonate_at(object: Node, self_damage: float) -> void:

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
	effect.call("detonate", blast_radius(), enemy_damage(), self_damage, knockback, point,hit_mask)

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


##本次爆炸对玩家的伤害（只有药水这条路会结算；附魔走 apply_weapon_enchant，固定为 0）
func player_damage_total() -> float:
	var effect_level:float = sqrt(level + 1)
	return player_damage * effect_level


func _default_polarity() -> POLARITY:
	return POLARITY.NEGATIVE
