
class_name Stamina
extends AlchemicalData

## 耐力：施加「耐力」buff，提高玩家的闪避次数上限；上限变高时立刻补上多出来的闪避次数。

@export var buff: BuffData = preload("res://resources/buffs/stamina.tres")


##没有炼药反应配方

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
