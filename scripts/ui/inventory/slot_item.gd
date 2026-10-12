extends Control

class_name SlotItem

##背包内物品图标数量显示

@onready var item_texture: TextureRect = $ItemTexture
@onready var amount_label:Label = $AmountLabel

@export var count:int = 0 #数量

# ==============================================================================
# ↓↓↓↓ item_list 注册表重构段：种类看 item_id，需要实例时从 ItemListGlobal 取 ↓↓↓↓
# ==============================================================================
##物品id，判断是不是同一种物品只看这个
@export var item_id:int = -1
##物品模板实例，由 ItemListGlobal 注册表提供，只用于取图标等展示数据。
##故意写成 Variant：只拿得到物品id的调用(slot_item.item = 物品id)也能直接赋值，
##赋进来的id会在setter里去注册表取模板，取不到则为null。
var item: Variant = null:
	get:
		return _item
	set(value):
		_item = _resolve_item(value)

var _item:ItemData = null


##把赋进来的值统一变成 ItemData 实例：实例原样返回，id 走注册表
func _resolve_item(value: Variant) -> ItemData:

	if value is ItemData:
		return value

	if value is int:
		var id:int = value
		if id >= 0 and ItemListGlobal.has_template(id):
			return ItemListGlobal.get_template(id)

	return null


##由物品id设置本格物品：id是种类依据，模板从注册表取
func set_item_id(id:int) -> void:
	item_id = id
	item = id


##构造：物品用id给，实例由注册表解析
func _init(item_id_:int = -1,count_:int = 1) -> void:
	item_id = item_id_
	item = item_id_
	count = count_
# ==============================================================================
# ↑↑↑↑ item_list 注册表重构段（结束）↑↑↑↑
# ==============================================================================

##物品显示更新函数，更新数量和图标
func slot_item_update()->void:

	#只登记了id没有实例时，从注册表补上
	if _item == null and item_id >= 0:
		item = item_id

	if !_item: return

	if count <= 0:
		item_texture.self_modulate.a = 0.4
	else:
		item_texture.self_modulate.a = 1
	item_texture.visible = true
	item_texture.texture = _item.texture

	if count >1:
		amount_label.visible = true
		amount_label.text = str(count)
	else :
		amount_label.visible = false
