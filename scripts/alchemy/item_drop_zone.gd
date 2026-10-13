extends Control
##材料投放区,把背包里拖出来的材料丢到本区域，

@export var spawn_pos:Node2D

func _ready() -> void:
	spawn_pos = get_parent().get_parent().get_node("SpawnedItems")

##从拖拽载荷里取回物品模板实例
func _get_dragged_item(data: Variant) -> ItemData:

	if !(data is Dictionary):
		return null

	var item_id:int = int((data as Dictionary).get("item_id", -1))

	#不是物品载荷就直接当没有，别去注册表问不存在的id
	if item_id < 0 or !ItemListGlobal.has_template(item_id):
		return null

	return ItemListGlobal.get_template(item_id)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ingredient := _get_dragged_item(data) as ItemData

	if ingredient == null:
		return false

	return ingredient.get_item_scene() != null


##放下材料
func _drop_data(_at_position: Vector2, data: Variant) -> void:

	if !(data is Dictionary):
		return

	var ingredient := _get_dragged_item(data) as ItemData

	if ingredient == null:
		return

	if spawn_pos == null:
		return

	var model = ingredient.create_model()
	if model == null:
		return

	spawn_pos.add_child(model)

	model.global_position = get_global_mouse_position()
	model.global_rotation = float((data as Dictionary).get("rotation",0.0))
