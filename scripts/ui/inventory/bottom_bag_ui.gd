extends Control

@onready var handy_slot_container:HBoxContainer = $PanelContainer/MarginContainer/HBoxContainer

@onready var item_buttons:Array[SlotButton]

@onready var slot_item:PackedScene = preload("res://scenes/ui/inventory/slot_item.tscn") #物品图标

@export var player:PlayerCharacter
var inventory:Inventory

func _ready() -> void:
	
	inventory = player.inventory
	inventory.inventory_update.connect(bag_update)
	
	init_button()
	bag_update()

func init_button() -> void:
	for child in handy_slot_container.get_children():
		item_buttons.append(child)

##背包更新函数，同步背包数据
func bag_update() ->void:

	#加载背包内物品
	for item in inventory.handy_items_pos:
		var pos = inventory.handy_items_pos[item]

		var slot_item_:SlotItem = slot_item.instantiate()

		slot_item_.item = item
		slot_item_.count = inventory.items[item]

		if item_buttons[pos].slot_item != null:
			if item_buttons[pos].slot_item.item.id != slot_item_.item.id:
				item_buttons[pos].queue_free()
			else :
				item_buttons[pos].slot_item.count = slot_item_.count
				continue

		item_buttons[pos].slot_insert(slot_item_)
		
		
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if Input.is_action_just_pressed("alchemy_menu"):
			visible = !visible
