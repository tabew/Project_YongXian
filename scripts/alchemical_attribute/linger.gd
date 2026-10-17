
class_name Linger
extends AlchemicalData

## 滞留：药水级修饰属性。
## 带滞留的药水，破碎后的作用圈会保留一段时间；

##0 级时作用圈持续多少秒
@export var seconds: float = 2.0
##每级增加多少秒
@export var seconds_per_level: float = 1.5


##作用圈应该持续多少秒
func linger_seconds() -> float:
	return seconds + seconds_per_level * float(maxi(level, 0))


func interact(attribute: Array[AlchemicalData], which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	if attribute.is_empty():
		return result

	for i in attribute.size():
		match attribute[i].attribute_id:
			AlchemicalAttributeList.ATTRIBUTE.LINGER:
				if !can_upgrade_level(attribute[i]):
					continue

				if which == 2:
					result.append(self)
					result.append(attribute[i])
				else:
					result.append(AlchemicalAttributeList.create(AlchemicalAttributeList.ATTRIBUTE.LINGER, level + 1))

		break
	return result


##本身不对生物产生效果
func use_effect(_object: Node = null) -> void:
	pass


func _default_polarity() -> POLARITY:
	return POLARITY.NEUTRAL
