extends StaticBody2D

@onready var attributes_text:AttributesText = $AttributesText

var attribute:Array[AlchemicalData];

##得到材料的所以炼金属性
func _get_attributes(body: Node2D) -> void:
	if body is IngredientModel:

		var ingredient_data := (body as IngredientModel).data

		for i in ingredient_data.alchemical_attribute.size():
			attribute.append(ingredient_data.alchemical_attribute[i])
			
			attributes_text.add_text(ingredient_data.alchemical_attribute[i])

		body.queue_free()
