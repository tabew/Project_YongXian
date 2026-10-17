
class_name BindingAttribute
extends AlchemicalData

## 固结:提供减伤

@export var buff: BuffData = preload("res://resources/buffs/solid.tres")


func interact(attribute: Array[AlchemicalData], which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	if attribute.is_empty():
		return result

	#单属性反应一定优先是第一个，多属性反应才需要单独遍历数组内其它属性
	for i in attribute.size():
		match attribute[i].attribute_id:
			AlchemicalAttributeList.ATTRIBUTE.POISON:
				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.SLOW, level))

			AlchemicalAttributeList.ATTRIBUTE.FIRE:
				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.LINGER, level))

		#一轮只看第一个反应物，判定完直接结束
		break
	return result


func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
