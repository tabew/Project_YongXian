# ===== AI 新增文件 (急速：附魔专属，提高武器攻速) =====
class_name Haste
extends AlchemicalData

## 急速：附魔专属属性。命中后给持武器的人挂上"急速"增益，
## 提高出手速度（写回持有者的 attack_speed，出手阶段按 1+它 加快）。
## 只做武器附魔，不参与炼药反应。

##本属性施加的 buff：默认指向急速
@export var buff: BuffData = preload("res://resources/buffs/haste.tres")


##没有炼药反应配方
func interact(_attribute: Array[AlchemicalData], _which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	return result


func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
