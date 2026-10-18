
class_name Invisibility
extends AlchemicalData

## 隐身：施加隐身 buff（标记类效果，宿主实现 set_buff_flag 才会被通知）。

@export var buff: BuffData = preload("res://resources/buffs/invisible.tres")


##目前不参与反应

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
