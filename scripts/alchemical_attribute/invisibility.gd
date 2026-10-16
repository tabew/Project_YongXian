# ===== AI 新增文件 (隐身：独立脚本，与其它属性同一种实现方式) =====
class_name Invisibility
extends AlchemicalData

## 隐身：施加隐身 buff（标记类效果，宿主实现 set_buff_flag 才会被通知）。
## 与其它属性保持同一种实现方式：反应用枚举 id + AlchemicalAttributeList.create(枚举, 等级)；
## 使用效果统一走 Buffs 入口，属性只做施加器。

##本属性施加的 buff：默认指向隐身，可在 Inspector 换成别的
@export var buff: BuffData = preload("res://resources/buffs/invisible.tres")


##目前不参与反应（以后要配方就在 match 里按枚举写，写法参照 heal.gd）
func interact(_attribute: Array[AlchemicalData], _which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	return result


func use_effect(object: Node = null) -> void:
	if buff == null:
		return
	Buffs.apply(object, buff, level)
