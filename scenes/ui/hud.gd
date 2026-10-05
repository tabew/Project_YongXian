extends Control

## 游戏内 HUD：左上角基本信息，右上角性能面板（F3 开关），底部操作提示，顶部临时消息。

const REFRESH_INTERVAL: float = 0.2

@onready var info_label: Label = $InfoLabel
@onready var stats_label: Label = $StatsLabel
@onready var hint_label: Label = $HintLabel
@onready var toast_label: Label = $ToastLabel

var _world: ChunkManager = null
var _player: Node2D = null
var _refresh_timer: float = 0.0
var _toast_tween: Tween = null


func _ready() -> void:
	hint_label.text = "WASD / 方向键 移动　·　R 换个世界　·　F3 性能面板"
	toast_label.modulate.a = 0.0
	EventBus.notification.connect(_on_notification)
	EventBus.world_ready.connect(_on_world_ready)


## 由 GameWorld 注入区块管理器与主角。
func bind_world(manager: ChunkManager, player: Node2D) -> void:
	_world = manager
	_player = player
	_refresh_timer = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		stats_label.visible = not stats_label.visible


func _process(delta: float) -> void:
	if _world == null or _player == null:
		return

	# 文本刷新很便宜但没必要每帧做，0.2 秒一次足够
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = REFRESH_INTERVAL
	_refresh()


func _refresh() -> void:
	var position: Vector2 = _player.global_position
	var tile: Vector2i = WorldGenerator.world_to_tile(position)
	var chunk: Vector2i = WorldGenerator.tile_to_chunk(tile)

	var lines := PackedStringArray()
	lines.append("种子 %d" % GameState.world_seed)
	lines.append("坐标 %d, %d　区块 %d, %d" % [tile.x, tile.y, chunk.x, chunk.y])
	lines.append("地形 %s　群系 %s" % [
		Terrain.name_of(_world.get_terrain_at(position)),
		Biome.name_of(_world.get_biome_at(position)),
	])
	info_label.text = "\n".join(lines)

	var stats: Dictionary = _world.get_stats()
	var stats_lines := PackedStringArray()
	stats_lines.append("已加载 %d　缓存 %d" % [stats["loaded"], stats["cached"]])
	stats_lines.append("队列 %d　生成中 %d" % [stats["queued"], stats["in_flight"]])
	stats_lines.append("生成 %.2f ms/块" % stats["generate_avg_ms"])
	stats_lines.append("铺图 %.2f ms/块" % stats["apply_avg_ms"])
	stats_lines.append("共生成 %d　缓存命中 %d" % [stats["generated"], stats["cache_hits"]])
	stats_lines.append("FPS %d" % Engine.get_frames_per_second())
	stats_label.text = "\n".join(stats_lines)


func _on_world_ready(_seed_value: int) -> void:
	_refresh_timer = 0.0


func _on_notification(message: String) -> void:
	toast_label.text = message
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()

	toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.5)
