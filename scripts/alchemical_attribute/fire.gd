
class_name Fire
extends AlchemicalData

@export var buff: BuffData = preload("res://resources/buffs/burn.tres")


func interact(attribute: Array[AlchemicalData], which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	if attribute.is_empty():
		return result

	#单属性反应一定优先是第一个，多属性反应才需要单独遍历数组内其它属性
	for i in attribute.size():
		match attribute[i].attribute_id:
			AlchemicalAttributeList.ATTRIBUTE.FIRE:
				if !can_upgrade_level(attribute[i]):
					continue

				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.FIRE, level + 1))

		#除了升级会continue外，其它情况直接break
		break
	return result


##每次结算对目标造成的伤害
@export_range(0.0, 100.0, 0.5) var damage: float = 3.0
##每级追加的伤害
@export_range(0.0, 100.0, 0.5) var damage_per_level: float = 1.5
##同一目标两次伤害之间的最小间隔(秒)
const DAMAGE_INTERVAL: float = 0.5

##每个目标上次被火伤害的时间
var _last_damage_ms: Dictionary = {}


##本次结算的伤害（0 级 = damage，逐级提高）
func damage_total() -> float:
	return damage + damage_per_level * float(maxi(level, 0))


func use_effect(object: Node = null) -> void:
	if buff != null:
		Buffs.apply(object, buff, level)
	_damage_target(object)


##对单个目标造成一次伤害，同一个目标按 DAMAGE_INTERVAL 限流
func _damage_target(object: Node) -> void:
	if object == null or not is_instance_valid(object):
		return
	var amount: float = damage_total()

	if amount <= 0.0:
		return

	var id: int = object.get_instance_id()
	var now: int = Time.get_ticks_msec()

	if now - int(_last_damage_ms.get(id, -1000000)) < int(DAMAGE_INTERVAL * 1000.0):
		return
	_last_damage_ms[id] = now
	Buffs.hurt_entity(object, amount)


func _default_polarity() -> POLARITY:
	return POLARITY.NEGATIVE
