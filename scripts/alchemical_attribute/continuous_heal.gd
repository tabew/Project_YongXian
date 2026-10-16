extends AlchemicalData

class_name ContinuousHeal

## 持续回复：先立刻回一小口，再挂一段按秒回复的 buff。
##
## 按秒回复交给 buff 系统（BuffData + BuffHolder），所以 HUD 的 buff 条会显示剩余时间；
## 立刻回的那一口按目标生命上限算，玩家与怪物两边才有可感知的分量。
const INSTANT_RATIO: float = 0.10

##本属性施加的 buff
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


func use_effect(object: Node = null) -> void:
	if object == null:
		return
	_instant_heal(object)
	if buff != null:
		Buffs.apply(object, buff, maxi(level, 1))


func _instant_heal(object: Node) -> void:
	var maximum: float = 0.0
	if "max_health" in object:
		maximum = float(object.get("max_health"))
	else:
		var health: Node = object.get_node_or_null("Health")
		if health != null:
			maximum = float(health.get("max_health"))
	if maximum <= 0.0:
		return
	var amount: float = maximum * INSTANT_RATIO
	if object.has_method("heal"):
		object.call("heal", amount)
		return
	var health: Node = object.get_node_or_null("Health")
	if health != null and health.has_method("heal"):
		health.call("heal", amount)
