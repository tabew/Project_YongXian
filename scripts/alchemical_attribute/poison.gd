
class_name Poison
extends AlchemicalData

## 毒性：施加中毒 buff，定时扣血。

@export var buff: BuffData = preload("res://resources/buffs/poison.tres")

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)

func _default_polarity() -> POLARITY:
	return POLARITY.NEGATIVE

