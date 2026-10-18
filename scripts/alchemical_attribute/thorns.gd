
class_name Thorns
extends AlchemicalData

## 荆棘：施加荆棘 buff，持有期间受到伤害会把一部分弹回攻击者（比例按等级放大）。

@export var buff: BuffData = preload("res://resources/buffs/thorns.tres")

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
