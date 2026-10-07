extends Control

class_name SlotItem

##背包内物品图标数量显示

@onready var item_texture: TextureRect = $ItemTexture
@onready var amount_label:Label = $AmountLabel

@export var item:ItemData = null #物品类型
@export var count:int = 0 #数量

func _init(item_:ItemData = null,count_:int = 1) -> void:
	item = item_
	count = count_

##物品显示更新函数，更新数量和图标
func slot_item_update()->void:
	if !item: return

	if count <= 0:
		item_texture.self_modulate.a = 0.4
	else:
		item_texture.self_modulate.a = 1
	item_texture.visible = true
	item_texture.texture = item.texture

	if count >1:
		amount_label.visible = true
		amount_label.text = str(count)
	else :
		amount_label.visible = false
