extends StaticBody2D

@onready var attributes_text:AttributesText = $AttributesText

##判断反应是否结束
var flag:bool = false

var attributes:Array[AlchemicalData]
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

##药水默认模板的id，配置在 resources/items/potions/potion_model.tres
const BASE_TEMPLATE_ID:int = 300

func _ready() -> void:

	player = get_tree().get_first_node_in_group("player") as PlayerCharacter

	if player != null:
		inventory = player.inventory
	queue_redraw()


## 坩埚外观：像素风石锅（宽口圆肚）+ 绿色药液 + 炉火 + 蒸汽，替掉原来那张纯黑占位图。
func _draw() -> void:
	const IRON := Color("3c3a3f")
	const IRON_LIGHT := Color("5b5860")
	const IRON_DARK := Color("26242a")
	const BREW := Color("58b04a")
	const BREW_LIGHT := Color("8ede6c")
	const FIRE := Color("e79840")
	const GLOW := Color("ffd27a")
	# 炉火与光晕：在锅底下方。
	draw_circle(Vector2(0, 74), 96.0, Color(GLOW, 0.10))
	for index: int in 5:
		var x: float = float(index - 2) * 26.0
		var height: float = 30.0 + 16.0 * float(2 - absi(index - 2))
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(x - 13, 96), Vector2(x, 96 - height), Vector2(x + 13, 96)
			]),
			FIRE.darkened(0.12 * float(posmod(index, 2)))
		)
	# 锅身：自锅沿向下逐层收窄，做出宽口圆肚。
	var widths: Array[float] = [150, 150, 146, 138, 126, 110, 90, 66]
	var top: float = -44.0
	for index: int in widths.size():
		var half: float = widths[index] * 0.5
		draw_rect(
			Rect2(-half, top + float(index) * 18.0, widths[index], 18.0),
			IRON if index % 2 == 0 else IRON_DARK
		)
	# 左侧受光、右侧阴影。
	draw_rect(Rect2(-64, -36, 10, 118), IRON_LIGHT.darkened(0.1))
	draw_rect(Rect2(52, -30, 9, 100), IRON_DARK)
	# 锅沿。
	draw_rect(Rect2(-82, -62, 164, 12), IRON_LIGHT)
	draw_rect(Rect2(-82, -62, 164, 4), IRON_LIGHT.lightened(0.28))
	draw_rect(Rect2(-88, -50, 176, 6), IRON)
	# 药液与气泡。
	draw_rect(Rect2(-70, -52, 140, 20), BREW.darkened(0.3))
	draw_rect(Rect2(-64, -52, 128, 7), BREW)
	for index: int in 5:
		var bubble_x: float = -44.0 + float(index) * 22.0
		draw_circle(
			Vector2(bubble_x, -56.0 - float(posmod(index * 7, 6))),
			3.0 + float(posmod(index, 2)),
			BREW_LIGHT
		)
	# 蒸汽。
	for index: int in 3:
		draw_circle(
			Vector2(float(index) * 36.0 - 36.0, -88.0 - float(index) * 13.0),
			9.0 + float(index) * 3.0,
			Color(0.88, 0.95, 0.88, 0.13)
		)


##得到材料的所以炼金属性
func _get_attributes(body: Node2D) -> void:
	if body is ItemModel:

		var ingredient_data := (body as ItemModel).data

		for i in ingredient_data.alchemical_attribute.size():
			var attr: AlchemicalData = ingredient_data.alchemical_attribute[i].duplicate()
			attr.level = ingredient_data.alchemical_attribute[i].level
			attributes.append(normalize_level(attr))

			attributes_text.add_text(attr)

		body.queue_free()

		#材料本来就不在表里，unregister_instance 对它们是空操作
		if ingredient_data != null:
			ItemListGlobal.unregister_instance(ingredient_data.id)

		# 投了新料
		has_started = false

##坩埚中属性显示更新
func text_update():
	attributes_text.reset()
	for i in attributes.size():
		attributes_text.add_text(attributes[i])

##开始反应
func start_transform() -> void:
	while true:
		#反应彻底完成
		if flag:
			break

		flag = true
		has_transform.clear()

		for i in attributes.size():

			transforming_attribute = attributes[i]

			#本回合已经被消耗的属性不能再当反应主体，否则两个属性会反复互相反应、重复产出
			if has_transform.has(transforming_attribute):
				continue

			prepared_attribute.clear()

			#遍历其它属性，检测是否可以与之反应
			for j in attributes.size():
				if i == j:
					continue

				#本回合已经被消耗的属性不再参与反应
				if has_transform.has(attributes[j]):
					continue

				if transforming_attribute.can_interact_with(attributes[j]):
					prepared_attribute.append(attributes[j])

			#没有反应物就不要调用反应函数
			if prepared_attribute.is_empty():
				continue

			var result = transforming_attribute.interact(prepared_attribute)
			var transformed = transforming_attribute.interact(prepared_attribute,2)

			#如果发生了反应，那么新属性可能参与新反应，故反应会继续，对新数组遍历
			if !result.is_empty():

				flag = false

				for k in result.size():
					attributes.append(result[k])

				for k in transformed.size():
					has_transform.append(transformed[k])

		#本回合结束，统一把被消耗的属性从坩埚里移除。
		for i in has_transform.size():
			attributes.erase(has_transform[i])

	flag = false
	text_update()


	has_started = true

##必须已经按过开始，且锅里还有反应完的属性
func can_finish_transform() -> bool:

	return has_started and !attributes.is_empty()


##装瓶
##药水不可堆叠，每瓶都有自己的id
func finish_transform() -> PotionData:

	if !can_finish_transform():
		return null

	if inventory == null:
		push_warning("Cauldon: 没有拿到玩家背包，药水装瓶失败")
		return null

	var potion:PotionData = create_from_attributes()

	if potion == null:
		return null

	inventory.add_item(potion.id,1)
	_grant_alchemy_rewards(potion)

	#装完就清锅：药水已经在背包里了，锅里不该还留着能再装一次的东西
	attributes.clear()
	attributes_text.reset()
	has_started = false

	return potion

## 用运行期查找而不是全局标识符，保证本脚本仍能作为 --script 单元测试的编译依赖被加载。
func _notify(message: String) -> void:
	var event_bus: Node = get_node_or_null("/root/EventBus")
	if event_bus != null and event_bus.has_signal("notification"):
		event_bus.emit_signal("notification", message)


## 装瓶结算：给炼金经验，并按“炼金回响”概率额外产出一瓶。
func _grant_alchemy_rewards(potion:PotionData) -> void:
	if potion == null:
		return
	var progress: Node = get_node_or_null("/root/RunProgress")
	if progress == null:
		return
	var key: String = _recipe_key(potion)
	var highest: int = 0
	for attribute:AlchemicalData in potion.alchemical_attribute:
		if attribute != null:
			highest = maxi(highest, attribute.level)
	progress.add_experience(progress.alchemy_experience(key, highest))
	var echo: float = progress.alchemy_echo_chance()
	if echo > 0.0 and randf() < echo:
		var extra:PotionData = create_from_attributes()
		if extra != null:
			inventory.add_item(extra.id,1)
			_notify("炼金回响：额外产出一瓶药水")


## 配方身份：属性 id 排序后拼接，等级不影响身份。
func _recipe_key(potion:PotionData) -> String:
	var ids: Array[int] = []
	for attribute:AlchemicalData in potion.alchemical_attribute:
		if attribute != null:
			ids.append(attribute.attribute_id)
	ids.sort()
	var parts: PackedStringArray = []
	for id: int in ids:
		parts.append(str(id))
	return "-".join(parts)


##把坩埚里反应完的属性装成一瓶药水
func create_from_attributes() -> PotionData:

	if attributes == null or attributes.is_empty():
		return null

	var base:ItemData = ItemListGlobal.get_template(BASE_TEMPLATE_ID)

	if base == null or !(base is PotionData):
		return null

	var potion:PotionData = (base as PotionData).duplicate() as PotionData

	#属性各自复制一份
	potion.alchemical_attribute = []

	for attribute:AlchemicalData in attributes:
		if attribute == null:
			continue

		var attr = attribute.duplicate()
		attr.level = attribute.level
		potion.alchemical_attribute.append(attr)

	potion.id = PotionData.next_potion_id()

	while not ItemListGlobal.register_instance(potion):
		potion.id = PotionData.next_potion_id()

	return potion

##等级归一化
func normalize_level(attribute:AlchemicalData)->AlchemicalData:
	if attribute.max_level>0:
		if attribute.level == 0:
			attribute.level = 1

	return attribute
