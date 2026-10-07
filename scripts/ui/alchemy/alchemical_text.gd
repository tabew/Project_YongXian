extends Control

class_name AlchemicalText

##坩埚已有属性

@onready var amount_label:Label = $Label

##物品显示更新函数，更新数量和图标
func alchemical_text_update(attribute:AlchemicalData)->void:

	amount_label.text = str(attribute.name)


