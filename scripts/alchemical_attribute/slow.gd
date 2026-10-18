
class_name Slow
extends AlchemicalData

## 迟缓：施加减速 buff

@export var buff: BuffData = preload("res://resources/buffs/slow.tres")

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)


func _default_polarity() -> POLARITY:
	return POLARITY.NEGATIVE

