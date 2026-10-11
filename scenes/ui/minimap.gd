class_name Minimap
extends Control

## 右上角小地图与全屏探索地图。
##
## 小地图独立采样玩家周围 512x512 格；按 M 铺满窗口显示已观察区域。
## compact 的世界像素缓存与全屏逐格探索快照相互独立。

const TERRAIN_ATLAS: String = "res://assets/terrain_tiles.png"
const ROAD_ATLAS: String = "res://assets/road_tiles.png"

## 小地图为 512 格 / 128 像素；全屏保持逐格探索细节。
const TILES_PER_PIXEL: int = 4
const WINDOW_TILES: int = 512
const TEXTURE_SIZE: int = WINDOW_TILES / TILES_PER_PIXEL
const PIXEL_CACHE_LIMIT: int = TEXTURE_SIZE * TEXTURE_SIZE * 4
const COMPACT_TILES_PER_PIXEL: int = TILES_PER_PIXEL
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
const LABEL_COLOR: Color = Color(0.90, 0.93, 1.0)
const ACTIVE_LABEL_COLOR: Color = Color(1.0, 0.90, 0.35)
const CAMERA_COLOR: Color = Color(0.90, 0.94, 1.0, 0.65)
const LABEL_FONT_SIZE: int = 13

@export var show_camera_view: bool = true

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
var _compact_pixels_per_chunk: int = WorldGenerator.CHUNK_SIZE / COMPACT_TILES_PER_PIXEL
var _full_pixels_per_chunk: int = WorldGenerator.CHUNK_SIZE / FULL_MAP_TILES_PER_PIXEL
var _active_pixels_per_chunk: int = 1
var _active_tiles_per_pixel: int = 1
var _seen_version: int = -1
var _expanded: bool = false
var _map_size: int = 0
var _map_node: int = -1
var _source_generator: WorldGenerator = null
var _sampler: WorldGenerator = null
var _seed: int = 0
var _specs: Array[MapSpec] = []
## 世界 tile -> RGB 整数；仅 compact 使用，不能作为探索记录。
var _pixel_cache: Dictionary = {}
## 同一个世界区块可能分属两个箱庭，分别记录已捕获的矩形区域。
var _captured_regions: Dictionary = {}

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
	_clear_world_cache()
	if _terrain_rgb.is_empty():
		_build_palette()
	_sync_generator()
	_update_focus()
	_capture_loaded_chunks()
	_rebuild()


func _clear_world_cache() -> void:
	_texture = null
	_image = null
	_map_origin = Vector2i.ZERO
	_map_image_size = Vector2i.ONE
	_map_size = 0
	_map_node = -1
	_focus_chunk = Vector2i(2147483647, 2147483647)
	_refresh_timer = 0.0
	_seen_version = -1
	_seed = 0
	_source_generator = null
	_sampler = null
	_specs.clear()
	_pixel_cache.clear()
	_captured_regions.clear()
	_explored_chunks.clear()
	_exploration_version = 0
	_seen_exploration_version = -1


func _sync_generator() -> bool:
	if not is_instance_valid(_manager):
		return false
	var generator: WorldGenerator = _manager.get_generator()
	if generator == null:
		# 旧测试只提供区块缓存，没有 generator/spec，仍可显示并保存完整快照。
		if _source_generator != null:
			_clear_world_cache()
		return true
	if generator != _source_generator or generator.world_seed != _seed:
		_clear_world_cache()
		_source_generator = generator
		_seed = generator.world_seed
		# 不共享管理器的可变分类缓冲，也不把采样结果记为已探索。
		_sampler = WorldGenerator.new(_seed)
		_specs = generator.map_specs().duplicate()
	return true


func _update_focus() -> void:
	if not is_instance_valid(_player):
		return
	var focus: Vector2i = WorldGenerator.tile_to_chunk(
		WorldGenerator.world_to_tile(_player.global_position)
	)
	if focus != _focus_chunk:
		_focus_chunk = focus
		_refresh_timer = 0.0
		_seen_exploration_version = -1


func _window_origin() -> Vector2i:
	var tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	var center: Vector2i = WorldGenerator.tile_to_chunk(tile) * WorldGenerator.CHUNK_SIZE
	return center - Vector2i(WINDOW_TILES / 2, WINDOW_TILES / 2)


## 出口瞬切或换种子时，当帧保持当前 compact/full 模式并同步刷新。
func refresh_position() -> void:
	if not is_instance_valid(_manager) or not is_instance_valid(_player):
		return
	if _sync_generator():
		_update_focus()
		_capture_loaded_chunks()
		if _texture == null or (_expanded and _exploration_version != _seen_exploration_version):
			_rebuild()
		elif not _expanded and _window_origin() != _map_origin:
			_rebuild()
		_seen_version = _manager.version
	_refresh_timer = REFRESH_INTERVAL
	queue_redraw()


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
	if not is_instance_valid(_manager) or not is_instance_valid(_player):
		return
	if not _sync_generator():
		return
	_update_focus()
	_capture_loaded_chunks()
	_refresh_timer -= delta
	var compact_changed: bool = not _expanded and _window_origin() != _map_origin
	var full_map_changed: bool = _expanded and _exploration_version != _seen_exploration_version
	if _refresh_timer <= 0.0 and (_texture == null or compact_changed or full_map_changed):
		_refresh_timer = REFRESH_INTERVAL
		_rebuild()
	_seen_version = _manager.version

	# 主角、当前箱庭标签与相机框每帧重画；区块版本不触发 compact 重采样。
	queue_redraw()


## 只保存当前可见地图的 loaded_chunks，不能把隐藏预加载邻图当作探索。
func _capture_loaded_chunks() -> void:
	if not is_instance_valid(_manager):
		return
	if _terrain_rgb.is_empty():
		_build_palette()
	var spec: MapSpec = _manager.get_map_spec()
	var changed: bool = false
	for coords: Vector2i in _manager.loaded_chunks():
		var capture_key := Vector3i(coords.x, coords.y, spec.node_id if spec != null else -1)
		if _captured_regions.has(capture_key):
			continue
		var data: ChunkData = _manager.get_cached_chunk(coords)
		if data == null:
			continue
		if spec == null:
			_explored_chunks[coords] = _build_chunk_pixels(data, FULL_MAP_TILES_PER_PIXEL)
		else:
			# 缓存包含整个边界区块；只拷贝当前箱庭，邻图以后访问时再补入。
			var origin: Vector2i = coords * WorldGenerator.CHUNK_SIZE
			var bounds := Rect2i(spec.origin, spec.extent).intersection(
				Rect2i(origin, Vector2i.ONE * WorldGenerator.CHUNK_SIZE)
			)
			if not bounds.has_area():
				continue
			var pixels: PackedByteArray
			if _explored_chunks.has(coords):
				pixels = _explored_chunks[coords]
			else:
				pixels = PackedByteArray()
				pixels.resize(WorldGenerator.CHUNK_SIZE * WorldGenerator.CHUNK_SIZE * 3)
				_fill_unknown(pixels)
			for y: int in range(bounds.position.y, bounds.end.y):
				for x: int in range(bounds.position.x, bounds.end.x):
					var local: Vector2i = Vector2i(x, y) - origin
					var index: int = local.y * WorldGenerator.CHUNK_SIZE + local.x
					var rgb: int = _color_rgb(data.terrain[index], data.route[index])
					pixels[index * 3] = (rgb >> 16) & 255
					pixels[index * 3 + 1] = (rgb >> 8) & 255
					pixels[index * 3 + 2] = rgb & 255
			_explored_chunks[coords] = pixels
		_captured_regions[capture_key] = true
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

## compact 纯 RGB 接口；允许未进场景树时测试，不上传纹理、不增加探索记录。
func build_pixels() -> PackedByteArray:
	if not _expanded:
		return _build_compact_pixels()
	if not _sync_generator():
		return PackedByteArray()
	# 全屏打开时读取 compact 数据也不能改变全屏纹理的坐标与比例。
	var origin: Vector2i = _map_origin
	var image_size: Vector2i = _map_image_size
	var map_size: int = _map_size
	var pixels_per_chunk: int = _active_pixels_per_chunk
	var tiles_per_pixel: int = _active_tiles_per_pixel
	var bytes: PackedByteArray = _build_compact_pixels()
	_map_origin = origin
	_map_image_size = image_size
	_map_size = map_size
	_active_pixels_per_chunk = pixels_per_chunk
	_active_tiles_per_pixel = tiles_per_pixel
	return bytes


func _build_compact_pixels() -> PackedByteArray:
	var bytes := PackedByteArray()
	if not is_instance_valid(_manager) or not is_instance_valid(_player):
		return bytes
	if not _sync_generator():
		return bytes
	if _terrain_rgb.is_empty():
		_build_palette()

	_map_origin = _window_origin()
	_map_size = WINDOW_TILES
	_map_image_size = Vector2i(TEXTURE_SIZE, TEXTURE_SIZE)
	_compact_pixels_per_chunk = WorldGenerator.CHUNK_SIZE / TILES_PER_PIXEL
	_active_pixels_per_chunk = _compact_pixels_per_chunk
	_active_tiles_per_pixel = TILES_PER_PIXEL
	# 预留整个新窗口的容量，确保插入过程中也不会超过缓存上限。
	if _pixel_cache.size() + TEXTURE_SIZE * TEXTURE_SIZE > PIXEL_CACHE_LIMIT:
		_trim_pixel_cache()

	bytes.resize(TEXTURE_SIZE * TEXTURE_SIZE * 3)
	var per_chunk: int = WorldGenerator.CHUNK_SIZE / TILES_PER_PIXEL
	var min_chunk: Vector2i = WorldGenerator.tile_to_chunk(_map_origin)
	var chunk_count: int = WINDOW_TILES / WorldGenerator.CHUNK_SIZE
	for chunk_y: int in chunk_count:
		for chunk_x: int in chunk_count:
			var coords: Vector2i = min_chunk + Vector2i(chunk_x, chunk_y)
			var data: ChunkData = _manager.get_cached_chunk(coords)
			var origin: Vector2i = coords * WorldGenerator.CHUNK_SIZE
			for cell_y: int in per_chunk:
				for cell_x: int in per_chunk:
					var local := Vector2i(cell_x, cell_y) * TILES_PER_PIXEL
					var tile: Vector2i = origin + local
					var rgb: int
					if data != null:
						# 缓存数据始终优先于先前的像素采样。
						var index: int = local.y * WorldGenerator.CHUNK_SIZE + local.x
						rgb = _color_rgb(data.terrain[index], data.route[index])
						_pixel_cache[tile] = rgb
					elif _pixel_cache.has(tile):
						rgb = _pixel_cache[tile]
					elif _sampler != null:
						rgb = _color_rgb(_sampler.sample_terrain(tile), _sampler.sample_route(tile))
						_pixel_cache[tile] = rgb
					else:
						# 没有生成器的旧 fixture 保留未知色，不凭空生成另一个世界。
						rgb = (int(_unknown_rgb[0]) << 16) | (int(_unknown_rgb[1]) << 8) | int(_unknown_rgb[2])

					var pixel_x: int = chunk_x * per_chunk + cell_x
					var pixel_y: int = chunk_y * per_chunk + cell_y
					var offset: int = (pixel_y * TEXTURE_SIZE + pixel_x) * 3
					bytes[offset] = (rgb >> 16) & 255
					bytes[offset + 1] = (rgb >> 8) & 255
					bytes[offset + 2] = rgb & 255
	return bytes


func _color_rgb(terrain: int, road: int) -> int:
	var palette: PackedByteArray = _terrain_rgb
	var entry: int = terrain * 3
	if road != Route.Kind.NONE:
		palette = _route_rgb
		entry = Route.atlas_row(road) * 3
	return (int(palette[entry]) << 16) | (int(palette[entry + 1]) << 8) | int(palette[entry + 2])


func _trim_pixel_cache() -> void:
	# 留当前窗口与半个窗口的周边，转身时仍可复用。
	var margin := Vector2i(WINDOW_TILES / 2, WINDOW_TILES / 2)
	var keep := Rect2i(_map_origin - margin, Vector2i(WINDOW_TILES, WINDOW_TILES) + margin * 2)
	for tile: Vector2i in _pixel_cache.keys():
		if not keep.has_point(tile):
			_pixel_cache.erase(tile)
	if _pixel_cache.size() + TEXTURE_SIZE * TEXTURE_SIZE > PIXEL_CACHE_LIMIT:
		var window := Rect2i(_map_origin, Vector2i(WINDOW_TILES, WINDOW_TILES))
		for tile: Vector2i in _pixel_cache.keys():
			if not window.has_point(tile):
				_pixel_cache.erase(tile)


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
	_map_size = width * FULL_MAP_TILES_PER_PIXEL
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
	if not is_instance_valid(_manager) or not is_instance_valid(_player):
		return
	if not _sync_generator():
		return
	if _terrain_rgb.is_empty():
		_build_palette()
	_update_focus()
	if _expanded:
		_capture_loaded_chunks()
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
	var scale_factor := Vector2(scale_x, scale_y)
	if _expanded:
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

	if is_instance_valid(_player):
		if show_camera_view:
			_draw_camera_view(map_rect, scale_factor)
		if not _expanded:
			_draw_regions(map_rect, scale_factor)
		var tile: Vector2 = _player.global_position / float(WorldGenerator.TILE_SIZE)
		var player_position: Vector2 = _tile_to_minimap(tile, map_rect, scale_factor)
		if map_rect.has_point(player_position):
			var marker_radius: float = 6.0 if _expanded else 3.5
			draw_circle(player_position, marker_radius, PLAYER_COLOR)
			draw_arc(player_position, marker_radius, 0.0, TAU, 20, PLAYER_OUTLINE, 1.5)

	draw_rect(map_rect, BORDER_COLOR, false, 1.0)


func _tile_to_minimap(tile: Vector2, map_rect: Rect2, scale_factor: Vector2) -> Vector2:
	return map_rect.position + (tile - Vector2(_map_origin)) / float(_active_tiles_per_pixel) * scale_factor


func _draw_regions(map_rect: Rect2, scale_factor: Vector2) -> void:
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	_map_node = -1
	for spec: MapSpec in _specs:
		if Rect2i(spec.origin, spec.extent).has_point(player_tile):
			_map_node = spec.node_id
			break

	var font: Font = get_theme_default_font()
	for spec: MapSpec in _specs:
		var center: Vector2 = _tile_to_minimap(Vector2(spec.origin) + Vector2(spec.center), map_rect, scale_factor)
		if not map_rect.has_point(center):
			continue
		var label: String = str(RunGraph.floor_of(spec.node_id) + 1)
		if RunGraph.variant_of(spec.node_id) == RunGraph.BRANCH_VARIANT:
			label += "·岔"
		var color: Color = ACTIVE_LABEL_COLOR if spec.node_id == _map_node else LABEL_COLOR
		var label_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var position: Vector2 = center + Vector2(-label_size.x * 0.5, -7.0)
		position.x = clampf(position.x, map_rect.position.x + 2.0, maxf(map_rect.position.x + 2.0, map_rect.end.x - label_size.x - 2.0))
		position.y = clampf(position.y, map_rect.position.y + font.get_ascent(LABEL_FONT_SIZE) + 2.0, map_rect.end.y - 2.0)
		draw_string_outline(font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, 3, PLAYER_OUTLINE)
		draw_string(font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, color)


func _draw_camera_view(map_rect: Rect2, scale_factor: Vector2) -> void:
	if not _player.is_inside_tree():
		return
	var viewport: Viewport = _player.get_viewport()
	if viewport.get_camera_2d() == null:
		return
	# 相机实际画布变换包含平滑、偏移和缩放。
	var inverse: Transform2D = viewport.get_canvas_transform().affine_inverse()
	var screen := Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	var top_left: Vector2 = inverse * screen.position
	var world_rect := Rect2(top_left, Vector2.ZERO)
	world_rect = world_rect.expand(inverse * Vector2(screen.end.x, screen.position.y))
	world_rect = world_rect.expand(inverse * screen.end)
	world_rect = world_rect.expand(inverse * Vector2(screen.position.x, screen.end.y))
	var start: Vector2 = _tile_to_minimap(world_rect.position / WorldGenerator.TILE_SIZE, map_rect, scale_factor)
	var finish: Vector2 = _tile_to_minimap(world_rect.end / WorldGenerator.TILE_SIZE, map_rect, scale_factor)
	var visible: Rect2 = Rect2(start, finish - start).intersection(map_rect)
	if visible.has_area():
		draw_rect(visible, CAMERA_COLOR, false, 1.0)


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
