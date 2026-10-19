
class_name Weakness
extends AlchemicalData

## 虚弱：施加虚弱 buff，目标出手造成的伤害按百分比降低（写回宿主的 damage_dealt）。

@export var buff: BuffData = preload("res://resources/buffs/weakness.tres")

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)


func _default_polarity() -> POLARITY:
	return POLARITY.NEGATIVE

