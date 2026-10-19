
class_name Agility
extends AlchemicalData

## 敏捷：施加敏捷 buff，增加攻速

@export var buff: BuffData = preload("res://resources/buffs/agility.tres")


##暂时没有反应配方

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
