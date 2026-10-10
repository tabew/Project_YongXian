extends Button

class_name BagUI
##背包ui，同步背包数据并显示和提供交互

@onready var bag_slot_container:GridContainer = $PanelContainer/MarginContainer/ScrollContainer/BagSlotContainer

@onready var item_for_button:Dictionary[ItemData,SlotButton]

@onready var inventory:Inventory = preload("res://resources/inventory/inventory.tres") #背包数据
@onready var slot_button:PackedScene = preload("res://scenes/ui/inventory/slot_button.tscn") #格子场景
@onready var slot_item:PackedScene = preload("res://scenes/ui/inventory/slot_item.tscn") #物品图标

func _ready() -> void:
	button_mask = MOUSE_BUTTON_MASK_LEFT

	inventory.inventory_update.connect(bag_update)
	
	bag_update()

##背包更新函数，同步背包数据
func bag_update() ->void:

	#加载背包内物品
	for i in range(inventory.has_items.size()):
		var item:ItemData = inventory.has_items[i]

		#判断是否已经加载了背包中的某个物品，已加载则跳过
		if item_for_button.has(item):
			continue

		var slot_item_:SlotItem = slot_item.instantiate()
		var slot_node: SlotButton = slot_button.instantiate()

		slot_item_.item = item
		slot_item_.count = inventory.items[item]

		bag_slot_container.add_child(slot_node)
		slot_node.slot_insert(slot_item_)

		item_for_button[item] = slot_node


func take_item(item:ItemData,num:int) ->void:
	inventory.remove_item(item,num)
	item_for_button[item].set_count(inventory.get_count(item))
	
func put_item(item:ItemData,num:int) ->void:
	inventory.add_item(item,num)
	item_for_button[item].set_count(inventory.get_count(item))

## 背包区域放回
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if !(data is Dictionary):
		return false
	return data.has("item")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	put_item(data.get("item"),data.get("count"))


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if Input.is_action_just_pressed("open_inventory"):
			visible = !visible
