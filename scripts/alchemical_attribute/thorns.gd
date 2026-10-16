
class_name Thorns
extends AlchemicalData

## 荆棘：施加荆棘 buff，持有期间受到伤害会把一部分弹回攻击者（比例按等级放大）。

@export var buff: BuffData = preload("res://resources/buffs/thorns.tres")


func interact(attribute: Array[AlchemicalData], which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	if attribute.is_empty():
		return result

	for i in attribute.size():
		match attribute[i].attribute_id:
			AlchemicalAttributeList.ATTRIBUTE.THORNS:
				if !can_upgrade_level(attribute[i]):
					continue

				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.THORNS, level + 1))

		break
	return result


func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
