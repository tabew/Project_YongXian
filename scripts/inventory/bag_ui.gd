extends Button

class_name BagUI
##背包ui，同步背包数据并显示和提供交互

@onready var bag_slot_container:GridContainer = $PanelContainer/MarginContainer/ScrollContainer/BagSlotContainer

@onready var item_for_button:Dictionary[ItemData,SlotButton]

@onready var inventory:Inventory = preload("res://resources/inventory/inventory.tres") #背包数据
@onready var slot_button:PackedScene = preload("res://scenes/ui/inventory/slot_button.tscn") #格子场景
@onready var slot_item:PackedScene = preload("res://scenes/ui/inventory/slot_item.tscn") #物品图标

var mouse_item:SlotItem = null #当前鼠标持有的物品

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
		slot_node.mouse_button_left_press.connect(mouse_left_slot_button.bind(slot_node))
		slot_node.has_been_free.connect(remove_button.bind(item))
		slot_node.slot_insert(slot_item_)

		item_for_button[item] = slot_node

##格子左键操作,拿取物品
func mouse_left_slot_button(slot_button_:SlotButton)->void:
	if !mouse_item:
		
		mouse_item = slot_button_.take_item(inventory)

		add_child(mouse_item)
		mouse_item.slot_item_update()

		item_follow_mouse()

##格子被释放
func remove_button(item:ItemData)->void:
	item_for_button.erase(item)

##物品放入背包
func _on_gui_input(event: InputEvent) -> void:
	if mouse_item:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:

				remove_child(mouse_item)

				if item_for_button.has(mouse_item.item):
					item_for_button[mouse_item.item].put_item(inventory,mouse_item)

				else: 
					var add_item = mouse_item.duplicate()
					inventory.add_item(add_item.item,add_item.count)

				mouse_item.queue_free()


##物品跟随光标函数
func item_follow_mouse() ->void:
	if !mouse_item:
		return
	
	mouse_item.global_position = get_global_mouse_position()

#输入事件函数
func _input(event: InputEvent) -> void:
	item_follow_mouse()
