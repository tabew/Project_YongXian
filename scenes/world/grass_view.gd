class_name GrassView
extends Node2D

## 一小片草丛（8x8 格 = 128 像素见方），星露谷式牧草：一簇就是一丛草，比角色高，
## 画在角色与怪物之上，武器挥过即清除。
##
## 为什么按 8x8 格切：`_draw` 是整块重绘，块越小，除草时重绘的开销越低；
## 同时每块只有几十簇，武器切割只需检查邻近的几块。
##
## 数据来自 ChunkData 的 terrain / route 字节数组，不重新采样噪声，与铺出来的地形
## 永远一致；清除状态按箱庭共享（同一个 Dictionary 引用），离开再返回不会补刷。

## 每块的边长（格）。
const CELL_TILES: int = 8
const CELL_PIXELS: float = float(CELL_TILES * WorldGenerator.TILE_SIZE)
## 一次切割最多溅几片草屑。
const MAX_EFFECTS_PER_CUT: int = 2

const SHADOW := Color(0.06, 0.11, 0.05, 0.22)
const LEAF_MIN_PIXELS: float = 0.55
const LEAF_MAX_PIXELS: float = 0.95

## 每套配色：0 根部暗色，1 叶身，2 受光叶尖。顺序与 WorldGrass.Palette 一致。
const PALETTES: Array = [
	[Color("254a1d"), Color("3a7a2c"), Color("69a648")],   # 草地
	[Color("5f5820"), Color("8a7d2e"), Color("b8ab5c")],   # 稀树草原
	[Color("1f3a26"), Color("356035"), Color("6d9a52")],   # 沼泽芦草
	[Color("42513f"), Color("647458"), Color("9aab80")],   # 苔原
	[Color("6e5f36"), Color("9a8647"), Color("c9b87c")],   # 沙漠枯草
	[Color("33422f"), Color("526547"), Color("7d8f68")],   # 石地
	[Color("46553f"), Color("708364"), Color("cfe0da")],   # 雪原顶雪
]

## 格坐标 -> [GrassView]。武器用包围盒直接定位邻近的块，不遍历整棵树的节点。
static var _cells: Dictionary = {}

## 相对角色的绘制层级：整块在脚底以上就在角色背后，以下就在角色前面。
const BACK_Z: int = 0
const FRONT_Z: int = 1
## 本块草与人物脚底分割线的关系。
enum Layer { BACK = 0, FRONT = 1, SPLIT = 2 }

var _cell: Vector2i = Vector2i.ZERO
## 本块可长草的实际范围（与地图矩形求交）。
var _rect: Rect2i = Rect2i()
var _generator: WorldGenerator = null
var _context: GrassContext = null
## 与所在箱庭共享的清除记录：key -> true。
var _cleared: Dictionary = {}

var _positions: PackedVector2Array = PackedVector2Array()
var _key_x: PackedInt32Array = PackedInt32Array()
var _key_y: PackedInt32Array = PackedInt32Array()
var _scales: PackedFloat32Array = PackedFloat32Array()
var _shapes: PackedByteArray = PackedByteArray()
var _flips: PackedByteArray = PackedByteArray()
var _tints: PackedByteArray = PackedByteArray()
var _palettes: PackedByteArray = PackedByteArray()
var _blade_seeds: PackedInt32Array = PackedInt32Array()
var _populated: bool = false
## 本块所有草根的 Y 范围，用来快速判断分割线有没有穿过本块。
var _y_min: float = INF
var _y_max: float = -INF
## 人物脚底的世界 Y：比它靠上的草画在人物后面，靠下的画在前面。
## 负无穷表示"还没有角色"，全部画在前面（也就是旧的"草一直盖住人"）。
var split_y: float = -INF
var _layer: int = Layer.FRONT
## 本块当前是否在与角色重叠的焦点范围内（决定走逐簇还是整块归层）。
var _splitting: bool = false
## 被分割线穿过时，上半部分交给这个兄弟节点绘制（画在角色背后）。
var _back: Node2D = null


func bind(
	cell: Vector2i,
	map_rect: Rect2i,
	generator: WorldGenerator,
	context: GrassContext,
	cleared: Dictionary
) -> void:
	_cell = cell
	_map_rect_setup(map_rect)
	_generator = generator
	_context = context
	_cleared = cleared
	position = Vector2(cell * CELL_TILES) * float(WorldGenerator.TILE_SIZE)
	z_index = FRONT_Z
	_register_cell()


func _map_rect_setup(map_rect: Rect2i) -> void:
	var bounds := Rect2i(_cell * CELL_TILES, Vector2i.ONE * CELL_TILES)
	_rect = bounds.intersection(map_rect)


func _exit_tree() -> void:
	var bucket: Array = _cells.get(_cell, [])
	bucket.erase(self)
	if bucket.is_empty():
		_cells.erase(_cell)
	if _back != null and is_instance_valid(_back):
		_back.queue_free()
		_back = null


func is_populated() -> bool:
	return _populated


## 本块里还没被清除的草丛数量；供测试与调试使用。
func live_clumps() -> int:
	var live: int = 0
	for index: int in _positions.size():
		if not _cleared.has(Vector2i(_key_x[index], _key_y[index])):
			live += 1
	return live


# ------------------------------------------------------------ 与角色的前后关系

## 按人物脚底的世界 Y 决定本块的绘制层级：
## 整块在脚底以上 -> 整块画在角色背后（人踩在草上）；整块在脚底以下 -> 画在角色前面。
## 只有被脚底分割线穿过的那一块，才把上半部分交给后层节点，保证逐簇排序。
func set_split(world_y: float) -> void:
	if world_y == split_y:
		return
	var low: float = minf(world_y, split_y)
	var high: float = maxf(world_y, split_y)
	split_y = world_y
	var next: int = layer_for(world_y)
	if next != _layer:
		_layer = next
		z_index = BACK_Z if next == Layer.BACK else FRONT_Z
		if next == Layer.SPLIT:
			_ensure_back()
		_mark_dirty()
		return
	# 同一层里只有真的跨过了某簇草根才需要重绘，走直线时不会每帧重画。
	if next == Layer.SPLIT and _crosses_split(low, high):
		_mark_dirty()


## 本块相对分割线落在哪一层。
func layer_for(world_y: float) -> int:
	if _positions.is_empty():
		return Layer.FRONT
	if _y_max < world_y:
		return Layer.BACK
	if _y_min >= world_y:
		return Layer.FRONT
	return Layer.SPLIT


## 每帧由 GameWorld 调用：
## 只有可能和角色重叠的那一两块才逐簇分层（跨线才重绘），
## 其余整块按脚底归到前 / 后层 —— 只改 z_index，走直线时完全不重绘。
func update_focus(feet_y: float, focus_rect: Rect2) -> void:
	if _bounds().intersects(focus_rect):
		if not _splitting:
			# 从整块归层切到逐簇：复位后走一次完整更新。
			_splitting = true
			_layer = Layer.FRONT
			z_index = FRONT_Z
			split_y = -INF
		set_split(feet_y)
		return
	if _splitting:
		# 离开焦点：整块归层，并重绘一次把交给后层的草收回来。
		_splitting = false
		_layer = Layer.FRONT
		z_index = FRONT_Z
		split_y = -INF
		_mark_dirty()
	split_y = feet_y
	var next: int = Layer.FRONT
	if not _positions.is_empty() and _y_max < feet_y:
		next = Layer.BACK
	if next != _layer:
		_layer = next
		z_index = BACK_Z if next == Layer.BACK else FRONT_Z


## 本块在世界上覆盖的矩形，用来判断它会不会和角色重叠。
func _bounds() -> Rect2:
	return Rect2(position, Vector2.ONE * CELL_PIXELS)


func _crosses_split(low: float, high: float) -> bool:
	if high < _y_min or low > _y_max:
		return false
	for index: int in _positions.size():
		var at: float = _positions[index].y
		if at >= low and at < high:
			return true
	return false


## 跨线时才建后层兄弟节点；它没有脚本，只在 draw 信号里发绘制命令。
func _ensure_back() -> void:
	if _back != null and is_instance_valid(_back):
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	_back = Node2D.new()
	_back.name = "%s_back" % name
	_back.position = position
	_back.z_index = BACK_Z
	_back.draw.connect(_draw_back_items)
	parent.add_child(_back)


## 后层节点：只画分割线以上的草（这些草盖住站着的人物）。
func _draw_back_items() -> void:
	if _layer != Layer.SPLIT or _back == null:
		return
	for index: int in _positions.size():
		if _cleared.has(Vector2i(_key_x[index], _key_y[index])):
			continue
		if _positions[index].y >= split_y:
			continue
		draw_clump_into(_back, index)


## 分割线以下还没被清除的簇数（测试与调试用）。
func below_split_count() -> int:
	var count: int = 0
	for index: int in _positions.size():
		if _cleared.has(Vector2i(_key_x[index], _key_y[index])):
			continue
		if _positions[index].y >= split_y:
			count += 1
	return count


## 分割线以上还没被清除的簇数（测试与调试用）。
func above_split_count() -> int:
	return maxi(live_clumps() - below_split_count(), 0)


## 用区块数据生成这一块的草丛：只长地图范围内的自然地面、避开排除区。
func populate(chunk_data: ChunkData, chunk_coords: Vector2i) -> void:
	if _populated or chunk_data == null or _generator == null or _context == null:
		return
	var cell_origin: Vector2i = _cell * CELL_TILES
	var offset: Vector2i = cell_origin - chunk_coords * WorldGenerator.CHUNK_SIZE
	var size: int = chunk_data.size
	# 8 整除区块边长，所以一块永远落在一个区块里。
	if offset.x < 0 or offset.y < 0 or offset.x + CELL_TILES > size or offset.y + CELL_TILES > size:
		return
	var seed: int = _generator.world_seed
	var variant: int = _generator.variant
	for local_y: int in CELL_TILES:
		for local_x: int in CELL_TILES:
			var tile: Vector2i = cell_origin + Vector2i(local_x, local_y)
			if not _rect.has_point(tile) or not _context.allows(tile):
				continue
			var index: int = (offset.y + local_y) * size + offset.x + local_x
			if chunk_data.route[index] != Route.Kind.NONE:
				continue
			for clump: Dictionary in WorldGrass.tufts_at(
				seed, variant, chunk_data.terrain[index], tile
			):
				_positions.append(clump["position"])
				_key_x.append(clump["key"].x)
				_key_y.append(clump["key"].y)
				_scales.append(clump["scale"])
				_shapes.append(clump["shape"])
				_flips.append(clump["flip"])
				_tints.append(int(round(float(clump["tint"]) * 255.0)))
				_palettes.append(clump["palette"])
				_blade_seeds.append(clump["blade_seed"])
				_y_min = minf(_y_min, clump["position"].y)
				_y_max = maxf(_y_max, clump["position"].y)
	_populated = true
	_mark_dirty()


## 武器形状（世界坐标多边形）掠过时清除范围内的草丛，返回新清除的簇数。
func cut_area(points: PackedVector2Array) -> int:
	if points.size() < 3 or _positions.is_empty():
		return 0
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for point: Vector2 in points:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	var cut: int = 0
	var effects: int = 0
	for index: int in _positions.size():
		var key := Vector2i(_key_x[index], _key_y[index])
		if _cleared.has(key):
			continue
		var at: Vector2 = _positions[index]
		if at.x < min_x or at.x > max_x or at.y < min_y or at.y > max_y:
			continue
		if not Geometry2D.is_point_in_polygon(at, points):
			continue
		_cleared[key] = true
		cut += 1
		if effects < MAX_EFFECTS_PER_CUT:
			GrassCutEffect.spawn(self, at, float(_tints[index]) / 255.0)
			effects += 1
	if cut > 0:
		# 后层节点也在画这批草，只重绘自己会留下残影。
		_mark_dirty()
	return cut


## 内容变了：前后两层都要重绘（后层只在跨线时存在）。
func _mark_dirty() -> void:
	queue_redraw()
	if _back != null and is_instance_valid(_back):
		_back.queue_redraw()


## 用一块圆形范围清除草丛（闪电、爆炸、药水等范围效果用）。
## 与武器共用同一份清除记录，切过的草不会补刷。
static func clear_circle(center: Vector2, radius: float) -> int:
	if radius <= 0.0:
		return 0
	var safe_radius: float = maxf(radius, 1.0)
	var steps: int = 12
	var points := PackedVector2Array()
	points.resize(steps)
	for index: int in steps:
		var angle: float = TAU * float(index) / float(steps)
		points[index] = center + Vector2(cos(angle), sin(angle)) * safe_radius
	var cut: int = 0
	for node: Node in views_in_rect(
		Rect2(center - Vector2.ONE * safe_radius, Vector2.ONE * safe_radius * 2.0)
	):
		var view := node as GrassView
		if view == null or not view.is_visible_in_tree():
			continue
		cut += view.cut_area(points)
	if cut > 0:
		_play_cut_sfx(center)
	return cut


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载。
static func _play_cut_sfx(at: Vector2) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var manager: Node = tree.root.get_node_or_null("AudioManager")
	if manager != null:
		manager.call("play_sfx", &"cut_grass", at)


## 落在矩形内的所有草丛块；武器按形状包围盒取，通常只有 1-4 块。
static func views_in_rect(world_rect: Rect2) -> Array:
	var result: Array = []
	var first := Vector2i(
		floori(world_rect.position.x / CELL_PIXELS),
		floori(world_rect.position.y / CELL_PIXELS)
	)
	var last := Vector2i(
		floori(maxf(world_rect.end.x - 0.001, world_rect.position.x) / CELL_PIXELS),
		floori(maxf(world_rect.end.y - 0.001, world_rect.position.y) / CELL_PIXELS)
	)
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var bucket: Array = _cells.get(Vector2i(x, y), [])
			if not bucket.is_empty():
				result.append_array(bucket)
	return result


func _register_cell() -> void:
	var bucket: Array = _cells.get(_cell, [])
	if bucket.is_empty():
		# 同一块可能被两张相邻箱庭各持有一份视图，注册表按块保存列表。
		_cells[_cell] = bucket
	if not bucket.has(self):
		bucket.append(self)


func _draw() -> void:
	# 被人物脚底分割线穿过时，脚底以上的部分交给后层节点，这里只画前面的。
	var splitting: bool = _layer == Layer.SPLIT
	for index: int in _positions.size():
		if _cleared.has(Vector2i(_key_x[index], _key_y[index])):
			continue
		if splitting and _positions[index].y < split_y:
			continue
		draw_clump_into(self, index)


## 一丛草：根部阴影加 5-8 片叶子。叶子从同一个根心长出、叶尖向外散开，
## 组合起来才像"一簇草"；叶片用顶点色做根深尖浅的渐变。
## 绘制命令必须发在正在绘制的那个节点上，所以这里显式传入 item。
func draw_clump_into(item: CanvasItem, index: int) -> void:
	var base: Vector2 = _positions[index] - position
	var scale: float = _scales[index]
	var tint: float = float(_tints[index]) / 255.0
	var palette: Array = PALETTES[_palettes[index]]
	var root_color: Color = palette[0]
	var body_color: Color = palette[1]
	var tip_color: Color = palette[2]
	var lean: float = -1.0 if _flips[index] > 0 else 1.0
	# 比 16 像素的角色更高，所以能盖住人和怪。
	var height: float = lerpf(20.0, 29.0, tint) * scale
	var root_radius: float = lerpf(1.2, 2.1, tint) * scale
	var tip_reach: float = lerpf(5.0, 8.5, tint) * scale
	var count: int = WorldGrass.blade_count(_shapes[index])
	var state: int = _blade_seeds[index]
	item.draw_rect(
		Rect2(base.x - root_radius - 1.5, base.y - 1.0, (root_radius + 1.5) * 2.0, 2.5),
		SHADOW
	)
	var blade_points := PackedVector2Array()
	var blade_colors := PackedColorArray()
	blade_points.resize(3)
	blade_colors.resize(3)
	blade_colors[0] = root_color
	blade_colors[2] = root_color
	for blade: int in count:
		state = WorldGrass.next_state(state)
		var jitter: float = WorldGrass.unit(state)
		state = WorldGrass.next_state(state)
		var tall: float = WorldGrass.unit(state)
		state = WorldGrass.next_state(state)
		var light: float = WorldGrass.unit(state)
		# fan 是这一片叶子在扇面上的位置：-1 最左，0 中间，1 最右。
		var fan: float = ((float(blade) + 0.5) / float(count) - 0.5) * 2.0
		var ratio: float = lerpf(0.48, 1.0, 1.0 - absf(fan)) * lerpf(0.85, 1.15, tall)
		var blade_height: float = height * clampf(ratio, 0.35, 1.15)
		var root_x: float = base.x + fan * root_radius + (jitter - 0.5) * 1.1
		var tip := Vector2(
			base.x + fan * tip_reach + lean * blade_height * 0.14 + (jitter - 0.5) * 1.3,
			base.y - blade_height
		)
		var half: float = lerpf(LEAF_MIN_PIXELS, LEAF_MAX_PIXELS, 1.0 - ratio)
		blade_points[0] = Vector2(root_x - half, base.y)
		blade_points[1] = tip
		blade_points[2] = Vector2(root_x + half, base.y)
		blade_colors[1] = body_color.lerp(tip_color, clampf(light * 0.35 + ratio * 0.65, 0.0, 1.0))
		item.draw_polygon(blade_points, blade_colors)
