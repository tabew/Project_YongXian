
class_name Woody
extends AlchemicalData

## 木质
## 与其它属性保持同一种实现方式：反应用枚举 id + AlchemicalAttributeList.create(枚举, 等级)；
## 使用效果统一走 Buffs 入口，属性只做施加器。

func use_effect(object: Node = null) -> void:
	pass
