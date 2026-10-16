
class_name Mineral
extends AlchemicalData

## 矿物
## 与其它属性保持同一种实现方式：反应用枚举 id + AlchemicalAttributeList.create(枚举, 等级)；
## 使用效果统一走 Buffs 入口，属性只做施加器。


func interact(attribute: Array[AlchemicalData], which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	if attribute.is_empty():
		return result

	#单属性反应一定优先是第一个，多属性反应才需要单独遍历数组内其它属性
	for i in attribute.size():
		match attribute[i].attribute_id:
			AlchemicalAttributeList.ATTRIBUTE.WOODY:
				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.BINDING, level))

			AlchemicalAttributeList.ATTRIBUTE.FIRE:

				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.SELF_EXEMPT, level))

		#一轮只看第一个反应物，判定完直接结束
		break
	return result


func use_effect(object: Node = null) -> void:
	pass
