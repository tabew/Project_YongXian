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
	_register_cell()


func _map_rect_setup(map_rect: Rect2i) -> void:
	var bounds := Rect2i(_cell * CELL_TILES, Vector2i.ONE * CELL_TILES)
	_rect = bounds.intersection(map_rect)


func _exit_tree() -> void:
	var bucket: Array = _cells.get(_cell, [])
	bucket.erase(self)
	if bucket.is_empty():
		_cells.erase(_cell)


func is_populated() -> bool:
	return _populated


## 本块里还没被清除的草丛数量；供测试与调试使用。
func live_clumps() -> int:
	var live: int = 0
	for index: int in _positions.size():
		if not _cleared.has(Vector2i(_key_x[index], _key_y[index])):
			live += 1
	return live


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
	_populated = true
	queue_redraw()


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
		queue_redraw()
	return cut


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
	for index: int in _positions.size():
		if _cleared.has(Vector2i(_key_x[index], _key_y[index])):
			continue
		_draw_clump(index)


## 一丛草：根部阴影加 5-8 片叶子。叶子从同一个根心长出、叶尖向外散开，
## 组合起来才像"一簇草"；叶片用顶点色做根深尖浅的渐变。
func _draw_clump(index: int) -> void:
	var base: Vector2 = to_local(_positions[index])
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
	draw_rect(
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
		draw_polygon(blade_points, blade_colors)
