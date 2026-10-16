extends AlchemicalData

class_name ContinuousHeal

##本属性施加的 buff
@export var buff: BuffData = preload("res://resources/buffs/regen.tres")


##生效方式：把 buff 施加到目标身上
func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)

