# ===== AI 新增文件 (锋利：附魔专属，提高武器伤害) =====
class_name Sharpness
extends AlchemicalData

## 锋利：附魔专属属性。命中后给持武器的人挂上"锋利"增益，
## 提高武器伤害（写回持有者的 damage_add，武器结算时加在基础伤害上）。
## 只做武器附魔，不参与炼药反应。

##本属性施加的 buff：默认指向锋利
@export var buff: BuffData = preload("res://resources/buffs/edge.tres")


##没有炼药反应配方
func interact(_attribute: Array[AlchemicalData], _which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	return result


func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
