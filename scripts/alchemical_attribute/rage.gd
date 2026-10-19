
class_name Rage
extends AlchemicalData

## 暴怒：施加暴怒 buff，暴击率提高

@export var buff: BuffData = preload("res://resources/buffs/rage.tres")


##暂时没有反应配方

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
