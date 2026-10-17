
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


##作用圈每次结算对圈内目标造成的伤害
@export_range(0.0, 100.0, 0.5) var zone_damage: float = 3.0
##每级追加的圈伤害
@export_range(0.0, 100.0, 0.5) var zone_damage_per_level: float = 1.5


##作用圈每次结算的伤害（0 级 = zone_damage，逐级提高）
func zone_damage_total() -> float:
	return zone_damage + zone_damage_per_level * float(maxi(level, 0))


func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)


func _default_polarity() -> POLARITY:
	return POLARITY.NEGATIVE
