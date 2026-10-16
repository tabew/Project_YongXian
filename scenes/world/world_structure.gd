class_name WorldStructure
extends Node2D

## 像素布景直接绘制；实心格与 WorldPopulation 的地形覆盖一一对应。
var kind: StringName = &"camp"
var variant: int = 0
var biome_id: int = Biome.Kind.FOREST
const DARK := Color("3b3533")
const STONE := Color("8d9383")
const LIGHT := Color("c7c5a2")
const WOOD := Color("966143")


func _draw() -> void:
	# 不规则的碎石/泥土底座让兴趣点自然融入原地面。
	var ground := Color("7c7054", 0.45)
	if biome_id in [Biome.Kind.SNOWY_PLAINS, Biome.Kind.ALPINE, Biome.Kind.TUNDRA]:
		ground = Color("b5bdb6", 0.42)
	for row: int in range(-3, 4):
		var inset: int = absi(row) * 4
		draw_rect(Rect2(-65 + inset, row * 16 - 6, 130 - inset * 2, 15), ground)
	match kind:
		&"camp":
			_draw_camp()
		&"ruins":
			_draw_ruins()
		&"stone_circle":
			_draw_circle()
		&"supplies":
			_draw_supplies()
		&"garden":
			_draw_garden()
	for index: int in 14:
		var point := Vector2(posmod(index * 37 + variant * 11, 122) - 61, posmod(index * 23, 88) - 44)
		draw_rect(Rect2(point, Vector2(3, 2)), Color("d4c9a0", 0.4))


func _draw_camp() -> void:
	var canvas: Color = [Color("b87542"), Color("6f8c79"), Color("a49363")][variant]
	# 帐篷覆盖本地 (-3,-2) 到 (-1,-1) 六格。
	draw_rect(Rect2(-58, -31, 50, 29), DARK)
	draw_colored_polygon(PackedVector2Array([Vector2(-58, -4), Vector2(-37, -36), Vector2(-10, -4)]), canvas.darkened(0.18))
	draw_colored_polygon(PackedVector2Array([Vector2(-37, -36), Vector2(-14, -36), Vector2(2, -4), Vector2(-10, -4)]), canvas)
	draw_colored_polygon(PackedVector2Array([Vector2(-45, -5), Vector2(-36, -23), Vector2(-27, -5)]), DARK)
	draw_line(Vector2(-37, -36), Vector2(-10, -4), LIGHT, 2)
	draw_line(Vector2(-58, -3), Vector2(2, -3), WOOD, 3)
	for point: Vector2 in [Vector2(20, 8), Vector2(36, 8), Vector2(16, 20), Vector2(40, 20), Vector2(28, 27)]:
		_stone(point, Vector2(7, 5))
	draw_line(Vector2(21, 14), Vector2(35, 22), WOOD.darkened(0.3), 4)
	draw_line(Vector2(21, 22), Vector2(35, 14), WOOD, 4)
	draw_colored_polygon(PackedVector2Array([Vector2(23, 17), Vector2(25, 1), Vector2(31, 10), Vector2(34, 17)]), Color("e79840"))
	draw_rect(Rect2(27, 10, 3, 7), Color("ffe4a0"))
	draw_rect(Rect2(-38, 22, 32, 10), Color("637968"))
	draw_rect(Rect2(-36, 23, 8, 8), Color("d7ceb0"))


func _draw_ruins() -> void:
	for y: int in range(-2, 3):
		for x: int in range(-3, 4):
			if posmod(x * 3 + y * 7 + variant, 6) == 0:
				continue
			var rect := Rect2(x * 16 - 7, y * 16 - 7, 14, 14)
			draw_rect(rect, Color("747c72"))
			draw_rect(rect.grow(-2), Color("969c87"))
			draw_line(rect.position + Vector2(3, 2), rect.position + Vector2(8, 8), Color("586357"), 1)
	for point: Vector2 in [Vector2(-48, -32), Vector2(48, -32), Vector2(-48, 32), Vector2(48, 32)]:
		draw_rect(Rect2(point - Vector2(8, 8), Vector2(16, 16)), DARK)
		draw_rect(Rect2(point - Vector2(6, 15), Vector2(12, 20)), STONE)
		draw_rect(Rect2(point - Vector2(8, 19), Vector2(16, 6)), LIGHT)
		draw_line(point - Vector2(3, 12), point - Vector2(3, 1), Color("657565"), 2)
	_stone(Vector2(18, -9), Vector2(9, 4))


func _draw_circle() -> void:
	for point: Vector2 in [Vector2(-32, -32), Vector2(32, -32), Vector2(-32, 32), Vector2(32, 32)]:
		_stone(point, Vector2(16, 16))
		draw_rect(Rect2(point - Vector2(6, 11), Vector2(12, 14)), STONE)
		draw_line(point - Vector2(3, 8), point + Vector2(2, -3), Color("b8cfb0"), 2)
	for point: Vector2 in [Vector2(0, -36), Vector2(0, 36), Vector2(-38, 0), Vector2(38, 0)]:
		_stone(point, Vector2(8, 5))
	draw_rect(Rect2(-12, -12, 24, 24), Color("686f62"), false, 2)
	draw_line(Vector2(-8, 0), Vector2(8, 0), Color("b9c49c"), 2)
	draw_line(Vector2(0, -8), Vector2(0, 8), Color("b9c49c"), 2)


func _draw_supplies() -> void:
	for y: int in range(-2, 3):
		draw_rect(Rect2(-51, y * 13, 100, 10), WOOD.darkened(0.25))
	_crate(Vector2(-32, -16))
	_crate(Vector2(-16, -16))
	_crate(Vector2(32, 16))
	draw_rect(Rect2(9, -28, 33, 19), Color("747d68"))
	draw_rect(Rect2(10, -27, 31, 4), Color("9fa58b"))
	draw_rect(Rect2(15, -25, 3, 15), Color("b6aa7e"))
	draw_rect(Rect2(33, -25, 3, 15), Color("b6aa7e"))


func _draw_garden() -> void:
	for row: int in range(-1, 2):
		draw_rect(Rect2(-49, row * 26 - 9, 98, 19), Color("544633"))
		draw_rect(Rect2(-47, row * 26 - 7, 94, 15), Color("796048"))
		for column: int in range(-2, 3):
			var point := Vector2(column * 19, row * 26)
			draw_line(point + Vector2(0, 4), point - Vector2(0, 6), Color("4c6e45"), 2)
			draw_rect(Rect2(point - Vector2(6, 2), Vector2(5, 3)), Color("83a659"))
			draw_rect(Rect2(point + Vector2(1, -5), Vector2(5, 3)), Color("9db26b"))
			if posmod(column + row + variant, 3) == 0:
				draw_rect(Rect2(point - Vector2(2, 8), Vector2(4, 4)), Color("d8c893"))


func _stone(point: Vector2, size: Vector2) -> void:
	draw_rect(Rect2(point - size * 0.5 + Vector2(1, 3), size), Color("333a32", 0.4))
	draw_rect(Rect2(point - size * 0.5, size), DARK)
	draw_rect(Rect2(point - size * 0.5, size).grow(-2), STONE)
	draw_rect(Rect2(point - size * 0.5 + Vector2(2, 1), Vector2(size.x - 4, 2)), LIGHT)


func _crate(point: Vector2) -> void:
	draw_rect(Rect2(point - Vector2(8, 8), Vector2(16, 16)), DARK)
	draw_rect(Rect2(point - Vector2(7, 9), Vector2(14, 14)), WOOD)
	draw_rect(Rect2(point - Vector2(6, 8), Vector2(12, 2)), LIGHT)
	draw_line(point - Vector2(5, 5), point + Vector2(5, 3), Color("c28a59"), 2)
	draw_line(point + Vector2(5, -5), point + Vector2(-5, 3), Color("c28a59"), 2)
