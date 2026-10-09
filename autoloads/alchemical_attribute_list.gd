extends Node

##炼金属性注册表
##id -> 模板资源。其它脚本要造炼金属性实例时走这里，不要各自 new。

enum ATTRIBUTE
{
    HEAL = 0,
	HOLY = 1,
	CONTINUOUS_HEAL = 2,
}



##模板清单
#用资源引用(preload)而不是字符串路径：字符串路径不被导出器跟踪，
@export var templates: Array[AlchemicalData] = [
	preload("res://resources/alchemical_attribute/heal.tres"),
	preload("res://resources/alchemical_attribute/holy.tres"),
	preload("res://resources/alchemical_attribute/continuous_heal.tres")
]

##id -> 模板
var table: Dictionary[int, AlchemicalData] = {}


func _ready() -> void:
	_build_table()

##取模板
func get_template(id: int) -> AlchemicalData:

	return table[id]


##按 id 造一个新实例。
##必须在方法里调用，不要在 AlchemicalData._init里调用：
##建表的过程本身就是在 load 模板，那时表还没建完。
func create(id: int, level: int = 0) -> AlchemicalData:
	var template: AlchemicalData = get_template(id)

	if template == null:
		return null

	#白名单在运行期只读，浅拷贝就够
	var instance: AlchemicalData = template.duplicate()
	instance.level = level

	return instance


func _build_table() -> void:
	table.clear()

	for template: AlchemicalData in templates:
		if template == null:
			continue

		#键直接取模板自己的 attribute_id
		var id: int = template.attribute_id

		if table.has(id):
			continue

		table[id] = template
