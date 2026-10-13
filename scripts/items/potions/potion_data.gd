extends ItemData

class_name PotionData

##药水数据由坩埚里反应完的属性装瓶而来
##药水不可堆叠

##药水id的起始值
const NEW_POTION_ID:int = 300

##药水默认模板的id，配置在 resources/items/potions/potion_model.tres
const BASE_TEMPLATE_ID:int = 300


##本局已经发到哪个药水id了：必须放在静态段，
##静态的 create_from_attributes 只能碰静态成员，实例方法的计数器在它里面用不了
static var _next_potion_id:int = NEW_POTION_ID

static func next_potion_id() -> int:
	var potion_id:int = _next_potion_id
	_next_potion_id += 1

	return potion_id


##把坩埚里反应完的属性装成一瓶药水，并登记进 ItemListGlobal。
##attributes 为空或药水模板缺失时返回 null，调用方不要往背包里塞半成品。
static func create_from_attributes(attributes: Array[AlchemicalData]) -> PotionData:

	if attributes == null or attributes.is_empty():
		return null

	#模板走注册表：造实例统一从这里拿，不要各自 new
	var item_list:Node = _item_list()

	if item_list == null:
		return null

	var base:ItemData = item_list.get_template(BASE_TEMPLATE_ID)

	if base == null or !(base is PotionData):
		return null

	var potion:PotionData = (base as PotionData).duplicate() as PotionData

	#属性各自复制一份，药水不跟着材料模板走
	potion.alchemical_attribute.clear()

	for attribute:AlchemicalData in attributes:
		if attribute == null:
			continue

		potion.alchemical_attribute.append(attribute.duplicate())

	potion.id = next_potion_id()

	return potion


##取自动加载的物品注册表。
##药水脚本里再用自动加载名会绕成编译期循环引用，只能在运行期按节点取。
static func _item_list() -> Node:
	var tree:SceneTree = Engine.get_main_loop() as SceneTree

	if tree == null or tree.root == null:
		return null

	return tree.root.get_node_or_null("ItemListGlobal")
