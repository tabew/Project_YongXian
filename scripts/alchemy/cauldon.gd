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
##本回合已经被消耗的属性数组
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
		has_transform.clear()

		for i in attribute.size():

			transforming_attribute = attribute[i]

			#本回合已经被消耗的属性不能再当反应主体，否则两个属性会反复互相反应、重复产出
			if has_transform.has(transforming_attribute):
				continue

			prepared_attribute.clear()

			#遍历其它属性，检测是否可以与之反应
			for j in attribute.size():
				if i == j:
					continue

				#本回合已经被消耗的属性不再参与反应
				if has_transform.has(attribute[j]):
					continue

				if transforming_attribute.can_interact_with(attribute[j]):
					prepared_attribute.append(attribute[j])

			#没有反应物就不要调用反应函数
			if prepared_attribute.is_empty():
				continue

			var result = transforming_attribute.interact(prepared_attribute)
			var transformed = transforming_attribute.interact(prepared_attribute,2)

			#如果发生了反应，那么新属性可能参与新反应，故反应会继续，对新数组遍历
			if !result.is_empty():

				flag = false

				for k in result.size():
					attribute.append(result[k])

				for k in transformed.size():
					has_transform.append(transformed[k])

		#本回合结束，统一把被消耗的属性从坩埚里移除。
		for i in has_transform.size():
			attribute.erase(has_transform[i])

	flag = false
	text_update()
