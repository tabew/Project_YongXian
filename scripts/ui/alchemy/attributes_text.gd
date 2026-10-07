extends Control

class_name AttributesText

@onready var container:GridContainer = $PanelContainer/MarginContainer/TextContainer

@onready var alchemical_text_scene:PackedScene = preload("res://scenes/ui/alchemy/alchemical_text.tscn")

func add_text(attribute:AlchemicalData)->void:
	var alchemical_text:AlchemicalText = alchemical_text_scene.instantiate()

	container.add_child(alchemical_text)
	alchemical_text.alchemical_text_update(attribute)

func reset()->void:
	var texts:= container.get_children()

	for i in container.get_child_count():
		texts[i].queue_free()
