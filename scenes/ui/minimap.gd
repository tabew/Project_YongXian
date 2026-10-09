class_name Minimap
extends Control

## 右上角小地图与全屏探索地图。
##
## 默认保持原来的 5x5 区块小地图；按 M 后铺满窗口，显示更大的已观察区域。
## 两种模式都直接读取区块缓存，不重新计算噪声；全屏模式保存逐格快照。

const TERRAIN_ATLAS: String = "res://assets/terrain_tiles.png"
const ROAD_ATLAS: String = "res://assets/road_tiles.png"

## 小地图保持 2 格 1 像素；全屏地图使用 1 格 1 像素显示更多细节。
const COMPACT_TILES_PER_PIXEL: int = 2
const FULL_MAP_TILES_PER_PIXEL: int = 1
## 全屏地图至少显示以玩家为中心的 15x7 个区块。
const FULL_MAP_HALF_CHUNKS: Vector2i = Vector2i(7, 3)
const REFRESH_INTERVAL: float = 0.25
## 图集里取色的位置（每块贴图的正中心）。
const ATLAS_PROBE: int = 8
const FULL_MAP_MARGIN: float = 48.0

const UNKNOWN_COLOR: Color = Color(0.08, 0.09, 0.12)
const FULL_MAP_BACKGROUND: Color = Color(0.025, 0.03, 0.045, 0.96)
## 路在地图上偏向暖黄，这样不管在什么群系上都能一眼看出路线。
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

## 当前贴图左上角对应的世界格子坐标。
var _map_origin: Vector2i = Vector2i.ZERO
var _map_image_size: Vector2i = Vector2i.ONE
var _focus_chunk: Vector2i = Vector2i(2147483647, 2147483647)
var _refresh_timer: float = 0.0
var _compact_pixels_per_chunk: int = 1
var _full_pixels_per_chunk: int = 1
var _active_pixels_per_chunk: int = 1
var _active_tiles_per_pixel: int = 1
var _seen_version: int = -1
var _expanded: bool = false

## 已探索区块的像素快照，确保区块离开缓存后仍能在全屏地图中显示。
var _explored_chunks: Dictionary = {}
var _exploration_version: int = 0
var _seen_exploration_version: int = -1


func _ready() -> void:
	_compact_pixels_per_chunk = maxi(
		WorldGenerator.CHUNK_SIZE / COMPACT_TILES_PER_PIXEL, 1
	)
	_full_pixels_per_chunk = maxi(
		WorldGenerator.CHUNK_SIZE / FULL_MAP_TILES_PER_PIXEL, 1
	)
	_build_palette()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 由 HUD 调用：注入区块管理器与主角。
func bind(manager: ChunkManager, player: Node2D) -> void:
	_manager = manager
	_player = player
	_focus_chunk = WorldGenerator.tile_to_chunk(
		WorldGenerator.world_to_tile(player.global_position)
	)
	_explored_chunks.clear()
	_exploration_version = 0
	_seen_exploration_version = -1
	_seen_version = -1
	_refresh_timer = 0.0
	_capture_loaded_chunks()
	_rebuild()


func set_expanded(value: bool) -> void:
	if _expanded == value:
		return
	_expanded = value

	if _expanded:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		z_index = 100
	else:
		anchor_left = 1.0
		anchor_top = 0.0
		anchor_right = 1.0
		anchor_bottom = 0.0
		offset_left = -178.0
		offset_top = 14.0
		offset_right = -14.0
		offset_bottom = 178.0
		z_index = 0

	_seen_version = -1
	_seen_exploration_version = -1
	_rebuild()
	queue_redraw()


func is_expanded() -> bool:
	return _expanded


func _process(delta: float) -> void:
	if _manager == null or _player == null:
		return

	var focus: Vector2i = WorldGenerator.tile_to_chunk(
		WorldGenerator.world_to_tile(_player.global_position)
	)
	if focus != _focus_chunk:
		_focus_chunk = focus
		_refresh_timer = 0.0
		_seen_version = -1
		_seen_exploration_version = -1

	_capture_loaded_chunks()
	_refresh_timer -= delta
	var compact_changed: bool = not _expanded and _manager.version != _seen_version
	var full_map_changed: bool = _expanded and _exploration_version != _seen_exploration_version
	if _refresh_timer <= 0.0 and (compact_changed or full_map_changed):
		_refresh_timer = REFRESH_INTERVAL
		_rebuild()

	# 主角光点每帧重画，地图底图只在数据变化时重建。
	queue_redraw()


## 所有实际加载并观察过的区块都保存逐格快照，离开缓存后仍可在全屏地图显示。
func _capture_loaded_chunks() -> void:
	var changed: bool = false
	for coords: Vector2i in _manager.loaded_chunks():
		if _explored_chunks.has(coords):
			continue
		var data: ChunkData = _manager.get_cached_chunk(coords)
		if data == null:
			continue
		_explored_chunks[coords] = _build_chunk_pixels(data, FULL_MAP_TILES_PER_PIXEL)
		changed = true
	if changed:
		_exploration_version += 1


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


# ------------------------------------------------------------ 地图数据

## 原来的右上角小地图：显示玩家附近已加载的 5x5 区块，不加探索迷雾。
func _build_compact_pixels() -> PackedByteArray:
	var bytes := PackedByteArray()
	var span_chunks: int = _manager.load_radius * 2 + 1
	var pixels: int = span_chunks * _compact_pixels_per_chunk
	var radius: int = _manager.load_radius
	var origin_chunk: Vector2i = _focus_chunk - Vector2i(radius, radius)
	_map_origin = origin_chunk * WorldGenerator.CHUNK_SIZE
	_map_image_size = Vector2i(pixels, pixels)
	_active_pixels_per_chunk = _compact_pixels_per_chunk
	_active_tiles_per_pixel = COMPACT_TILES_PER_PIXEL

	bytes.resize(pixels * pixels * 3)
	_fill_unknown(bytes)

	for chunk_y: int in span_chunks:
		for chunk_x: int in span_chunks:
			var data: ChunkData = _manager.get_cached_chunk(
				origin_chunk + Vector2i(chunk_x, chunk_y)
			)
			if data == null:
				continue
			var chunk_pixels: PackedByteArray = _build_chunk_pixels(
				data, COMPACT_TILES_PER_PIXEL
			)
			_copy_chunk_pixels(
				bytes, pixels, chunk_pixels, _compact_pixels_per_chunk, chunk_x, chunk_y
			)

	return bytes


## 全屏地图至少覆盖 15x7 区块，并在此基础上包含全部已探索区块。
func _build_explored_pixels() -> PackedByteArray:
	var bytes := PackedByteArray()
	var min_chunk: Vector2i = _focus_chunk - FULL_MAP_HALF_CHUNKS
	var max_chunk: Vector2i = _focus_chunk + FULL_MAP_HALF_CHUNKS
	for coords: Vector2i in _explored_chunks.keys():
		min_chunk.x = mini(min_chunk.x, coords.x)
		min_chunk.y = mini(min_chunk.y, coords.y)
		max_chunk.x = maxi(max_chunk.x, coords.x)
		max_chunk.y = maxi(max_chunk.y, coords.y)

	var chunk_span: Vector2i = max_chunk - min_chunk + Vector2i.ONE
	var width: int = chunk_span.x * _full_pixels_per_chunk
	var height: int = chunk_span.y * _full_pixels_per_chunk
	_map_origin = min_chunk * WorldGenerator.CHUNK_SIZE
	_map_image_size = Vector2i(width, height)
	_active_pixels_per_chunk = _full_pixels_per_chunk
	_active_tiles_per_pixel = FULL_MAP_TILES_PER_PIXEL
	bytes.resize(width * height * 3)
	_fill_unknown(bytes)

	for coords: Vector2i in _explored_chunks.keys():
		if coords.x < min_chunk.x or coords.y < min_chunk.y:
			continue
		if coords.x > max_chunk.x or coords.y > max_chunk.y:
			continue
		var local_chunk: Vector2i = coords - min_chunk
		var chunk_pixels: PackedByteArray = _explored_chunks[coords]
		_copy_chunk_pixels(
			bytes, width, chunk_pixels, _full_pixels_per_chunk,
			local_chunk.x, local_chunk.y
		)

	return bytes


func _build_chunk_pixels(data: ChunkData, tiles_per_pixel: int) -> PackedByteArray:
	var pixels_per_chunk: int = WorldGenerator.CHUNK_SIZE / tiles_per_pixel
	var bytes := PackedByteArray()
	bytes.resize(pixels_per_chunk * pixels_per_chunk * 3)
	for pixel_y: int in pixels_per_chunk:
		var local_row: int = pixel_y * tiles_per_pixel * WorldGenerator.CHUNK_SIZE
		for pixel_x: int in pixels_per_chunk:
			var source_index: int = local_row + pixel_x * tiles_per_pixel
			var road: int = data.route[source_index]
			var palette: PackedByteArray = _terrain_rgb
			var entry: int = data.terrain[source_index] * 3
			if road != Route.Kind.NONE:
				palette = _route_rgb
				entry = Route.atlas_row(road) * 3

			var target: int = (pixel_y * pixels_per_chunk + pixel_x) * 3
			bytes[target] = palette[entry]
			bytes[target + 1] = palette[entry + 1]
			bytes[target + 2] = palette[entry + 2]
	return bytes


func _copy_chunk_pixels(
	target: PackedByteArray,
	target_width: int,
	chunk_pixels: PackedByteArray,
	pixels_per_chunk: int,
	chunk_x: int,
	chunk_y: int
) -> void:
	for pixel_y: int in pixels_per_chunk:
		for pixel_x: int in pixels_per_chunk:
			var source: int = (pixel_y * pixels_per_chunk + pixel_x) * 3
			var target_x: int = chunk_x * pixels_per_chunk + pixel_x
			var target_y: int = chunk_y * pixels_per_chunk + pixel_y
			var destination: int = (target_y * target_width + target_x) * 3
			target[destination] = chunk_pixels[source]
			target[destination + 1] = chunk_pixels[source + 1]
			target[destination + 2] = chunk_pixels[source + 2]


func _fill_unknown(bytes: PackedByteArray) -> void:
	for offset: int in range(0, bytes.size(), 3):
		bytes[offset] = _unknown_rgb[0]
		bytes[offset + 1] = _unknown_rgb[1]
		bytes[offset + 2] = _unknown_rgb[2]


func _rebuild() -> void:
	if _manager == null:
		return
	var bytes: PackedByteArray = (
		_build_explored_pixels() if _expanded else _build_compact_pixels()
	)
	if bytes.is_empty():
		_texture = null
		_image = null
		queue_redraw()
		return

	_seen_version = _manager.version
	_seen_exploration_version = _exploration_version
	var width: int = _map_image_size.x
	var height: int = _map_image_size.y

	if _texture == null or _image == null or _image.get_size() != _map_image_size:
		_image = Image.create_from_data(width, height, false, Image.FORMAT_RGB8, bytes)
		_texture = ImageTexture.create_from_image(_image)
	else:
		_image.set_data(width, height, false, Image.FORMAT_RGB8, bytes)
		_texture.update(_image)
	queue_redraw()


# ------------------------------------------------------------ 绘制

func _draw() -> void:
	if _expanded:
		draw_rect(Rect2(Vector2.ZERO, size), FULL_MAP_BACKGROUND, true)
	if _texture == null or _image == null:
		return

	var map_rect: Rect2 = _calculate_map_rect()
	draw_texture_rect(_texture, map_rect, false)

	var scale_x: float = map_rect.size.x / float(_image.get_width())
	var scale_y: float = map_rect.size.y / float(_image.get_height())
	var chunk_width: float = float(_active_pixels_per_chunk) * scale_x
	var chunk_height: float = float(_active_pixels_per_chunk) * scale_y

	var offset_x: float = 0.0
	while offset_x <= map_rect.size.x:
		var x: float = map_rect.position.x + offset_x
		draw_line(Vector2(x, map_rect.position.y), Vector2(x, map_rect.end.y), GRID_COLOR, 1.0)
		offset_x += chunk_width
	var offset_y: float = 0.0
	while offset_y <= map_rect.size.y:
		var y: float = map_rect.position.y + offset_y
		draw_line(Vector2(map_rect.position.x, y), Vector2(map_rect.end.x, y), GRID_COLOR, 1.0)
		offset_y += chunk_height

	if _player != null:
		var tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
		var local_pixels: Vector2 = (
			Vector2(tile - _map_origin) / float(_active_tiles_per_pixel)
		)
		var player_position := Vector2(
			map_rect.position.x + local_pixels.x * scale_x,
			map_rect.position.y + local_pixels.y * scale_y
		)
		if map_rect.has_point(player_position):
			var marker_radius: float = 6.0 if _expanded else 3.5
			draw_circle(player_position, marker_radius, PLAYER_COLOR)
			draw_arc(player_position, marker_radius, 0.0, TAU, 20, PLAYER_OUTLINE, 1.5)

	draw_rect(map_rect, BORDER_COLOR, false, 1.0)


func _calculate_map_rect() -> Rect2:
	if not _expanded:
		var side: float = minf(size.x, size.y)
		return Rect2(Vector2.ZERO, Vector2(side, side))

	var available := Vector2(
		maxf(size.x - FULL_MAP_MARGIN * 2.0, 1.0),
		maxf(size.y - FULL_MAP_MARGIN * 2.0, 1.0)
	)
	var scale_factor: float = minf(
		available.x / float(_image.get_width()),
		available.y / float(_image.get_height())
	)
	var map_size := Vector2(
		float(_image.get_width()) * scale_factor,
		float(_image.get_height()) * scale_factor
	)
	return Rect2((size - map_size) * 0.5, map_size)
