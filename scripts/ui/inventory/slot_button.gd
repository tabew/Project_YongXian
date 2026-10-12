extends Button

##背包格子脚本

class_name SlotButton

signal take_item_signal(item_id:int, num:int)
signal put_item_signal(item_id:int, num:int)

##记录被选中的物品id（-1表示没有）
var dragged_item_id:int = -1
var dragged_count:int = 0

const DRAG_ROTATE_DEGREES:float = 6.0 #每次按键旋转的角度

var dragged_preview:Control = null #当前光标的拖拽预览
var dragged_data:Dictionary = {} #拖拽载荷

##是否为物品栏格子
@export var is_handy_button:bool = false

@onready var center_container:CenterContainer = $WaitforImage/CenterContainer
@onready var background:ColorRect = $WaitforImage

var slot_item:SlotItem = null;

func  _ready() -> void:
	button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_RIGHT


##物品插入函数
func  slot_insert(SI:SlotItem)->void:
	slot_item = SI
	center_container.add_child(slot_item)
	slot_item.slot_item_update()

##拿取物品,返回本格的物品
func take_item(num:int = 1) -> SlotItem:
	take_item_signal.emit(slot_item.item_id,num)
	
	var held:SlotItem = slot_item.duplicate()
	held.count = num

	return held

#放入物品，只在背包中存在相同物品时才会调用
func put_item(num:int) -> void:
	#空格子没有物品，发不出id
	if slot_item == null:
		return

	if slot_item != null:
		slot_item.rotation = 0.0

	put_item_signal.emit(slot_item.item_id,num)


##把物品放至光标
func _get_drag_data(_at_position: Vector2) -> Variant:
	if slot_item == null or slot_item.item == null:
		return null

	"""还没写shift+全部拿取的操作"""

	var held: SlotItem = take_item()

	if held == null:
		return null

	#记下拿走的东西id，拖拽取消时按这个数量还回背包
	dragged_item_id = held.item_id
	dragged_count = held.count

	set_drag_preview(held)

	held.slot_item_update()

	dragged_preview = held
	dragged_preview.rotation = 0.0

	dragged_data = {"item_id": held.item_id, "count": held.count, "rotation": dragged_preview.rotation}

	# 载荷：物品id + 数量 + 角度
	return dragged_data

## 能否放到本格子上：只接受同一种物品，按id比较
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if  not (data is Dictionary):
		return false

	#物品栏特殊判断
	if slot_item == null:
		return data.get("item_id") != null
	
	return data.get("item_id") != null and slot_item.item_id == data.get("item_id")

## 放下物品
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if slot_item == null:
		var temp = preload("res://scenes/ui/inventory/slot_item.tscn")
		slot_item = temp.instantiate()
		slot_item.item = ItemListGlobal.get_template(data.get("item_id"))

	put_item(data.get("count"))

##旋转输入
func _input(event: InputEvent) -> void:

	if dragged_preview == null:
		return

	if !(event is InputEventKey):
		return

	if !event.pressed:
		return

	# 2D 里 Y 轴朝下，正角度在屏幕上是顺时针，所以逆时针要用负角度
	match event.physical_keycode:
		KEY_Q:
			_rotate_dragged(-DRAG_ROTATE_DEGREES)
		KEY_E:
			_rotate_dragged(DRAG_ROTATE_DEGREES)

##旋转角度
func _rotate_dragged(degrees:float) -> void:
	dragged_preview.rotation_degrees += degrees

	dragged_data["rotation"] = dragged_preview.rotation

## 拖拽结束
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# item_list 重构：还回背包时用记下的物品id
		if dragged_item_id != -1 and not get_viewport().gui_is_drag_successful():
			put_item(dragged_count)

		dragged_item_id = -1
		dragged_count = 0

		if dragged_preview != null:
			dragged_preview.rotation = 0.0
		dragged_preview = null
		dragged_data = {}

		if is_handy_button:
			if slot_item != null:
				if slot_item.count<=0:
					slot_item.queue_free()
			return

		#如果本格数量为空，则释放
		if slot_item != null and slot_item.count <= 0:
			queue_free()

func set_count(num:int) -> void:
	if slot_item == null:
		return
	slot_item.count = num
	slot_item.slot_item_update()
