extends Button

class_name BagUI
##背包ui，同步背包数据并显示和提供交互
##
##格子显示完全跟着背包数据走：背包里没有的物品，格子必须一起收掉。
##否则炼金台里那块一直开着的背包（不会在打开时重建）会留着已经用掉、交出去、
##或者被换掉的格子，看起来"背包里还有这瓶药水"，而正常打开背包（每次打开都重建）却没有。

@onready var bag_slot_container:GridContainer = $PanelContainer/MarginContainer/ScrollContainer/BagSlotContainer

@onready var item_for_button:Dictionary[int,SlotButton] = {}

@onready var slot_button:PackedScene = preload("res://scenes/ui/inventory/slot_button.tscn") #格子场景
@onready var slot_item:PackedScene = preload("res://scenes/ui/inventory/slot_item.tscn") #物品图标

@export var player:PlayerCharacter

var inventory:Inventory

func _ready() -> void:
	button_mask = MOUSE_BUTTON_MASK_LEFT

	player = get_tree().get_first_node_in_group("player")

	if player == null or player.inventory == null:
		push_warning("BagUI: 没拿到玩家背包，背包界面不会同步")
		return

	inventory = player.inventory
	inventory.inventory_update.connect(bag_update)

	bag_update()

##背包更新函数，把格子显示和背包数据对齐：
##缺的补上、数量刷新、背包里已经没有的物品连格子一起收掉
func bag_update() ->void:

	if inventory == null:
		return

	#先收掉不该再显示的格子（药水用掉、拖去投料框、附魔换掉都会走到这里）
	for item_id:int in item_for_button.keys():
		if !_should_show(item_id):
			_remove_slot(item_id)

	#再补上缺的格子、刷新已有格子的数量
	for item_id:int in inventory.has_items:
		if !_should_show(item_id):
			continue

		if item_for_button.has(item_id):
			item_for_button[item_id].set_count(inventory.get_count(item_id))
			continue

		_add_slot(item_id)

##这个id现在还该在背包里占一格吗
func _should_show(item_id:int) ->bool:

	if !inventory.has_items.has(item_id):
		return false

	if inventory.get_count(item_id) <= 0:
		return false

	return inventory.get_item_template(item_id) != null

##新建一格并登记
func _add_slot(item_id:int) ->void:

	var item:ItemData = inventory.get_item_template(item_id)

	if item == null:
		return

	var slot_item_:SlotItem = slot_item.instantiate()
	var slot_node:SlotButton = slot_button.instantiate()

	slot_item_.set_item_id(item_id) # item_list 重构：id定种类，实例来自注册表
	slot_item_.count = inventory.get_count(item_id)

	bag_slot_container.add_child(slot_node)
	item_for_button[item_id] = slot_node

	slot_node.take_item_signal.connect(take_item)
	slot_node.put_item_signal.connect(put_item)
	slot_node.quick_move_signal.connect(_on_slot_quick_move) #shift+左键：整堆挪进快捷栏
	slot_node.enchant_item_signal.connect(_on_slot_enchant) #药水拖到武器上：附魔
	slot_node.slot_insert(slot_item_)

##收掉某一格：登记和网格一起摘掉
##正在被拖拽的格子留给它自己在 DRAG_END 收尾——取消拖拽要靠来源格把物品还回背包，
##这里的格子要是先没了，那瓶药水就凭空消失了
func _remove_slot(item_id:int) ->void:

	var slot_node:SlotButton = item_for_button.get(item_id)
	item_for_button.erase(item_id)

	if slot_node == null or !is_instance_valid(slot_node):
		return

	if slot_node.is_dragging_item:
		slot_node.set_count(0)
		return

	bag_slot_container.remove_child(slot_node)
	slot_node.queue_free()

##拿取物品，item_id为物品id
func take_item(item_id:int,num:int) ->void:
	inventory.remove_item(item_id,num)

	if !item_for_button.has(item_id): #格子可能已经被释放
		return

	item_for_button[item_id].set_count(inventory.get_count(item_id))

	if !_should_show(item_id):
		_remove_slot(item_id)

##放入物品，item_id为物品id
func put_item(item_id:int,num:int) ->void:
	inventory.add_item(item_id,num) #背包数据变了会发 inventory_update，格子由 bag_update 对齐

#//////////////////////////快捷移动
##shift+左键：本格整堆挪进物品栏(快捷栏)
func _on_slot_quick_move(item_id:int,num:int) ->void:
	if inventory.quick_move_to_handy(item_id,num) <= 0:
		return

	_refresh_slot(item_id)

##药水拖到武器上：交给背包附魔。附魔只换走一份，原来的 id 还有剩余(同款武器堆叠)
##就保留旧格子，整份都被换走才把格子收掉。
func _on_slot_enchant(weapon_item_id:int,potion_item_id:int) ->void:
	if !inventory.enchant_bag_weapon(weapon_item_id,potion_item_id):
		return

	_refresh_slot(weapon_item_id)

##背包里某种物品的数量变了就同步显示，整堆拿完就把格子收掉
func _refresh_slot(item_id:int) ->void:
	if item_for_button.has(item_id) and _should_show(item_id):
		item_for_button[item_id].set_count(inventory.get_count(item_id))
		return

	_remove_slot(item_id)
#///////////////////////////////////

## 背包区域放回
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if !(data is Dictionary):
		return false
	return data.has("item_id")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	put_item(data.get("item_id"),data.get("count"))

func _input(event: InputEvent) -> void:
	#只认"按下"这一次事件：同一帧里按下+松开会各走一次 _input，
	#用 is_action_just_pressed 判断会开了又关，看起来就是背包打不开
	if event.is_action_pressed("open_inventory"):
		visible = !visible
		_input_update()

func _input_update():
	if !visible:
		return

	#拖拽中重建会把来源格拆掉（取消拖拽要靠它物归原处），等拖完再说
	if get_viewport().gui_is_dragging():
		return

	for child:Node in bag_slot_container.get_children():
		bag_slot_container.remove_child(child)
		child.queue_free()

	item_for_button.clear()
	bag_update()
