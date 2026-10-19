class_name Deftness
extends AlchemicalData

## 灵巧：施加灵巧 buff，持有者的闪避次数回复速度提高（写回宿主的 dodge_recovery）。
## 目前不参与反应，配方后续再补。

##本属性施加的 buff：默认指向灵巧
@export var buff: BuffData = preload("res://resources/buffs/deftness.tres")


##暂时没有反应配方

func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
