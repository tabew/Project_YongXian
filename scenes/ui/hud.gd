extends Control

## 游戏内 HUD：左上角显示地图信息，底部显示操作提示，顶部弹临时消息。

@onready var info_label: Label = $InfoLabel
@onready var hint_label: Label = $HintLabel
@onready var toast_label: Label = $ToastLabel

var _toast_tween: Tween = null


func _ready() -> void:
	hint_label.text = "WASD / 方向键 移动　·　R 重新生成地图"
	toast_label.modulate.a = 0.0
	EventBus.map_ready.connect(_on_map_ready)
	EventBus.notification.connect(_on_notification)


func _on_map_ready(map: MapData) -> void:
	var counts: PackedInt32Array = map.count_terrain()
	var walkable: int = (
		counts[MapData.Terrain.GRASS]
		+ counts[MapData.Terrain.FOREST]
		+ counts[MapData.Terrain.BEACH]
	)
	var total: int = maxi(map.width * map.height, 1)

	var lines := PackedStringArray()
	lines.append("种子：%d" % map.map_seed)
	lines.append("地图：%d × %d" % [map.width, map.height])
	lines.append("出生点：(%d, %d)" % [map.spawn_tile.x, map.spawn_tile.y])
	lines.append("可通行：%d%%" % int(roundf(float(walkable) / float(total) * 100.0)))
	info_label.text = "\n".join(lines)


func _on_notification(message: String) -> void:
	toast_label.text = message
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()

	toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.5)
