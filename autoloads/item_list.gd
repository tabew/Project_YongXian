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
	preload("res://resources/items/weapons/longsword.tres"),
	preload("res://resources/items/weapons/long_staff.tres"),
	#药水模板始终保持在最后一个
	preload("res://resources/items/potions/potion_model.tres")
]

##id -> 模板
var table: Dictionary[int, ItemData] = {}

const POTION_ID_STRAT:int = 300

func _ready() -> void:
	_build_table()

##是否注册过该id
func has_template(id: int) -> bool:
	if id>=POTION_ID_STRAT:
		return true

	return table.has(id)


##取模板
func get_template(id: int) -> ItemData:

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

	#物品模板在运行期只读，浅拷贝就够
	var instance: ItemData = template.duplicate()

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
