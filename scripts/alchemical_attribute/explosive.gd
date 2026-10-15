extends AlchemicalData

class_name Explosive

var explode:PackedScene = preload("res://scenes/effects/explode.tscn")

# ===== AI 修改开始 (爆炸参数：都可以在 Inspector 里调，按属性等级加算) =====
##爆炸半径(像素)：每级再加 radius_per_level
@export_range(4.0, 400.0, 1.0) var explosion_radius: float = 200.0
@export_range(0.0, 100.0, 1.0) var radius_per_level: float = 8.0
##对敌人的伤害：和武器一个量级(长剑18)
@export_range(0.0, 1000.0, 1.0) var damage: float = 18.0
@export_range(0.0, 1000.0, 1.0) var damage_per_level: float = 8.0
##对玩家的伤害：玩家只有10点血，单独一套小数值
@export_range(0.0, 100.0, 1.0) var player_damage: float = 1.0
@export_range(0.0, 100.0, 1.0) var player_damage_per_level: float = 0.0
##击退强度：和武器定义里的 knockback 同一套用法(长剑110)
@export_range(0.0, 2000.0, 1.0) var knockback: float = 1000
##击退随距离衰减：圈边还剩多少倍(1=不衰减，越靠近爆心越接近满值)
@export_range(0.0, 1.0, 0.05) var knockback_edge_scale: float = 0.3
##衰减曲线：1=线性；越大越集中在爆心，越小越平
@export_range(0.25, 4.0, 0.05) var knockback_falloff_power: float = 1.0
##受击盒所在层：和 weapon_definition.hit_mask 默认值一致(4 = EnemyHurtbox)
@export_flags_2d_physics var hit_mask: int = 4
# ===== AI 修改结束 =====

func use_effect(object:Node = null) -> void:
	# ===== AI 修改开始 (爆炸：在生效处炸一次，圈内敌人和玩家都吃伤害与击退) =====
	if object == null or not (object is Node2D):
		return

	var point: Node2D = object as Node2D
	var world: Node = point.get_parent()

	if world == null:
		return

	var effect: Node2D = explode.instantiate() as Node2D

	if effect == null:
		return

	#不改动 explode.tscn：脚本在运行时挂到它的根节点上，场景里只保留你自己的节点；
	#范围形状仍然用它自带的 Area2D/CollisionShape2D，半径按这次爆炸的数值缩放
	effect.set_script(ExplodeEffect)
	world.add_child(effect)
	effect.global_position = point.global_position
	effect.call("detonate", blast_radius(), enemy_damage(), player_damage_total(), knockback, hit_mask, point,
		knockback_edge_scale, knockback_falloff_power)
	# ===== AI 修改结束 =====

# ===== AI 修改开始 (按属性等级换算爆炸数值) =====
##本次爆炸的半径
func blast_radius() -> float:
	return explosion_radius + radius_per_level * float(maxi(level, 0))


##本次爆炸对敌人的伤害
func enemy_damage() -> float:
	return damage + damage_per_level * float(maxi(level, 0))


##本次爆炸对玩家的伤害
func player_damage_total() -> float:
	return player_damage + player_damage_per_level * float(maxi(level, 0))
# ===== AI 修改结束 =====
