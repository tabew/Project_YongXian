extends Node2D

## 游戏世界：生成随机地图、铺进 TileMapLayer、把主角放到出生点。

## TileSet 里地形图集所在的 source id。
const TILE_SOURCE_ID: int = 0
## 图集是竖排的一条（6 格一列），所以图集坐标的列固定为 0，行才是地形编号。
const TILE_ATLAS_COLUMN: int = 0

@onready var tile_map: TileMapLayer = $TileMapLayer
@onready var player: PlayerCharacter = $Player

var map_data: MapData = null


func _ready() -> void:
	# 直接从编辑器单独运行本场景时，也要能开局
	if GameState.map_seed == 0:
		GameState.start_new_game()
	build_map(GameState.map_seed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate_map"):
		regenerate_map()


## 用指定种子生成一张地图并铺好，主角回到新的出生点。
func build_map(seed_value: int) -> void:
	map_data = MapGenerator.generate(GameState.map_width, GameState.map_height, seed_value)
	GameState.map_seed = map_data.map_seed

	_paint_tiles()
	player.spawn_on_map(map_data)
	_apply_camera_limits()

	EventBus.map_ready.emit(map_data)


## 换一个种子重新生成，用于“再来一张”的验证。
func regenerate_map() -> void:
	var new_seed: int = GameState.reroll_seed()
	build_map(new_seed)
	EventBus.notification.emit("已重新生成地图（种子 %d）" % new_seed)


func _paint_tiles() -> void:
	tile_map.clear()
	for y: int in map_data.height:
		for x: int in map_data.width:
			tile_map.set_cell(
				Vector2i(x, y),
				TILE_SOURCE_ID,
				Vector2i(TILE_ATLAS_COLUMN, map_data.get_tile(x, y))
			)


## 把摄像机限制在地图范围内，避免镜头拍到地图外面。
func _apply_camera_limits() -> void:
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map_data.width * MapData.TILE_SIZE
	camera.limit_bottom = map_data.height * MapData.TILE_SIZE
