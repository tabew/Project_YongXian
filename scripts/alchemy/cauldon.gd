extends StaticBody2D

@onready var attributes_text:AttributesText = $AttributesText

##判断反应是否结束
var flag:bool = false

var attribute:Array[AlchemicalData]
##正在反应属性指针
var transforming_attribute:AlchemicalData
##将与指针反应的属性数组
var prepared_attribute:Array[AlchemicalData]
##本回合已经被消耗的属性数组
var has_transform:Array[AlchemicalData]

@export var player:PlayerCharacter

var inventory:Inventory

##只有开始反应过才允许装瓶，
var has_started:bool = false

func _ready() -> void:
	#药水要进玩家背包：场景里没连线时按分组找主角，和背包 UI 取主角的方式保持一致
	if player == null:
		player = get_tree().get_first_node_in_group("player") as PlayerCharacter

	if player != null:
		inventory = player.inventory

##得到材料的所以炼金属性
func _get_attributes(body: Node2D) -> void:
	if body is ItemModel:

		var ingredient_data := (body as ItemModel).data

		for i in ingredient_data.alchemical_attribute.size():
			var attr = normalize_level(ingredient_data.alchemical_attribute[i])

			attribute.append(attr)

			attributes_text.add_text(attr)

		body.queue_free()

		# 投了新料
		has_started = false

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


	has_started = true

##必须已经按过开始，且锅里还有反应完的属性
func can_finish_transform() -> bool:

	return has_started and !attribute.is_empty()


##装瓶
##药水不可堆叠，每瓶都有自己的id
func finish_transform() -> PotionData:

	if !can_finish_transform():
		return null

	if inventory == null:
		push_warning("Cauldon: 没有拿到玩家背包，药水装瓶失败")
		return null

	var potion:PotionData = PotionData.create_from_attributes(attribute)

	if potion == null:
		return null

	inventory.add_item(potion.id,1)

	#装完就清锅：药水已经在背包里了，锅里不该还留着能再装一次的东西
	attribute.clear()
	attributes_text.reset()
	has_started = false

	return potion

##等级归一化
func normalize_level(attribute:AlchemicalData)->AlchemicalData:
	if attribute.max_level>0:
		if attribute.level == 0:
			attribute.level = 1

	return attribute
