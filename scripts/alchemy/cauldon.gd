extends StaticBody2D

@onready var attributes_text:AttributesText = $AttributesText
@onready var start_button:Button = $Button

##判断反应是否结束
var flag:bool = false

var attribute:Array[AlchemicalData]
##正在反应属性指针
var transforming_attribute:AlchemicalData
##将与指针反应的属性数组
var prepared_attribute:Array[AlchemicalData]
##已经反应了的属性数组
var has_transform:Array[AlchemicalData]


##得到材料的所以炼金属性
func _get_attributes(body: Node2D) -> void:
	if body is IngredientModel:

		var ingredient_data := (body as IngredientModel).data

		for i in ingredient_data.alchemical_attribute.size():
			attribute.append(ingredient_data.alchemical_attribute[i])
			
			attributes_text.add_text(ingredient_data.alchemical_attribute[i])

		body.queue_free()

##坩埚中属性显示更新
func text_update():
	attributes_text.reset()
	for i in attribute.size():
		attributes_text.add_text(attribute[i])

##开始反应
func start_transform() -> void:
	while true:
		#反应彻底完成
		if flag:
			break

		flag = true

		for i in attribute.size():
			
			transforming_attribute = attribute[i]

			#遍历其它属性，检测是否可以与之反应
			for j in attribute.size():
				if i == j:
					continue
				
				if transforming_attribute.can_interact_with(attribute[j]):
					prepared_attribute.append(attribute[j])
			
			var result = transforming_attribute.interact(prepared_attribute)
			var transformed = transforming_attribute.interact(prepared_attribute,2)

			#如果发生了反应，那么新属性可能参与新反应，故反应会继续，对新数组遍历
			if !result.is_empty():

				flag = false

				for k in result.size():
					attribute.append(result[k])

				for k in transformed.size():
					has_transform.append(transformed[k])

		for i in has_transform.size():
			attribute.erase(has_transform[i])
	
	text_update()
