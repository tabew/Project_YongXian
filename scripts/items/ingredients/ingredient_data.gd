
extends ItemData

class_name IngredientData
##材料数据脚本

@export var for_use_attribute:Array[AlchemicalData] = []


##默认使用方式：左键。把使用属性作用到自己身上。
##负面效果（会造成伤害/减益的，例如雷、爆炸、迟缓）作用在脚下，
##但把自己标成豁免对象，避免材料把自己劈了或炸了。
func left_use(player: PlayerCharacter) -> int:
	if player == null or not is_instance_valid(player) or for_use_attribute.is_empty():
		return 0
	var used: bool = false

	for attribute: AlchemicalData in for_use_attribute:
		if attribute == null:
			continue
		if attribute.is_negative_effect():
			player.set_meta(SelfExempt.EXEMPT_META, player)
			attribute.use_effect(player)
			player.remove_meta(SelfExempt.EXEMPT_META)
		else:
			attribute.use_effect(player)
		used = true
	return 1 if used else 0
