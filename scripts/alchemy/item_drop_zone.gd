extends Control
##材料投放区,把背包里拖出来的材料丢到本区域，

@export var spawn_pos:Node2D

func _ready() -> void:
	spawn_pos = get_parent().get_parent().get_node("SpawnedItems")

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return ((data as Dictionary).get("item") as IngredientData).create_model() != null


##放下材料
func _drop_data(_at_position: Vector2, data: Variant) -> void:

	if !(data is Dictionary):
		return

	var ingredient := (data as Dictionary).get("item") as IngredientData

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
