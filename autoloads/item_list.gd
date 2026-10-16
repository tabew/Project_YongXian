extends Node

##材料注册表
##id -> 模板资源。其它脚本要造材料实例时走这里，不要各自 new。

##模板清单
#用资源引用(preload)而不是字符串路径：字符串路径不被导出器跟踪，
@export var templates: Array[ItemData] = [
	preload("res://resources/items/ingredients/herb.tres"),
	preload("res://resources/items/ingredients/stone.tres"),
	preload("res://resources/items/ingredients/stick.tres"),
	preload("res://resources/items/ingredients/give_fur.tres"),
	preload("res://resources/items/ingredients/monkey_hide.tres"),
	preload("res://resources/items/ingredients/crocodile_eye.tres"),
	preload("res://resources/items/ingredients/crocodile_shell.tres"),
	preload("res://resources/items/ingredients/sharp_tooth.tres"),
	preload("res://resources/items/ingredients/slime_liquid.tres"),
	preload("res://resources/items/ingredients/sticky_ball.tres"),
	preload("res://resources/items/ingredients/rabbit_hide.tres"),
	preload("res://resources/items/ingredients/shabei_meat.tres"),
	preload("res://resources/items/ingredients/carrot.tres"),
	preload("res://resources/items/weapons/longsword.tres"),
	preload("res://resources/items/weapons/spear.tres"),
	preload("res://resources/items/weapons/yoyo.tres"),
	preload("res://resources/items/weapons/thunder_yoyo.tres"),
	preload("res://resources/items/weapons/hive_yoyo.tres"),
	preload("res://resources/items/ingredients/bomb.tres"),
	#药水模板始终保持在最后一个
	preload("res://resources/items/potions/potion_model.tres")
]

##id -> 模板
var table: Dictionary[int, ItemData] = {}

##id -> 运行时实例。药水每瓶 id 唯一、属性在装瓶时才算出来，
##登记在这里之后，所有"按 id 取数据"的地方(背包/格子/拖拽/使用/悬停提示)都能取回正确的那一瓶。
var runtime_instances: Dictionary[int, ItemData] = {}


##登记一个运行时实例，键就是它自己的 id。id 无效或已被占用时返回 false。
func register_instance(instance: ItemData) -> bool:

	if instance == null or instance.id < 0:
		return false

	if runtime_instances.has(instance.id):
		push_warning("ItemList: 运行时实例 id %d 已被占用，登记失败" % instance.id)
		return false

	runtime_instances[instance.id] = instance

	return true


##注销运行时实例：物品真正用掉之后调用，避免表只增不减。
##已经交出去的引用(比如砸在路上的药水模型、碎点上的圆形范围)各自持有 Resource，不受影响。
func unregister_instance(id: int) -> void:

	if runtime_instances.has(id):
		runtime_instances.erase(id)


##这个 id 是不是登记过的运行时实例
func has_runtime_instance(id: int) -> bool:

	return runtime_instances.has(id)

const POTION_ID_STRAT:int = 300

func _ready() -> void:
	_build_table()

##是否注册过该id
func has_template(id: int) -> bool:

	if runtime_instances.has(id):
		return true

	if id>=POTION_ID_STRAT:
		return true

	return table.has(id)


##取模板
func get_template(id: int) -> ItemData:

	if runtime_instances.has(id):
		return runtime_instances[id]


	if id >=POTION_ID_STRAT:
		return table[POTION_ID_STRAT]

	if !table.has(id):
		push_warning("ItemList: 物品id %d 未注册" % id)
		return null

	return table[id]


##按 id 造一个新实例。
##必须在方法里调用，不要在 ItemData._init里调用：
##建表的过程本身就是在 load 模板，那时表还没建完。
func create(id: int) -> ItemData:
	var template: ItemData = get_template(id)

	if template == null:
		return null

	var instance: ItemData = template.duplicate()

	var attribute_copy: Array[AlchemicalData] = []
	attribute_copy.assign(template.alchemical_attribute)
	instance.alchemical_attribute = attribute_copy

	var physical_copy: Array[PhysicalData] = []
	physical_copy.assign(template.physical_attribute)
	instance.physical_attribute = physical_copy

	return instance


func _build_table() -> void:
	table.clear()

	for template: ItemData in templates:
		if template == null:
			continue

		#键直接取模板自己的 id
		var id: int = template.id

		if table.has(id):
			push_warning("ItemList: 物品id %d 重复，后一张模板被忽略" % id)
			continue

		table[id] = template
