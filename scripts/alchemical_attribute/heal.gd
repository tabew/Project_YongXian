class_name Heal
extends AlchemicalData

func _init(set_level:int = 0) -> void:
	level = set_level
	max_level = 3

func interact(attribute:Array[AlchemicalData],which:int = 1) ->Array[AlchemicalData]:
	var result:Array[AlchemicalData]

	if attribute.is_empty():
		return result

	#单属性反应一定优先是第一个，多属性反应才需要单独遍历数组内其它属性
	match  attribute[0]:
		Heal:
			if which == 2:
				result.append(self)
				result.append(attribute[0])

			else:
				result.append(Heal.new(2))

	return result
			

func use_effect(object:Node) -> void:
	pass


