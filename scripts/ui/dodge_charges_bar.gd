@tool
class_name DodgeChargesBar
extends Node2D

## 闪避次数：角色脚下的一条长条。
## 整条被次数均分，攒满一格就填实；正在恢复的那一格从左侧按进度填。
## 纯代码绘制，不需要贴图；带 @tool，所以在编辑器里也能看到并拖动调位置。
## 读角色属性一律走 get()：编辑器里脚本/属性可能还没就绪，不能直接点属性。

##相对角色的位置（脚下）。角色帧是 32×32，所以 y 要在 16 之外才不会被身体挡住
@export var offset: Vector2 = Vector2(0, 21):
	set(value):
		offset = value
		position = value
##长条尺寸(像素)：宽 × 高
@export var bar_size: Vector2 = Vector2(22, 3):
	set(value):
		bar_size = Vector2(maxf(value.x, 4.0), maxf(value.y, 1.0))
		queue_redraw()
##可用次数颜色
@export var full_color: Color = Color(0.82, 0.96, 1.0, 1.0):
	set(value):
		full_color = value
		queue_redraw()
##已用掉（空）的颜色
@export var empty_color: Color = Color(0.10, 0.14, 0.20, 0.85):
	set(value):
		empty_color = value
		queue_redraw()
##正在恢复那一段的颜色
@export var charging_color: Color = Color(0.45, 0.85, 1.0, 1.0):
	set(value):
		charging_color = value
		queue_redraw()
##外框颜色：保证在任何地面上都看得清
@export var outline_color: Color = Color(0.04, 0.06, 0.09, 0.9):
	set(value):
		outline_color = value
		queue_redraw()
##格与格之间要不要画分隔线
@export var show_dividers: bool = true:
	set(value):
		show_dividers = value
		queue_redraw()
##角色死亡时隐藏（编辑器里不隐藏，方便调位置）
@export var hide_when_dead: bool = true
##编辑器预览时按几次算（运行时用真实次数）
@export var editor_preview_charges: int = 2:
	set(value):
		editor_preview_charges = value
		queue_redraw()

var _player: Node = null


func _ready() -> void:
	_player = get_parent()
	position = offset
	#画在角色之上，避免被地形或身体盖住
	z_index = 1
	queue_redraw()


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if hide_when_dead and not Engine.is_editor_hint():
		var hp: Variant = _player.get("health")

		visible = not (hp is float or hp is int) or float(hp) > 0.0
	queue_redraw()


func _draw() -> void:
	#编辑器里没有运行时状态：直接画满条，方便调位置
	if Engine.is_editor_hint() or _player == null or not is_instance_valid(_player):
		_draw_bar(maxi(editor_preview_charges, 1), maxi(editor_preview_charges, 1), 1.0)
		return

	var total_value: Variant = _player.get("dodge_max_charges")
	var charges_value: Variant = _player.get("dodge_charges")

	#玩家的闪避属性还没就绪（脚本没刷新等）：也画预览，不报错
	if not (total_value is int) or not (charges_value is int):
		_draw_bar(maxi(editor_preview_charges, 1), maxi(editor_preview_charges, 1), 1.0)
		return

	var total: int = maxi(int(total_value), 1)
	var charges: int = clampi(int(charges_value), 0, total)
	var ratio: float = 1.0
	var ratio_value: Variant = _player.call("dodge_recharge_ratio")

	if ratio_value is float or ratio_value is int:
		ratio = clampf(float(ratio_value), 0.0, 1.0)
	_draw_bar(total, charges, ratio)


##画一条 total 等分的长条：前 charges 格填满，第 charges 格按 ratio 从左侧填
func _draw_bar(total: int, charges: int, ratio: float) -> void:
	var width: float = bar_size.x
	var height: float = bar_size.y
	var left: float = -width * 0.5
	var top: float = -height * 0.5
	var slot: float = width / float(maxi(total, 1))

	#底：整条暗色
	draw_rect(Rect2(left, top, width, height), empty_color, true)

	#已经攒满的格
	if charges > 0:
		draw_rect(Rect2(left, top, slot * float(charges), height), full_color, true)

	#正在恢复的那一格：从它自己的起点按进度往右填
	if charges < total and ratio > 0.0:
		draw_rect(Rect2(left + slot * float(charges), top, slot * clampf(ratio, 0.0, 1.0), height),
				charging_color, true)

	#格与格之间的分隔
	if show_dividers and total > 1:
		for i in range(1, total):
			var x: float = left + slot * float(i)

			draw_line(Vector2(x, top), Vector2(x, top + height), outline_color, 1.0)

	#外框
	draw_rect(Rect2(left, top, width, height), outline_color, false, 1.0)
