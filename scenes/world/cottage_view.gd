class_name CottageView
extends Node2D

## 开顶小屋：画面与地形碰撞都读取 CottageLayout，不生成图片或交互节点。
const TILE_SIZE: int = 16
const WOOD_DARK := Color("493023")
const WOOD_EDGE := Color("704830")
const WOOD_LIGHT := Color("d8a568")
const WALL_TOP := Color("a87145")
const CREAM := Color("f3dbab")

var _spec: MapSpec = null
var _layout: CottageLayout = null


func bind(spec: MapSpec) -> void:
	_spec = spec
	_layout = spec.cottage if spec != null else null
	position = Vector2(spec.origin) * TILE_SIZE if spec != null else Vector2.ZERO
	visible = _layout != null
	queue_redraw()


func _draw() -> void:
	if _layout == null:
		return
	_draw_floor()
	_draw_porch()
	_draw_rug()
	_draw_walls()
	_draw_windows()
	for item: Dictionary in _layout.furniture:
		_draw_furniture(item)
	_draw_lamps()


func _pixels(rect: Rect2i) -> Rect2:
	return Rect2(Vector2(rect.position) * TILE_SIZE, Vector2(rect.size) * TILE_SIZE)


func _draw_floor() -> void:
	var bounds: Rect2i = _layout.bounds
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var tile := Vector2i(x, y)
			if _layout.is_wall(tile):
				continue
			var grain: int = posmod(x * 13 + y * 7 + _layout.floor_variant * 3, 5)
			var shade: float = float(grain) * 0.018
			var color := Color(0.64 + shade, 0.42 + shade, 0.25 + shade * 0.6)
			var rect := Rect2(Vector2(tile) * TILE_SIZE, Vector2.ONE * TILE_SIZE)
			draw_rect(rect, color)
			draw_line(rect.position + Vector2(0, 15), rect.position + Vector2(16, 15), WOOD_EDGE, 1.0)
			if posmod(x + y, 3) == 0:
				draw_line(rect.position, rect.position + Vector2(0, 15), WOOD_EDGE, 1.0)
			if grain == 0:
				draw_line(rect.position + Vector2(3, 5), rect.position + Vector2(11, 5), Color(0.84, 0.63, 0.37, 0.3), 1.0)


func _draw_porch() -> void:
	var rect := Rect2i(_layout.door_tile + Vector2i(1, -2), Vector2i(4, 5))
	var pixels: Rect2 = _pixels(rect)
	draw_rect(pixels.grow(2), WOOD_DARK)
	draw_rect(pixels, Color("ad7a49"))
	for y: int in range(1, rect.size.y):
		var start: Vector2 = pixels.position + Vector2(0, y * TILE_SIZE)
		draw_line(start, start + Vector2(pixels.size.x, 0), WOOD_EDGE, 2.0)
	# 平台的上下短栏杆不跨出入口；只作地面边缘装饰。
	draw_rect(Rect2(pixels.position, Vector2(pixels.size.x, 3)), WOOD_LIGHT)
	draw_rect(Rect2(pixels.position + Vector2(0, pixels.size.y - 3), Vector2(pixels.size.x, 3)), WOOD_EDGE)
	var threshold := Rect2(Vector2(_layout.door_tile + Vector2i(0, -1)) * TILE_SIZE, Vector2(16, 48))
	draw_rect(threshold, Color("c89456"))
	draw_rect(Rect2(threshold.position + Vector2(7, 0), Vector2(2, 48)), WOOD_LIGHT)


func _draw_rug() -> void:
	var pixels: Rect2 = _pixels(_layout.rug).grow(-2)
	draw_rect(pixels, Color("633b3b"))
	draw_rect(pixels.grow(-3), Color("a45845"))
	draw_rect(pixels.grow(-7), Color("bd7650"), false, 2.0)
	for y: int in range(8, int(pixels.size.y) - 8, 12):
		for x: int in range(10, int(pixels.size.x) - 10, 16):
			draw_rect(Rect2(pixels.position + Vector2(x, y), Vector2(3, 3)), Color("ddb775"))


func _draw_walls() -> void:
	var bounds: Rect2i = _layout.bounds
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var tile := Vector2i(x, y)
			if not _layout.is_wall(tile):
				continue
			var pixels := Rect2(Vector2(tile) * TILE_SIZE, Vector2.ONE * TILE_SIZE)
			draw_rect(pixels, WOOD_DARK)
			draw_rect(pixels.grow(-1), WALL_TOP)
			draw_rect(Rect2(pixels.position + Vector2(2, 2), Vector2(12, 3)), WOOD_LIGHT)
			draw_line(pixels.position + Vector2(2, 12), pixels.position + Vector2(14, 12), WOOD_EDGE, 2.0)
			if posmod(x + y, 2) == 0:
				draw_rect(Rect2(pixels.position + Vector2(6, 7), Vector2(3, 2)), WOOD_EDGE)
	# 门洞三格，与 is_door() 完全一致；门框留在相邻墙格上。
	for direction: int in [-2, 2]:
		var point: Vector2 = Vector2(_layout.door_tile + Vector2i(0, direction)) * TILE_SIZE
		draw_rect(Rect2(point + Vector2(2, 2), Vector2(12, 12)), WOOD_LIGHT)
		draw_rect(Rect2(point + Vector2(5, 5), Vector2(6, 6)), WOOD_EDGE)


func _draw_windows() -> void:
	for tile: Vector2i in _layout.window_tiles:
		var pixels := Rect2(Vector2(tile) * TILE_SIZE + Vector2(2, 2), Vector2(12, 12))
		draw_rect(pixels, WOOD_DARK)
		draw_rect(pixels.grow(-2), Color("89b6b2"))
		draw_rect(Rect2(pixels.position + Vector2(3, 3), Vector2(3, 3)), Color("cce1c4"))
		draw_line(pixels.position + Vector2(6, 1), pixels.position + Vector2(6, 11), CREAM, 2.0)
		draw_line(pixels.position + Vector2(1, 6), pixels.position + Vector2(11, 6), CREAM, 2.0)


func _draw_furniture(item: Dictionary) -> void:
	var footprint: Rect2i = item["rect"]
	var pixels: Rect2 = _pixels(footprint)
	var kind: StringName = item["kind"]
	draw_rect(pixels, WOOD_DARK)
	draw_rect(pixels.grow(-2), WOOD_EDGE)
	match kind:
		&"bed":
			draw_rect(pixels.grow(-4), CREAM)
			draw_rect(Rect2(pixels.position + Vector2(5, 5), Vector2(pixels.size.x - 10, 13)), Color("fff0d0"))
			draw_rect(Rect2(pixels.position + Vector2(4, 23), pixels.size - Vector2(8, 27)), Color("748e87"))
			draw_line(pixels.position + Vector2(5, 25), pixels.position + Vector2(pixels.size.x - 5, 25), Color("afc1a6"), 3.0)
			draw_rect(Rect2(pixels.position + Vector2(1, 1), Vector2(pixels.size.x - 2, 3)), WOOD_LIGHT)
		&"table":
			draw_rect(pixels.grow(-3), Color("bb8653"))
			draw_rect(pixels.grow(-5), Color("d09a60"), false, 1.0)
			var center: Vector2 = pixels.get_center()
			draw_rect(Rect2(center - Vector2(10, 8), Vector2(13, 15)), CREAM)
			draw_line(center - Vector2(6, 3), center + Vector2(0, -3), WOOD_EDGE, 1.0)
			draw_rect(Rect2(center + Vector2(10, -4), Vector2(7, 8)), Color("6b8182"))
			draw_rect(Rect2(center + Vector2(11, -3), Vector2(5, 2)), CREAM)
		&"wardrobe":
			draw_rect(pixels.grow(-3), Color("9a633b"))
			var center_x: float = pixels.get_center().x
			draw_line(Vector2(center_x, pixels.position.y + 4), Vector2(center_x, pixels.end.y - 4), WOOD_DARK, 2.0)
			for direction: int in [-1, 1]:
				draw_rect(Rect2(Vector2(center_x + direction * 4 - 1, pixels.get_center().y), Vector2(2, 4)), Color("e0b45f"))
			draw_rect(Rect2(pixels.position + Vector2(2, 2), Vector2(pixels.size.x - 4, 3)), WOOD_LIGHT)
		&"bookshelf":
			draw_rect(pixels.grow(-3), Color("5b3b2c"))
			var colors: Array[Color] = [Color("a35f46"), Color("6c8b80"), Color("c6aa73"), Color("6e7e9a")]
			for index: int in range(6):
				var point: Vector2 = pixels.position + Vector2(5 + index * 6, 4)
				draw_rect(Rect2(point, Vector2(4, 8)), colors[index % colors.size()])
			draw_line(pixels.position + Vector2(3, 13), pixels.end - Vector2(3, 3), WOOD_LIGHT, 2.0)
		&"chest":
			draw_rect(pixels.grow(-3), Color("b67f45"))
			draw_line(pixels.position + Vector2(3, 12), Vector2(pixels.end.x - 3, pixels.position.y + 12), WOOD_DARK, 2.0)
			for x: int in [6, int(pixels.size.x) - 8]:
				draw_rect(Rect2(pixels.position + Vector2(x, 3), Vector2(3, pixels.size.y - 6)), Color("d4b16d"))
			draw_rect(Rect2(pixels.get_center() - Vector2(2, 3), Vector2(4, 6)), Color("f0d393"))


func _draw_lamps() -> void:
	for tile: Vector2i in _layout.lamp_tiles:
		var center: Vector2 = (Vector2(tile) + Vector2.ONE * 0.5) * TILE_SIZE
		# 低透明度矩形暖光保持像素边缘；灯具放在已有实心墙格上。
		for radius: int in [20, 14, 9]:
			draw_rect(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), Color(1.0, 0.76, 0.38, 0.035))
		draw_rect(Rect2(center - Vector2(3, 4), Vector2(6, 9)), WOOD_DARK)
		draw_rect(Rect2(center - Vector2(2, 3), Vector2(4, 5)), Color("ffe3a0"))
		draw_rect(Rect2(center - Vector2(1, 2), Vector2(2, 3)), Color("fff7d6"))
