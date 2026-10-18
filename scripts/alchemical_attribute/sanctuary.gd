
class_name Sanctuary
extends AlchemicalData

## 圣佑：施加上圣佑 buff（受到的伤害降低、并缓慢回复）。
## 原来挂在神圣身上，现在独立成属性。

@export var buff: BuffData = preload("res://resources/buffs/holy.tres")


func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
