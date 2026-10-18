
class_name Fortify
extends AlchemicalData

## 强身：施加强身 buff，临时增加最大生命上限(加空血)。

@export var buff: BuffData = preload("res://resources/buffs/fortify.tres")

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
