extends Button

class_name BagUI
##背包ui，同步背包数据并显示和提供交互

@onready var bag_slot_container:GridContainer = $PanelContainer/MarginContainer/ScrollContainer/BagSlotContainer

@onready var item_for_button:Dictionary[int,SlotButton]

@onready var slot_button:PackedScene = preload("res://scenes/ui/inventory/slot_button.tscn") #格子场景
@onready var slot_item:PackedScene = preload("res://scenes/ui/inventory/slot_item.tscn") #物品图标

@export var player:PlayerCharacter

var inventory:Inventory

func _ready() -> void:
	button_mask = MOUSE_BUTTON_MASK_LEFT
	
	player = get_tree().get_first_node_in_group("player")

	inventory = player.inventory
	inventory.inventory_update.connect(bag_update)
	
	bag_update()

##背包更新函数，同步背包数据
func bag_update() ->void:

	#加载背包内物品，has_items里装的是物品id
	for item_id in inventory.has_items:

		#判断是否已经加载了背包中的某个物品，已加载则跳过
		if item_for_button.has(item_id):
			item_for_button[item_id].set_count(inventory.get_count(item_id))
			continue

		var item:ItemData = inventory.get_item_template(item_id)

		if item == null:
			continue

		var slot_item_:SlotItem = slot_item.instantiate()
		var slot_node: SlotButton = slot_button.instantiate()

		slot_item_.set_item_id(item_id) # item_list 重构：id定种类，实例来自注册表
		slot_item_.count = inventory.items[item_id]

		bag_slot_container.add_child(slot_node)
		slot_node.take_item_signal.connect(take_item)
		slot_node.put_item_signal.connect(put_item)
		slot_node.quick_move_signal.connect(_on_slot_quick_move) #shift+左键：整堆挪进快捷栏
		slot_node.slot_insert(slot_item_)

		slot_node.tooltip_text = _build_item_tooltip(item)

		item_for_button[item_id] = slot_node


##拿取物品，item_id为物品id
func take_item(item_id:int,num:int) ->void:
	inventory.remove_item(item_id,num)

	if !item_for_button.has(item_id): #格子可能已经被释放
		return

	item_for_button[item_id].set_count(inventory.get_count(item_id))
	if item_for_button[item_id].slot_item.count <= 0:
		item_for_button.erase(item_id)
	
##放入物品，item_id为物品id
func put_item(item_id:int,num:int) ->void:
	inventory.add_item(item_id,num)

	if !item_for_button.has(item_id): #格子可能已经被释放
		return

	item_for_button[item_id].set_count(inventory.get_count(item_id))

#//////////////////////////快捷移动
##shift+左键：本格整堆挪进物品栏(快捷栏)
func _on_slot_quick_move(item_id:int,num:int) ->void:
	if inventory.quick_move_to_handy(item_id,num) <= 0:
		return

	_refresh_slot(item_id)

##背包里某种物品的数量变了就同步显示，整堆拿完就把格子收掉
func _refresh_slot(item_id:int) ->void:
	if !item_for_button.has(item_id):
		return

	var count:int = inventory.get_count(item_id)

	if count > 0:
		item_for_button[item_id].set_count(count)
		return

	item_for_button[item_id].queue_free()
	item_for_button.erase(item_id)
#///////////////////////////////////

## 背包区域放回
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if !(data is Dictionary):
		return false
	return data.has("item_id")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	put_item(data.get("item_id"),data.get("count"))

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if Input.is_action_just_pressed("open_inventory"):
			visible = !visible
			_input_update()
			return

		if Input.is_action_just_pressed("alchemy_menu"):
			visible = false

func _input_update():
	if visible:
		for item_id in item_for_button:
			item_for_button[item_id].queue_free()
		item_for_button.clear()
		bag_update()

##鼠标悬停提示的物品名，空一行后列出炼金属性。
func _build_item_tooltip(item: ItemData) -> String:

	if item == null:
		return ""

	var attribute_text:String = ""

	for attribute:AlchemicalData in item.alchemical_attribute:

		if attribute == null:
			continue

		if attribute_text != "":
			attribute_text += "\n"

		if attribute.level > 0:
			attribute_text += str(attribute.name) + str(attribute.level)
		else:
			attribute_text += str(attribute.name)

	if attribute_text == "":
		return str(item.name) + "\n\n无属性"

	return str(item.name) + "\n\n" + attribute_text
