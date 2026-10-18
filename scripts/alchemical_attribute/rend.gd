# ===== AI 新增文件 (裂伤：附魔专属，命中追加伤害) =====
class_name Rend
extends AlchemicalData

## 裂伤：附魔专属属性。命中时对被命中的目标追加一次固定伤害。
## 只做武器附魔，不参与炼药反应。

##0 级追加的伤害
@export var extra_damage: float = 2.0
##每级追加的伤害
@export var extra_damage_per_level: float = 1.5


##本次追加的伤害（0 级 = extra_damage，逐级提高）
func extra_total() -> float:
	return extra_damage + extra_damage_per_level * float(maxi(level, 0))


##没有炼药反应配方
func interact(_attribute: Array[AlchemicalData], _which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	return result


func use_effect(object: Node = null) -> void:
	if object == null or not is_instance_valid(object):
		return
	Buffs.hurt_entity(object, extra_total())
