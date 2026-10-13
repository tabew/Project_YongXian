class_name MaterialModel
extends ItemModel

## 仅供背包拖入炼金界面的刚体模型；世界散落材料使用 GroundPickup。
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	if data != null:
		sprite.texture = data.texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
