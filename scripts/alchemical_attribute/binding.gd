# ===== AI 新增文件 (固结：独立脚本，与其它属性同一种实现方式) =====
class_name BindingAttribute
extends AlchemicalData

## 固结（材料本性）：矿物 + 木质的反应产物，惰性终产物，不再参与任何反应。
## 与其它属性保持同一种实现方式：使用效果统一走 Buffs 入口，属性只做施加器。

##本属性产生的使用效果：留空表示不产生效果
@export var buff: BuffData = null


##惰性终产物：不与任何属性反应
func interact(_attribute: Array[AlchemicalData], _which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	return result


func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
