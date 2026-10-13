class_name GroundPickup
extends Node2D

## 世界地面材料；与炼金界面内的 IngredientModel 物理模型分离。
## 由 GameWorld 选择最近物品后显式调用 collect，不监听输入或自动拾取。
signal collected(item_id: int, amount: int)

var data: IngredientData = null
var amount: int = 1
var _sprite: Sprite2D = null
var _collected: bool = false
var _highlighted: bool = false


func _ready() -> void:
	add_to_group("ground_pickups")
	_update_visual()


func bind(ingredient: IngredientData, quantity: int = 1) -> void:
	data = ingredient
	amount = maxi(quantity, 0)
	_collected = false
	_update_visual()


func collect(player: PlayerCharacter) -> bool:
	if _collected or is_queued_for_deletion() or data == null or amount <= 0:
		return false
	if not is_instance_valid(player) or player.inventory == null:
		return false
	# 先标记，避免 inventory_update 的同步监听者重复收取本节点。
	_collected = true
	player.inventory.add_item(data.id, amount)
	collected.emit(data.id, amount)
	visible = false
	queue_free()
	return true


## 可由世界层标记当前可拾取目标；无需每个物品独立处理输入或轮询。
func set_highlighted(value: bool) -> void:
	if _highlighted == value:
		return
	_highlighted = value
	queue_redraw()


func _update_visual() -> void:
	if not is_instance_valid(_sprite):
		_sprite = get_node_or_null("Sprite2D") as Sprite2D
		if _sprite == null:
			_sprite = Sprite2D.new()
			_sprite.name = "Sprite2D"
			add_child(_sprite)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position = Vector2(0, -2)
	_sprite.texture = data.texture if data != null else null
	visible = data != null and amount > 0 and not _collected
	queue_redraw()


func _draw() -> void:
	if data == null or _collected:
		return
	# 阴影与高光保持静态像素边缘，避免大量物品各自运行动画。
	draw_rect(Rect2(-6, 3, 12, 2), Color(0.08, 0.09, 0.06, 0.30))
	draw_rect(Rect2(-4, 2, 8, 4), Color(0.08, 0.09, 0.06, 0.18))
	draw_rect(Rect2(5, -7, 2, 1), Color(1.0, 0.91, 0.66, 0.8))
	if _highlighted:
		draw_rect(Rect2(-9, -11, 18, 20), Color("f5dfa0"), false, 1.0)
