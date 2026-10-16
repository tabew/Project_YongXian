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


func use_effect(object:Node = null) -> void:
	if object == null:
		return
	var maximum: float = _max_health_of(object)
	if maximum <= 0.0:
		return
	var amount: float = maximum * heal_ratio()
	if object.has_method("heal"):
		object.call("heal", amount)
		return
	_heal_component(object, amount)


func _max_health_of(object: Node) -> float:
	if "max_health" in object:
		return float(object.get("max_health"))
	var health: Node = object.get_node_or_null("Health")
	return float(health.get("max_health")) if health != null else 0.0


##怪物恢复：生命组件已经死了就不再回复
func _heal_component(object: Node, amount: float) -> void:
	var health: Node = object.get_node_or_null("Health")
	if health == null or not health.has_method("heal"):
		return
	health.call("heal", amount)
