extends Button

##背包格子脚本

class_name SlotButton

signal take_item_signal(item_id:int, num:int)
signal put_item_signal(item_id:int, num:int)

##item_id/num是拿在手上的那份，from_pos是它原来所在的格子位置
signal swap_item_signal(item_id:int, num:int, from_pos:int)

##自己在快捷栏里的格子位置，不是快捷栏格子则为-1
var handy_slot:int = -1

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

##清掉本格显示
func clear_slot() -> void:
	if slot_item == null:
		return

	if is_instance_valid(slot_item):

		if slot_item.get_parent() == center_container:
			center_container.remove_child(slot_item)
		slot_item.queue_free()

	slot_item = null

##拿取物品,返回本格的物品
func take_item(num:int = 1) -> SlotItem:

	var held:SlotItem = null

	if slot_item != null:
		held = slot_item.duplicate()
		held.count = num
		take_item_signal.emit(slot_item.item_id,num)

	return held

#放入物品，只在背包中存在相同物品时才会调用
func put_item(num:int) -> void:
	#空格子没有物品id，发不出信号
	if slot_item == null:
		return

	put_item_by_id(slot_item.item_id,num)

#快捷栏空格收下拖来的东西
func put_item_by_id(item_id:int,num:int = 1) -> void:
	if item_id < 0 or num <= 0:
		return

	#放进本格的东西不带拖拽时的旋转
	if slot_item != null:
		slot_item.rotation = 0.0

	put_item_signal.emit(item_id,num)


##把物品放至光标
func _get_drag_data(_at_position: Vector2) -> Variant:
	if slot_item == null or slot_item.item == null:
		return null

	"""还没写shift+全部拿取的操作"""

	var held: SlotItem = take_item()

	if held == null:
		return null

	#记下拿走的东西id，拖拽取消时按这个数量还回原处
	dragged_item_id = held.item_id
	dragged_count = held.count

	set_drag_preview(held)

	held.slot_item_update()

	dragged_preview = held
	dragged_preview.rotation = 0.0

	dragged_data = {"item_id": held.item_id, "count": held.count, "rotation": dragged_preview.rotation, "from_pos": handy_slot}

	# 载荷：物品id + 数量 + 角度 + 来源格子
	return dragged_data

## 能否放到本格子上：同种物品可以叠，快捷栏两格之间还可以整堆交换
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if  not (data is Dictionary):
		return false

	#物品栏特殊判断
	if slot_item == null:
		return data.get("item_id") != null

	if data.get("item_id") == null:
		return false

	if slot_item.item_id == data.get("item_id"):
		return true

	return is_handy_button and _get_from_pos(data) >= 0

## 放下物品
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if !(data is Dictionary):
		return

	if slot_item == null:
		put_item_by_id(int(data.get("item_id",-1)),int(data.get("count",1)))
		return

	if is_handy_button and slot_item.item_id != data.get("item_id"):
		swap_item_signal.emit(int(data.get("item_id",-1)),int(data.get("count",1)),_get_from_pos(data))
		return

	put_item(int(data.get("count",1)))

##载荷里带的来源格子位置，不是快捷栏来的就是-1
func _get_from_pos(data: Variant) -> int:
	return int((data as Dictionary).get("from_pos",-1))

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

		if dragged_item_id != -1 and not get_viewport().gui_is_drag_successful():
			put_item_by_id(dragged_item_id,dragged_count)

		dragged_item_id = -1
		dragged_count = 0

		if dragged_preview != null:
			dragged_preview.rotation = 0.0
		dragged_preview = null
		dragged_data = {}

		if is_handy_button:
			if slot_item != null and slot_item.count <= 0:
				clear_slot()
			return

		#如果本格数量为空，则释放
		if slot_item != null and slot_item.count <= 0:
			queue_free()

func set_count(num:int) -> void:
	if slot_item == null:
		return
	slot_item.count = num
	slot_item.slot_item_update()
