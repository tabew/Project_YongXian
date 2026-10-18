extends Node

##炼金属性注册表
##id -> 模板资源。其它脚本要造炼金属性实例时走这里，不要各自 new。

enum ATTRIBUTE
{
	HEAL = 0,
	HOLY = 1,
	CONTINUOUS_HEAL = 2,
	MINERAL = 3,
	WOODY = 4,
	BINDING = 5,
	EXPLOSIVE = 6,
	FIRE = 7,
	INVISIBILITY = 8,
	SELF_EXEMPT = 9,
	POISON = 10,
	SLOW = 11,
	SWIFT = 12,
	GUARD = 13,
	POWERFUL = 14,
	CLEANSE = 15,
	THORNS = 16,
	WEAKNESS = 17,
	VULNERABLE = 18,
	LIFESTEAL = 19,
	FORTIFY = 20,
	ABSORB = 21,
	LINGER = 22,
	THUNDER = 23,
	RAGE = 24,
	AGILITY = 25,
	DEFTNESS = 26,
	SHARPNESS = 27,
	HASTE = 28,
	REND = 29,
	WATER = 30,
	EARTH = 31,
	METAL = 32,
	WIND = 33,
	FLOWER = 34,
	FLESH = 35,
	FUR = 36,
	BONE = 37,
	ACID = 38,
	OIL = 39,
	SALT = 40,
	ASH = 41,
}



##模板清单
#用资源引用(preload)而不是字符串路径：字符串路径不被导出器跟踪，
@export var templates: Array[AlchemicalData] = [
	preload("res://resources/alchemical_attribute/heal.tres"),
	preload("res://resources/alchemical_attribute/holy.tres"),
	preload("res://resources/alchemical_attribute/continuous_heal.tres"),
	preload("res://resources/alchemical_attribute/mineral.tres"),
	preload("res://resources/alchemical_attribute/woody.tres"),
	preload("res://resources/alchemical_attribute/binding.tres"),
	preload("res://resources/alchemical_attribute/explosive.tres"),
	preload("res://resources/alchemical_attribute/fire.tres"),
	preload("res://resources/alchemical_attribute/invisibility.tres"),
	preload("res://resources/alchemical_attribute/self_exempt.tres"),
	preload("res://resources/alchemical_attribute/poison.tres"),
	preload("res://resources/alchemical_attribute/slow.tres"),
	preload("res://resources/alchemical_attribute/swift.tres"),
	preload("res://resources/alchemical_attribute/guard.tres"),
	preload("res://resources/alchemical_attribute/powerful.tres"),
	preload("res://resources/alchemical_attribute/cleanse.tres"),
	preload("res://resources/alchemical_attribute/thorns.tres"),
	preload("res://resources/alchemical_attribute/weakness.tres"),
	preload("res://resources/alchemical_attribute/vulnerable.tres"),
	preload("res://resources/alchemical_attribute/lifesteal.tres"),
	preload("res://resources/alchemical_attribute/fortify.tres"),
	preload("res://resources/alchemical_attribute/absorb.tres"),
	# ===== AI 修改开始 (滞留) =====
	preload("res://resources/alchemical_attribute/linger.tres"),
	# ===== AI 修改结束 =====
	preload("res://resources/alchemical_attribute/thunder.tres"),
	preload("res://resources/alchemical_attribute/rage.tres"),
	preload("res://resources/alchemical_attribute/agility.tres"),
	preload("res://resources/alchemical_attribute/deftness.tres"),
	preload("res://resources/alchemical_attribute/sharpness.tres"),
	preload("res://resources/alchemical_attribute/haste.tres"),
	preload("res://resources/alchemical_attribute/rend.tres"),
	preload("res://resources/alchemical_attribute/water.tres"),
	preload("res://resources/alchemical_attribute/earth.tres"),
	preload("res://resources/alchemical_attribute/metal.tres"),
	preload("res://resources/alchemical_attribute/wind.tres"),
	preload("res://resources/alchemical_attribute/flower.tres"),
	preload("res://resources/alchemical_attribute/flesh.tres"),
	preload("res://resources/alchemical_attribute/fur.tres"),
	preload("res://resources/alchemical_attribute/bone.tres"),
	preload("res://resources/alchemical_attribute/acid.tres"),
	preload("res://resources/alchemical_attribute/oil.tres"),
	preload("res://resources/alchemical_attribute/salt.tres"),
	preload("res://resources/alchemical_attribute/ash.tres")
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
