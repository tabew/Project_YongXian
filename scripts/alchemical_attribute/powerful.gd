
class_name Powerful
extends AlchemicalData

## 力量：施加攻击力 buff（写回宿主的 damage_dealt，武器结算伤害时乘算）。

@export var buff: BuffData = preload("res://resources/buffs/powerful.tres")

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
