extends RigidBody2D

class_name IngredientModel
##材料互动脚本

@export var data:ItemData;

func _ready() -> void:
	add_to_group("ingredients")


