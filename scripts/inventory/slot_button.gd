extends Button

##背包格子脚本

class_name SlotButton

signal mouse_button_left_press
signal mouse_button_right_press
signal has_been_free

@onready var center_container:CenterContainer = $WaitforImage/CenterContainer
@onready var background:ColorRect = $WaitforImage

var slot_item:SlotItem;

func  _ready() -> void:
	button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_RIGHT


##物品插入函数
func  slot_insert(SI:SlotItem)->void:
	slot_item = SI
	center_container.add_child(slot_item)
	slot_item.slot_item_update()

#接收鼠标左右键
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			mouse_button_left_press.emit()

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			mouse_button_right_press.emit()

##拿取物品
func take_item(inventory:Inventory,num:int = 1) -> SlotItem:

	inventory.remove_item(slot_item.item,num)

	slot_item.count -= num

	if slot_item.count <= 0:
		has_been_free.emit()
		center_container.remove_child(slot_item)
		queue_free()
	
	slot_item.slot_item_update()

	var mouse_slot_item:SlotItem = slot_item.duplicate()
	mouse_slot_item.count = 1

	return mouse_slot_item

func put_item(inventory:Inventory,mouse_item:SlotItem) -> void:

	inventory.add_item(mouse_item.item,mouse_item.count)

	slot_item.count += mouse_item.count

	slot_item.slot_item_update()
