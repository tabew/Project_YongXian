class_name ItemData
extends Resource
##物品数据模板

@export var id:int #物品id
@export var name:String #物品名称
@export var texture:Texture2D #物品图标
@export var max_stack:int = 999 #最大堆叠数

func use() -> void:
	pass

