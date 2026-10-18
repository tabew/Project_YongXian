
class_name Guard
extends AlchemicalData

## 护体：施加防御 buff（写回 Health.defense / 玩家 defense）

@export var buff: BuffData = preload("res://resources/buffs/defense_up.tres")

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
