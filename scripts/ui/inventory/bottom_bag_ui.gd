extends Control
##物品栏(快捷栏)ui，同步物品栏数据并显示和提供交互
##与背包的区别：背包同种物品只有一格(不能分开)，物品栏按格子管理，
##同一个物品可以同时放在不同格子里，物品归谁管只看格子本身

@onready var handy_slot_container:HBoxContainer = $PanelContainer/MarginContainer/HBoxContainer

@onready var item_buttons:Array[SlotButton]

@onready var slot_item:PackedScene = preload("res://scenes/ui/inventory/slot_item.tscn") #物品图标

@export var player:PlayerCharacter
var inventory:Inventory

func _ready() -> void:
	
	inventory = player.inventory
	inventory.inventory_update.connect(bag_update)
	inventory.handy_selection_changed.connect(_refresh_selection)
	
	init_button()
	bag_update()

func init_button() -> void:
	for child in handy_slot_container.get_children():
		item_buttons.append(child)

	if item_buttons.size() != Inventory.HANDY_SLOT_COUNT: 
		push_warning("物品栏格子数 %d 与 Inventory.HANDY_SLOT_COUNT %d 不一致" % [item_buttons.size(),Inventory.HANDY_SLOT_COUNT])

	for pos in item_buttons.size():
		var button:SlotButton = item_buttons[pos]
		button.is_handy_button = true
		button.handy_slot = pos #快捷栏交换：告诉目标格子本格是从哪一格拖出来的
		button.take_item_signal.connect(_on_slot_take.bind(pos))
		button.put_item_signal.connect(_on_slot_put.bind(pos)) 
		button.swap_item_signal.connect(_on_slot_swap.bind(pos)) #快捷栏交换：有别的物品要放进本格

		button.quick_move_signal.connect(_on_slot_quick_move.bind(pos)) #shift+左键：整堆挪回背包

		button.select_item_signal.connect(_on_slot_select.bind(pos)) #左键切换选中
		button.use_item_signal.connect(_on_slot_use_requested) #右键格子：选中并使用

		button.enchant_item_signal.connect(_on_slot_enchant.bind(pos)) #药水拖到本格武器上：附魔



##物品栏更新函数，同步物品栏数据
func bag_update() ->void:

	for pos in item_buttons.size():
		_slot_update(pos)

	_refresh_selection()

##把某一格的显示和物品栏数据对齐
func _slot_update(pos:int) ->void:
	var button:SlotButton = item_buttons[pos]

	var item_id:int = inventory.get_handy_slot_id(pos)
	var count:int = inventory.get_handy_slot_count(pos)

	if item_id < 0 or count <= 0:
		button.clear_slot()
		return

	#同一种物品只改数量
	if button.slot_item != null and is_instance_valid(button.slot_item) and button.slot_item.item_id == item_id:
		button.set_count(count)
		return

	#换了物品整格重建显示
	button.clear_slot()

	var slot_item_:SlotItem = slot_item.instantiate()
	slot_item_.set_item_id(item_id)
	slot_item_.count = count

	button.slot_insert(slot_item_)

##本格的东西被拿走
func _on_slot_take(_item_id:int,num:int,pos:int) ->void:
	inventory.remove_handy_slot(pos,num)

##有东西放进本格
func _on_slot_put(item_id:int,num:int,pos:int) ->void:
	if inventory.add_handy_slot(pos,item_id,num):
		return

	inventory.add_item(item_id,num)

##from_pos是拖出来的那一格，to_pos是本格(由信号绑定，只看格子本身)
func _on_slot_swap(item_id:int,num:int,from_pos:int,to_pos:int) ->void:
	inventory.swap_handy_slot(from_pos,to_pos,item_id,num)

#//////////////////////选取部分
##把每一格的描边和背包里记的选中格对齐
func _refresh_selection() ->void:

	var selected:int = inventory.get_selected_handy()

	for pos in item_buttons.size():
		item_buttons[pos].set_selected(pos == selected)

##左键切换选中
func _on_slot_select(pos:int, _bound_pos:int) ->void:
	inventory.select_handy_slot(pos)

##右键格子：选中后交给玩家走统一的使用逻辑。药水默认喝下，其他物品走右键效果。
func _on_slot_use_requested(_item_id:int, pos:int) ->void:
	if player == null or !is_instance_valid(player):
		return
	player.use_handy_slot(pos, false)

##选中只在物品栏露出来、又没在拖东西的时候生效
func _can_operate() ->bool:

	if player == null or inventory == null:
		return false

	if !visible:
		return false

	return true

##从 from 按 step 走到下一格，绕圈；没有选中时从环外起步（向后落在第1格）
func _next_slot(from:int, step:int) ->int:

	if from < 0:
		from = -1 if step > 0 else 0

	return posmod(from + step, Inventory.HANDY_SLOT_COUNT)
#///////////////////////////////////

##快捷移动
func _on_slot_quick_move(_item_id:int,_num:int,pos:int) ->void:
	inventory.quick_move_to_bag(pos)

##药水拖到本格的武器上：附魔。附魔成功后这一格的 id 会变成武器实例 id，
##本格同款还有多份的话退回背包；背包数据变了会发 inventory_update，
##_slot_update 会照着新 id 重建本格显示。
func _on_slot_enchant(_weapon_item_id:int,potion_item_id:int,pos:int) ->void:
	inventory.enchant_handy_weapon(pos,potion_item_id)


func _input(event: InputEvent) -> void:

	if event is InputEventKey:
		if Input.is_action_just_pressed("open_inventory")&&visible == false:
			visible = true

	#物品栏选中
	if !_can_operate():
		return

	var key_event:InputEventKey = event as InputEventKey

	if key_event != null and key_event.pressed and !key_event.echo:
		var digit:int = key_event.physical_keycode - KEY_0

		if digit >= 1 and digit <= Inventory.HANDY_SLOT_COUNT:
			inventory.select_handy_slot(digit - 1)
			get_viewport().set_input_as_handled()

		return

	var mouse_event:InputEventMouseButton = event as InputEventMouseButton

	if mouse_event != null and mouse_event.pressed:
		# 全屏地图展开时滚轮用来缩放地图，物品栏让出滚轮。
		if _fullscreen_map_open():
			return

		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			inventory.select_handy_slot(_next_slot(inventory.get_selected_handy(),-1))
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			inventory.select_handy_slot(_next_slot(inventory.get_selected_handy(),1))
			get_viewport().set_input_as_handled()


##全屏地图（M）展开时，滚轮与中键归地图，物品栏不再抢输入。
func _fullscreen_map_open() ->bool:

	var minimap:Node = get_parent().get_node_or_null("HUD/Minimap")

	return minimap != null and minimap.has_method("is_expanded") and minimap.call("is_expanded")

