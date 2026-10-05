class_name Minimap
extends Control

## 右上角小地图。
##
## 性能关键：底图**直接读已加载区块的数据**着色，一行噪声都不重算。
## 覆盖范围正好等于区块加载范围（默认 5x5 区块 = 160x160 格），
## 所以永远是"已加载多少就显示多少"，没加载的地方显示为暗色。
##
## 2 格 1 像素 -> 80x80 的底图，再整数放大到控件大小，配合最近邻采样保持锐利。

const TERRAIN_ATLAS: String = "res://assets/terrain_tiles.png"
const ROAD_ATLAS: String = "res://assets/road_tiles.png"

## 一个像素代表多少格地形。
const TILES_PER_PIXEL: int = 2
const REFRESH_INTERVAL: float = 0.25
## 图集里取色的位置（每块贴图的正中心）。
const ATLAS_PROBE: int = 8

const UNKNOWN_COLOR: Color = Color(0.08, 0.09, 0.12)
## 路在底图上偏向暖黄，这样不管在什么群系上都能一眼看出路线。
const ROAD_HIGHLIGHT: Color = Color(1.0, 0.85, 0.35)
const ROAD_HIGHLIGHT_STRENGTH: float = 0.55
const PLAYER_COLOR: Color = Color(1.0, 0.9, 0.25)
const PLAYER_OUTLINE: Color = Color(0.08, 0.08, 0.10)
const GRID_COLOR: Color = Color(1.0, 1.0, 1.0, 0.08)
const BORDER_COLOR: Color = Color(0.78, 0.84, 0.92, 0.85)

var _manager: ChunkManager = null
var _player: Node2D = null

## 调色板直接以 RGB 字节存好，逐像素填的时候不用再做浮点转换。
var _terrain_rgb: PackedByteArray = PackedByteArray()
var _route_rgb: PackedByteArray = PackedByteArray()
var _unknown_rgb: PackedByteArray = PackedByteArray()

var _texture: ImageTexture = null
var _image: Image = null

## 小地图左上角对应的世界格子坐标。
var _map_origin: Vector2i = Vector2i.ZERO
var _focus_chunk: Vector2i = Vector2i(2147483647, 2147483647)
var _refresh_timer: float = 0.0
var _pixels_per_chunk: int = 1
## 上次重建时区块数据的版本号，用来跳过无意义的重建。
var _seen_version: int = -1


func _ready() -> void:
	_pixels_per_chunk = maxi(WorldGenerator.CHUNK_SIZE / TILES_PER_PIXEL, 1)
	_build_palette()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 由 HUD 调用：注入区块管理器与主角。
func bind(manager: ChunkManager, player: Node2D) -> void:
	_manager = manager
	_player = player
	_focus_chunk = WorldGenerator.tile_to_chunk(
		WorldGenerator.world_to_tile(player.global_position)
	)
	_rebuild()


func _process(delta: float) -> void:
	if _manager == null or _player == null:
		return

	var focus: Vector2i = WorldGenerator.tile_to_chunk(
		WorldGenerator.world_to_tile(_player.global_position)
	)
	if focus != _focus_chunk:
		_focus_chunk = focus
		_refresh_timer = 0.0

	_refresh_timer -= delta
	if _refresh_timer <= 0.0 and _manager.version != _seen_version:
		_refresh_timer = REFRESH_INTERVAL
		_rebuild()

	# 主角光点要跟手，所以每帧重画；重画只是贴一张图加十来条线，很便宜
	queue_redraw()


# ------------------------------------------------------------ 调色板

## 颜色直接从图集上取，避免颜色表和图集两边各写一份而对不上。
func _build_palette() -> void:
	_terrain_rgb = _sample_atlas(TERRAIN_ATLAS, Terrain.COUNT)
	_route_rgb = _sample_atlas(ROAD_ATLAS, Route.COUNT, ROAD_HIGHLIGHT, ROAD_HIGHLIGHT_STRENGTH)
	_unknown_rgb = PackedByteArray()
	_unknown_rgb.append(int(UNKNOWN_COLOR.r * 255.0))
	_unknown_rgb.append(int(UNKNOWN_COLOR.g * 255.0))
	_unknown_rgb.append(int(UNKNOWN_COLOR.b * 255.0))


func _sample_atlas(
	path: String,
	count: int,
	highlight: Color = Color(0, 0, 0, 0),
	highlight_strength: float = 0.0
) -> PackedByteArray:
	var image: Image = (load(path) as Texture2D).get_image()
	var rgb := PackedByteArray()
	rgb.resize(count * 3)
	for index: int in count:
		var color: Color = image.get_pixel(ATLAS_PROBE, index * 16 + ATLAS_PROBE)
		if highlight_strength > 0.0:
			color = color.lerp(highlight, highlight_strength)
		rgb[index * 3] = int(color.r * 255.0)
		rgb[index * 3 + 1] = int(color.g * 255.0)
		rgb[index * 3 + 2] = int(color.b * 255.0)
	return rgb


# ------------------------------------------------------------ 底图

## 按当前已加载的区块生成底图像素（纯数据，不上传贴图，方便单独测试）。
func build_pixels() -> PackedByteArray:
	var bytes := PackedByteArray()
	if _manager == null:
		return bytes

	var span_chunks: int = _manager.load_radius * 2 + 1
	var pixels: int = span_chunks * _pixels_per_chunk
	var radius: int = _manager.load_radius
	var origin_chunk: Vector2i = _focus_chunk - Vector2i(radius, radius)
	_map_origin = origin_chunk * WorldGenerator.CHUNK_SIZE

	bytes.resize(pixels * pixels * 3)
	bytes.fill(0)

	# 按区块遍历，每块只查一次缓存；逐像素查字典会慢两个数量级
	for chunk_y: int in span_chunks:
		for chunk_x: int in span_chunks:
			var data: ChunkData = _manager.get_cached_chunk(
				origin_chunk + Vector2i(chunk_x, chunk_y)
			)
			for pixel_y: int in _pixels_per_chunk:
				var base: int = (chunk_y * _pixels_per_chunk + pixel_y) * pixels * 3
				var local_row: int = pixel_y * TILES_PER_PIXEL * WorldGenerator.CHUNK_SIZE
				for pixel_x: int in _pixels_per_chunk:
					var offset: int = base + (chunk_x * _pixels_per_chunk + pixel_x) * 3
					if data == null:
						bytes[offset] = _unknown_rgb[0]
						bytes[offset + 1] = _unknown_rgb[1]
						bytes[offset + 2] = _unknown_rgb[2]
						continue

					var index: int = local_row + pixel_x * TILES_PER_PIXEL
					var road: int = data.route[index]
					var palette: PackedByteArray = _terrain_rgb
					var entry: int = data.terrain[index] * 3
					if road != Route.Kind.NONE:
						palette = _route_rgb
						entry = Route.atlas_row(road) * 3

					bytes[offset] = palette[entry]
					bytes[offset + 1] = palette[entry + 1]
					bytes[offset + 2] = palette[entry + 2]

	return bytes


func _rebuild() -> void:
	var bytes: PackedByteArray = build_pixels()
	if bytes.is_empty():
		return

	_seen_version = _manager.version
	var pixels: int = int(sqrt(float(bytes.size() / 3)))
	if _texture == null or _image == null or _image.get_width() != pixels:
		_image = Image.create_from_data(pixels, pixels, false, Image.FORMAT_RGB8, bytes)
		_texture = ImageTexture.create_from_image(_image)
	else:
		_image.set_data(pixels, pixels, false, Image.FORMAT_RGB8, bytes)
		_texture.update(_image)


# ------------------------------------------------------------ 绘制

func _draw() -> void:
	var side: float = minf(size.x, size.y)
	if _texture == null or side <= 0.0:
		return

	var scale_factor: float = side / float(_image.get_width())
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, Vector2(side, side)), false)

	# 区块网格
	var chunk_pixels: float = float(_pixels_per_chunk) * scale_factor
	var offset: float = 0.0
	while offset <= side:
		draw_line(Vector2(offset, 0.0), Vector2(offset, side), GRID_COLOR, 1.0)
		draw_line(Vector2(0.0, offset), Vector2(side, offset), GRID_COLOR, 1.0)
		offset += chunk_pixels

	# 主角
	if _player != null:
		var tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
		var local: Vector2 = Vector2(tile - _map_origin) / float(TILES_PER_PIXEL) * scale_factor
		if local.x >= 0.0 and local.y >= 0.0 and local.x <= side and local.y <= side:
			draw_circle(local, 3.5, PLAYER_COLOR)
			draw_arc(local, 3.5, 0.0, TAU, 20, PLAYER_OUTLINE, 1.5)

	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, size.y)), BORDER_COLOR, false, 1.0)
