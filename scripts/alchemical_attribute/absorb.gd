
class_name Absorb
extends AlchemicalData

## 吸收：施加吸收 buff。持有期间受到的伤害被反转成等量回复

@export var buff: BuffData = preload("res://resources/buffs/absorb.tres")

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
