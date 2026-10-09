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
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.CONTINUOUS_HEAL))

		#除了升级会continue外，其它情况直接break
		break
	return result
			

func use_effect(object:Node) -> void:
	pass
