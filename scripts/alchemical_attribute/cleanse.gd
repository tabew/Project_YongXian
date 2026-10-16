
class_name Cleanse
extends AlchemicalData

## 净化：消除目标身上所有减益

func interact(attribute: Array[AlchemicalData], which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	if attribute.is_empty():
		return result

	for i in attribute.size():
		match attribute[i].attribute_id:
			AlchemicalAttributeList.ATTRIBUTE.POISON:
				#以净化解毒，得到治疗
				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.HEAL, level))

		break
	return result

func use_effect(object: Node = null) -> void:
	Buffs.clear_debuffs(object)
