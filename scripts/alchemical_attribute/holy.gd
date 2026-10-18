extends AlchemicalData

class_name Holy

##本属性施加的 buff：祝福（受到的回复量提高）
@export var buff: BuffData = preload("res://resources/buffs/blessing.tres")


func _init(set_level:int = 0) -> void:
	level = set_level
	max_level = 0

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
