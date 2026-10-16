# ===== AI 新增文件 (火：独立脚本，与其它属性同一种实现方式) =====
class_name Fire
extends AlchemicalData

## 火：施加燃烧 buff，定时扣血。
## 与其它属性保持同一种实现方式：反应用枚举 id + AlchemicalAttributeList.create(枚举, 等级)；
## 使用效果统一走 Buffs 入口，属性只做施加器。

##本属性施加的 buff：默认指向燃烧，可在 Inspector 换成别的
@export var buff: BuffData = preload("res://resources/buffs/burn.tres")


##目前不参与反应（以后要配方就在 match 里按枚举写，写法参照 heal.gd）
func interact(_attribute: Array[AlchemicalData], _which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	return result


func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
