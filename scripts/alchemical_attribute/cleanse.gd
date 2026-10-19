
class_name Cleanse
extends AlchemicalData

## 净化：消除目标身上所有减益

func use_effect(object: Node = null) -> void:
	Buffs.clear_debuffs(object)
