extends AlchemicalData

class_name ContinuousHeal

@export var buff: BuffData = preload("res://resources/buffs/regen.tres")


##同属性可以互相强化（和 heal 一样：两份同级合成更高一级）
func interact(attribute: Array[AlchemicalData], which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	if attribute.is_empty():
		return result

	for i in attribute.size():
		match attribute[i].attribute_id:
			AlchemicalAttributeList.ATTRIBUTE.CONTINUOUS_HEAL:
				if !can_upgrade_level(attribute[i]):
					continue

				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.CONTINUOUS_HEAL, level + 1))

			
			AlchemicalAttributeList.ATTRIBUTE.BINDING:
				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.ABSORB, level))

		#除了升级会continue外，其它情况直接break
		break
	return result


##生效方式：把 buff 施加到目标身上
func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
