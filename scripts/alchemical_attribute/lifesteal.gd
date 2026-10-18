
class_name Lifesteal
extends AlchemicalData

## 吸血：施加吸血 buff，持有者造成伤害时按比例回复生命（写回宿主的 lifesteal）。
## 作为武器附魔时改成"命中直接回血"：按本次伤害的比例立刻回复，不挂 buff。

@export var buff: BuffData = preload("res://resources/buffs/lifesteal.tres")
##附魔形态：回复本次伤害的比例
@export var hit_heal_ratio: float = 0.25
##每级追加的比例
@export var hit_heal_ratio_per_level: float = 0.10


##附魔时回复本次伤害的比例
func hit_heal_ratio_total() -> float:
	return maxf(hit_heal_ratio + hit_heal_ratio_per_level * float(maxi(level, 0)), 0.0)


##附魔命中：直接回复本次伤害的一部分，不再挂 buff
func apply_weapon_enchant(target: Node, hit: CombatHit) -> void:
	if hit == null:
		return
	Buffs.heal_entity(target, maxf(hit.damage, 0.0) * hit_heal_ratio_total())

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
