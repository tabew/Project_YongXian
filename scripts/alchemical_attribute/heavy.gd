
class_name Heavy
extends AlchemicalData

## 沉重：附魔专用。命中时按概率把目标砸晕（眩晕 buff 是硬控）。

##基础眩晕概率
@export_range(0.0, 1.0, 0.01) var stun_chance: float = 0.25
##每级追加的概率
@export_range(0.0, 1.0, 0.01) var stun_chance_per_level: float = 0.10
##眩晕 buff
@export var stun_buff: BuffData = preload("res://resources/buffs/stun.tres")


##本次命中的眩晕概率
func stun_chance_total() -> float:
	return clampf(stun_chance + stun_chance_per_level * float(maxi(level, 0)), 0.0, 1.0)


func use_effect(object: Node = null) -> void:
	if object == null or not is_instance_valid(object):
		return
	if randf() > stun_chance_total():
		return
	if stun_buff != null:
		Buffs.apply(object, stun_buff, level)
