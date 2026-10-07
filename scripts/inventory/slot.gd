extends Resource

class_name Slot
##背包格子数据脚本，包含物品种类及数量

func _init(item_:ItemData = null,count_:int = 1) -> void:
	item = item_
	count = count_

@export var item:ItemData = null #物品类型
@export var count:int = 0 #数量