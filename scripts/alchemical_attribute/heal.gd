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
## 走 PlayerCharacter.heal，因此受“药材学”与“以血换知”影响。
const BASE_RATIO: float = 0.30
const RATIO_PER_LEVEL: float = 0.15


func use_effect(object:Node) -> void:
	if object == null or not object.has_method("heal"):
		return
	var maximum: float = 0.0
	if "max_health" in object:
		maximum = float(object.get("max_health"))
	if maximum <= 0.0:
		return
	var ratio: float = BASE_RATIO + RATIO_PER_LEVEL * float(maxi(level - 1, 0))
	object.call("heal", maximum * ratio)
