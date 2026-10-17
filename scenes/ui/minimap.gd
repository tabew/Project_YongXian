class_name Minimap
extends Control

## 右上角小地图与全屏探索地图。
##
## 小地图独立采样玩家周围 512x512 格；按 M 显示整局贴合箱庭轮廓及已观察地形。
## compact 的世界像素缓存与全屏逐格探索快照相互独立。

const TERRAIN_ATLAS: String = "res://assets/terrain_tiles.png"
const ROAD_ATLAS: String = "res://assets/road_tiles.png"

## 小地图为 512 格 / 128 像素；全屏保持逐格探索细节。
const TILES_PER_PIXEL: int = 4
const WINDOW_TILES: int = 512
const TEXTURE_SIZE: int = WINDOW_TILES / TILES_PER_PIXEL
const COMPACT_TILES_PER_PIXEL: int = TILES_PER_PIXEL
const FULL_MAP_TILES_PER_PIXEL: int = 1
## 全屏地图至少显示以玩家为中心的 15x7 个区块。
const FULL_MAP_HALF_CHUNKS: Vector2i = Vector2i(7, 3)
const REFRESH_INTERVAL: float = 0.25
## 每帧最多快照几个区块的探索像素，避免进图时一次性拷贝整张地图；
## 转场期间没有画面要画，可以多做，淡入时小地图已经补齐。
const CAPTURE_BUDGET: int = 8
const CAPTURE_BUDGET_TRANSITION: int = 24
## 图集里取色的位置（每块贴图的正中心）。
const ATLAS_PROBE: int = 8
const FULL_MAP_MARGIN: float = 48.0
## 全屏地图的缩放范围与滚轮步进；1.0 表示整局适配。
const FULL_MAP_MIN_ZOOM: float = 0.6
const FULL_MAP_MAX_ZOOM: float = 8.0
const FULL_MAP_ZOOM_STEP: float = 1.18
const HINT_FONT_SIZE: int = 12

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
const HINT_COLOR: Color = Color(0.78, 0.84, 0.92, 0.85)
## 区域染色的羽化层数与每层内缩像素。
const REGION_TINT_STEPS: int = 7
const REGION_TINT_INSET: float = 2.5
const REGION_TINT_ALPHA: float = 0.26

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
var _seed: int = 0
var _specs: Array[MapSpec] = []
## 全屏地图的缩放与平移；1.0 / 零偏移表示整局适配。
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _dragging: bool = false
## 待快照的区块队列（近的先做），避免进图时一次性拷贝整张地图。
var _capture_queue: Array[Vector2i] = []
## 同一个世界区块可能分属两个箱庭，分别记录已捕获的矩形区域。
var _captured_regions: Dictionary = {}

## 已探索区块的像素快照，确保区块离开缓存后仍能在全屏地图中显示。
var _explored_chunks: Dictionary = {}
var _exploration_version: int = 0
var _seen_exploration_version: int = -1
## 去过（有已探索区块）的箱庭；小地图只标出这些。
var _visited_regions: Dictionary = {}
var _visited_version: int = -1


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
	_specs.clear()
	_capture_queue.clear()
	_captured_regions.clear()
	_explored_chunks.clear()
	_exploration_version = 0
	_seen_exploration_version = -1
	_visited_regions.clear()
	_visited_version = -1
	_zoom = 1.0
	_pan = Vector2.ZERO
	_dragging = false


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
		if _is_stale():
			_rebuild()
		_seen_version = _manager.version
	_refresh_timer = REFRESH_INTERVAL
	queue_redraw()


## compact 与全屏都建立在探索记录上，所以新探索到的区块也要触发重建。
func _is_stale() -> bool:
	if _texture == null or _exploration_version != _seen_exploration_version:
		return true
	if _expanded:
		return false
	return _window_origin() != _map_origin


func set_expanded(value: bool) -> void:
	if _expanded == value:
		return
	_expanded = value
	# 每次开关都回到整局适配；滚轮缩放和中键拖动在这个基础上叠加。
	_zoom = 1.0
	_pan = Vector2.ZERO
	_dragging = false

	if _expanded:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		z_index = 100
		mouse_filter = Control.MOUSE_FILTER_STOP
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
		mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	if _refresh_timer <= 0.0 and _is_stale():
		_refresh_timer = REFRESH_INTERVAL
		_rebuild()
	_seen_version = _manager.version

	# 主角、当前箱庭标签与相机框每帧重画；区块版本不触发 compact 重采样。
	queue_redraw()


## 每帧最多快照 CAPTURE_BUDGET 个区块，近的先做：进图时不再一次性拷贝整张地图。
## 只保存当前可见地图的 loaded_chunks，不能把隐藏预加载邻图当作探索。
func _capture_loaded_chunks() -> void:
	if not is_instance_valid(_manager):
		return
	if _terrain_rgb.is_empty():
		_build_palette()
	var spec: MapSpec = _manager.get_map_spec()
	if _capture_queue.is_empty():
		_capture_queue = _pending_capture_chunks(spec)
		if _capture_queue.is_empty():
			return
	var taken: int = 0
	var budget: int = CAPTURE_BUDGET_TRANSITION if _in_transition() else CAPTURE_BUDGET
	while taken < budget and not _capture_queue.is_empty():
		var coords: Vector2i = _capture_queue.pop_front()
		if _capture_chunk(coords, spec):
			taken += 1
	if taken > 0:
		_exploration_version += 1


## 转场中：黑屏期间没有画面要画，快照可以多做一点。
## 自动加载单例用运行期查找而不是全局标识符，这样本脚本仍能作为全局类被其他
## 脚本引用并在 --script 单元测试里编译。
func _in_transition() -> bool:
	var manager: Node = get_node_or_null("/root/SceneManager")
	return manager != null and bool(manager.call("is_transitioning"))


## 还没快照过的已铺区块；近的排前面，小地图先补齐玩家身边。
func _pending_capture_chunks(spec: MapSpec) -> Array[Vector2i]:
	var node_id: int = spec.node_id if spec != null else -1
	var pending: Array[Vector2i] = []
	for coords: Vector2i in _manager.loaded_chunks():
		if _captured_regions.has(Vector3i(coords.x, coords.y, node_id)):
			continue
		if _manager.get_cached_chunk(coords) == null:
			continue
		pending.append(coords)
	if pending.size() <= 1:
		return pending
	var focus := Vector2(_focus_chunk)
	pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(focus) < Vector2(b).distance_squared_to(focus)
	)
	return pending


func _capture_chunk(coords: Vector2i, spec: MapSpec) -> bool:
	var data: ChunkData = _manager.get_cached_chunk(coords)
	if data == null:
		return false
	var node_id: int = spec.node_id if spec != null else -1
	if spec == null:
		_explored_chunks[coords] = _build_chunk_pixels(data, FULL_MAP_TILES_PER_PIXEL)
	else:
		# 缓存包含整个边界区块；只拷贝当前箱庭，邻图以后访问时再补入。
		var origin: Vector2i = coords * WorldGenerator.CHUNK_SIZE
		var bounds := Rect2i(spec.origin, spec.extent).intersection(
			Rect2i(origin, Vector2i.ONE * WorldGenerator.CHUNK_SIZE)
		)
		if not bounds.has_area():
			return false
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
	_captured_regions[Vector3i(coords.x, coords.y, node_id)] = true
	return true


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


## 小地图只画已探索过的区块：没去过的箱庭保持迷雾，不提前泄露地形。
## 数据来自与全屏地图同一份探索快照（1 格 / 像素），按 4 格 / 像素降采样。
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

	bytes.resize(TEXTURE_SIZE * TEXTURE_SIZE * 3)
	_fill_unknown(bytes)
	var per_chunk: int = WorldGenerator.CHUNK_SIZE / TILES_PER_PIXEL
	var min_chunk: Vector2i = WorldGenerator.tile_to_chunk(_map_origin)
	var chunk_count: int = WINDOW_TILES / WorldGenerator.CHUNK_SIZE
	var snapshot_side: int = WorldGenerator.CHUNK_SIZE
	for chunk_y: int in chunk_count:
		for chunk_x: int in chunk_count:
			var coords: Vector2i = min_chunk + Vector2i(chunk_x, chunk_y)
			if not _explored_chunks.has(coords):
				continue
			var snapshot: PackedByteArray = _explored_chunks[coords]
			if snapshot.size() < snapshot_side * snapshot_side * 3:
				continue
			for cell_y: int in per_chunk:
				var source_row: int = cell_y * TILES_PER_PIXEL * snapshot_side
				for cell_x: int in per_chunk:
					var source: int = (source_row + cell_x * TILES_PER_PIXEL) * 3
					var target_x: int = chunk_x * per_chunk + cell_x
					var target_y: int = chunk_y * per_chunk + cell_y
					var target: int = (target_y * TEXTURE_SIZE + target_x) * 3
					bytes[target] = snapshot[source]
					bytes[target + 1] = snapshot[source + 1]
					bytes[target + 2] = snapshot[source + 2]
	return bytes


func _color_rgb(terrain: int, road: int) -> int:
	var palette: PackedByteArray = _terrain_rgb
	var entry: int = terrain * 3
	if road != Route.Kind.NONE:
		palette = _route_rgb
		entry = Route.atlas_row(road) * 3
	return (int(palette[entry]) << 16) | (int(palette[entry + 1]) << 8) | int(palette[entry + 2])


## 全屏地图至少覆盖 15x7 区块，并在此基础上包含全部已探索区块。
func _build_explored_pixels() -> PackedByteArray:
	var bytes := PackedByteArray()
	var min_chunk: Vector2i = _focus_chunk - FULL_MAP_HALF_CHUNKS
	var max_chunk: Vector2i = _focus_chunk + FULL_MAP_HALF_CHUNKS
	# 世界总览覆盖全部箱庭轮廓；未知地形仍保持探索迷雾。
	for spec: MapSpec in _specs:
		var first: Vector2i = WorldGenerator.tile_to_chunk(spec.origin)
		var last: Vector2i = WorldGenerator.tile_to_chunk(spec.origin + spec.extent - Vector2i.ONE)
		min_chunk = min_chunk.min(first)
		max_chunk = max_chunk.max(last)
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
		_draw_regions(map_rect, scale_factor)
		var tile: Vector2 = _player.global_position / float(WorldGenerator.TILE_SIZE)
		var player_position: Vector2 = _tile_to_minimap(tile, map_rect, scale_factor)
		if map_rect.has_point(player_position):
			var marker_radius: float = 6.0 if _expanded else 3.5
			draw_circle(player_position, marker_radius, PLAYER_COLOR)
			draw_arc(player_position, marker_radius, 0.0, TAU, 20, PLAYER_OUTLINE, 1.5)

	draw_rect(map_rect, BORDER_COLOR, false, 1.0)
	if _expanded:
		_draw_hint()


## 全屏地图的操作提示。
func _draw_hint() -> void:
	var font: Font = get_theme_default_font()
	var text: String = "滚轮缩放 · 中键拖动 · M 关闭"
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE)
	var position := Vector2((size.x - text_size.x) * 0.5, size.y - 18.0)
	draw_string_outline(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE, 3, PLAYER_OUTLINE)
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE, HINT_COLOR)


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
	var visited: Dictionary = _visited_region_set()
	for spec: MapSpec in _specs:
		# 右上角小地图只标出已经探索过的箱庭，没去过的不泄露。
		if not _expanded and not visited.has(spec.node_id):
			continue
		if _expanded:
			var start: Vector2 = _tile_to_minimap(Vector2(spec.origin), map_rect, scale_factor)
			var end: Vector2 = _tile_to_minimap(Vector2(spec.origin + spec.extent), map_rect, scale_factor)
			var bounds: Rect2 = Rect2(start, end - start).intersection(map_rect)
			if bounds.has_area():
				# 区域染色：多层内缩矩形叠出羽化边缘，区域之间不再有硬边和边框线。
				var rgb: int = _color_rgb(RegionBiomes.ground_for(spec.biome_id), Route.Kind.NONE)
				var shade := Color(
					float((rgb >> 16) & 255) / 255.0,
					float((rgb >> 8) & 255) / 255.0,
					float(rgb & 255) / 255.0
				)
				for step: int in REGION_TINT_STEPS:
					var area: Rect2 = bounds.grow(-float(step) * REGION_TINT_INSET)
					if not area.has_area():
						break
					draw_rect(
						area,
						Color(shade.r, shade.g, shade.b, REGION_TINT_ALPHA / float(REGION_TINT_STEPS)),
						true
					)
		var center: Vector2 = _tile_to_minimap(Vector2(spec.origin) + Vector2(spec.center), map_rect, scale_factor)
		if not map_rect.has_point(center):
			continue
		var label: String = str(RunGraph.floor_of(spec.node_id) + 1)
		if RunGraph.variant_of(spec.node_id) != RunGraph.MAIN_VARIANT:
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
	var fitted: Rect2 = _fitted_map_rect()
	if is_equal_approx(_zoom, 1.0) and _pan.is_zero_approx():
		return fitted
	var scaled: Vector2 = fitted.size * _zoom
	var center: Vector2 = fitted.get_center() + _pan
	return Rect2(center - scaled * 0.5, scaled)


## 整局适配：把整张探索图放进可用区域，居中。
func _fitted_map_rect() -> Rect2:
	var available := Vector2(
		maxf(size.x - FULL_MAP_MARGIN * 2.0, 1.0),
		maxf(size.y - FULL_MAP_MARGIN * 2.0, 1.0)
	)
	var scale_factor: float = minf(
		available.x / float(_image.get_width()),
		available.y / float(_image.get_height())
	)
	var fitted_size := Vector2(
		float(_image.get_width()) * scale_factor,
		float(_image.get_height()) * scale_factor
	)
	return Rect2((size - fitted_size) * 0.5, fitted_size)


# ------------------------------------------------------------ 全屏地图的缩放与拖动

## 展开时在 _input 阶段直接接管滚轮与中键：不依赖鼠标 hover，也不受其他
## _input 处理器的树序影响（物品栏也会在 _input 里读滚轮）。
func _input(event: InputEvent) -> void:
	if not _expanded:
		return
	if _handle_pointer(event):
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not _expanded:
		return
	if _handle_pointer(event):
		accept_event()


## 处理滚轮缩放与中键拖动；吃掉事件时返回 true。
func _handle_pointer(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button != null:
		if not button.pressed:
			if button.button_index == MOUSE_BUTTON_MIDDLE:
				_dragging = false
				return true
			return false
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(FULL_MAP_ZOOM_STEP, button.position)
			return true
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / FULL_MAP_ZOOM_STEP, button.position)
			return true
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = true
			return true
		return false
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_pan += motion.relative
		_clamp_pan()
		queue_redraw()
		return true
	return false


## 以光标为锚点缩放：光标下的那一点保持不动。
func _zoom_at(factor: float, focus: Vector2) -> void:
	var before: Rect2 = _calculate_map_rect()
	var next_zoom: float = clampf(_zoom * factor, FULL_MAP_MIN_ZOOM, FULL_MAP_MAX_ZOOM)
	if is_equal_approx(next_zoom, _zoom):
		return
	var anchor: Vector2 = (focus - before.position) / before.size
	_zoom = next_zoom
	var after: Rect2 = _calculate_map_rect()
	_pan += focus - (after.position + after.size * anchor)
	_clamp_pan()
	queue_redraw()


## 放大后可以拖到地图边缘，但不会把地图拖出画面；适配状态下面板归零。
func _clamp_pan() -> void:
	var fitted: Rect2 = _fitted_map_rect()
	var limit := Vector2(
		maxf(fitted.size.x * (_zoom - 1.0) * 0.5, 0.0),
		maxf(fitted.size.y * (_zoom - 1.0) * 0.5, 0.0)
	)
	_pan = _pan.clamp(-limit, limit)


## 去过的箱庭集合：小地图只标出这些，没探索过的不显示。
func _visited_region_set() -> Dictionary:
	if _visited_version == _exploration_version:
		return _visited_regions
	_visited_version = _exploration_version
	_visited_regions.clear()
	for coords: Vector2i in _explored_chunks.keys():
		var bounds := Rect2i(
			coords * WorldGenerator.CHUNK_SIZE, Vector2i.ONE * WorldGenerator.CHUNK_SIZE
		)
		for spec: MapSpec in _specs:
			if _visited_regions.has(spec.node_id):
				continue
			if Rect2i(spec.origin, spec.extent).intersects(bounds):
				_visited_regions[spec.node_id] = true
	return _visited_regions
