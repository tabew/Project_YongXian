
class_name Swift
extends AlchemicalData

## 迅捷：施加加速 buff

@export var buff: BuffData = preload("res://resources/buffs/swift.tres")

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
