
class_name BindingAttribute
extends AlchemicalData

## 固结:提供减伤

@export var buff: BuffData = preload("res://resources/buffs/solid.tres")

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
