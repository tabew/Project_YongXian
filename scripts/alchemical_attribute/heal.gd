class_name Heal
extends AlchemicalData

func interact(attribute:Array[AlchemicalData],which:int = 1) ->Array[AlchemicalData]:
	var result:Array[AlchemicalData]

	if attribute.is_empty():
		return result

	#单属性反应一定优先是第一个，多属性反应才需要单独遍历数组内其它属性
	#相同属性但不能升级的情况就continue，其它情况直接break，无需遍历
	for i in attribute.size():
		match attribute[i].attribute_id:
			AlchemicalAttributeList.ATTRIBUTE.HEAL:
				if !can_upgrade_level(attribute[i]):
					continue

				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.HEAL, level+1))

			AlchemicalAttributeList.ATTRIBUTE.HOLY:
				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.CONTINUOUS_HEAL,level))


		#除了升级会continue外，其它情况直接break
		break
	return result
			

## 按最大生命百分比回复：等级 1/2/3 对应 30% / 45% / 60%。
##
## 生命刻度统一到 100 点之后，固定值回复在玩家与怪物两边都没有可感知的分量，
## 所以这里按“目标自己的生命上限”算比例。玩家走 PlayerCharacter.heal()，
## 因此受“药材学”与“以血换知”影响；怪物没有 heal()，直接补给它的生命组件。
const BASE_RATIO: float = 0.30
const RATIO_PER_LEVEL: float = 0.15


func heal_ratio() -> float:
	return BASE_RATIO + RATIO_PER_LEVEL * float(maxi(level - 1, 0))


## 回血成功后给目标挂上"治疗抵抗"，期间带 heal 的物品不会恢复生命。
const HEAL_RESIST_ID: StringName = &"heal_resist"
const HEAL_RESIST_BUFF: BuffData = preload("res://resources/buffs/heal_resist.tres")


##目标是否被治疗抵抗挡着（等价于"现在不能通过 heal 回血"）
func is_heal_resisted(object: Node) -> bool:
	if object == null or not is_instance_valid(object):
		return false
	return Buffs.has(object, HEAL_RESIST_ID)


func use_effect(object:Node = null) -> void:
	if object == null:
		return

	if is_heal_resisted(object):
		return

	var maximum: float = _max_health_of(object)
	if maximum <= 0.0:
		return
	var amount: float = maximum * heal_ratio()
	var healed: float = 0.0

	if object.has_method("heal"):
		healed = float(object.call("heal", amount))
	else:
		healed = _heal_component(object, amount)

	if healed > 0.0 and HEAL_RESIST_BUFF != null:
		Buffs.apply(object, HEAL_RESIST_BUFF, 0)


func _max_health_of(object: Node) -> float:
	if "max_health" in object:
		return float(object.get("max_health"))
	var health: Node = object.get_node_or_null("Health")
	return float(health.get("max_health")) if health != null else 0.0


##怪物恢复：生命组件已经死了就不再回复。返回实际回复量
func _heal_component(object: Node, amount: float) -> float:
	var health: Node = object.get_node_or_null("Health")
	if health == null or not health.has_method("heal"):
		return 0.0
	return float(health.call("heal", amount))
