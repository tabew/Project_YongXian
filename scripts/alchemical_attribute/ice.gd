
class_name Ice
extends AlchemicalData

## 冰：给目标积累冰冻值；攒满后炸一次伤害并冻住目标（硬控）。
## 冰冻值记在目标自己身上，所以每个目标独立累积。

##每次施加积累多少冰冻值
@export var freeze_per_apply: float = 1.0
##每级追加的冰冻值
@export var freeze_per_apply_per_level: float = 0.5
##冰冻值攒到多少触发冰冻
@export_range(1.0, 50.0, 1.0) var freeze_threshold: float = 4.0
##触发时的伤害
@export var shatter_damage: float = 4.0
##每级追加的伤害
@export var shatter_damage_per_level: float = 2.0
##冰冻 buff
@export var freeze_buff: BuffData = preload("res://resources/buffs/frozen.tres")

##冰冻值存在目标身上的 meta 键
const FREEZE_META: StringName = &"ice_freeze_value"


##本次施加积累的冰冻值（吃药水强度：强药水冻得更快）
func freeze_value() -> float:
	return (freeze_per_apply + freeze_per_apply_per_level * float(maxi(level, 0))) * Buffs.power_scale()


##触发时的伤害（吃药水强度）
func shatter_damage_total() -> float:
	return (shatter_damage + shatter_damage_per_level * float(maxi(level, 0))) * Buffs.power_scale()


##目标当前的冰冻值（0 表示没在累积）
func freeze_of(object: Node) -> float:
	if object == null or not is_instance_valid(object):
		return 0.0
	return float(object.get_meta(FREEZE_META, 0.0))


func use_effect(object: Node = null) -> void:
	if object == null or not is_instance_valid(object):
		return

	var accumulated: float = freeze_of(object) + freeze_value()

	if accumulated < freeze_threshold:
		object.set_meta(FREEZE_META, accumulated)
		return

	#攒满：清零、炸一次伤害、冻住
	object.set_meta(FREEZE_META, 0.0)
	Buffs.hurt_entity(object, shatter_damage_total())
	if freeze_buff != null:
		Buffs.apply(object, freeze_buff, level)
