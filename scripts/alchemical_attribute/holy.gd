extends AlchemicalData

class_name Holy

func _init(set_level:int = 0) -> void:
	level = set_level
	max_level = 0

func interact(attribute:Array[AlchemicalData],which:int = 1) ->Array[AlchemicalData]:
	var result:Array[AlchemicalData]

	if attribute.is_empty():
		return result

	#单属性反应一定优先是第一个，多属性反应才需要单独遍历数组内其它属
	#相同属性但不能升级的情况就continue，其它情况直接break，无需遍历
	for i in attribute.size():
		match attribute[i].attribute_id:
			pass
		break
	return result
			

func use_effect(object:Node) -> void:
	pass
