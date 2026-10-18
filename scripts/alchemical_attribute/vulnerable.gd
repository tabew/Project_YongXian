
class_name Vulnerable
extends AlchemicalData

## 易伤：施加易伤 buff，目标受到的伤害按百分比增加（写回宿主的 damage_taken）。

@export var buff: BuffData = preload("res://resources/buffs/vulnerable.tres")

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)


func _default_polarity() -> POLARITY:
	return POLARITY.NEGATIVE

