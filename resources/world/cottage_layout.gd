class_name CottageLayout
extends RefCounted

## 小屋只保存区域本地格坐标；地形查询与 Canvas 绘制共用同一份数据。
var bounds: Rect2i = Rect2i()
var spawn_tile: Vector2i = Vector2i.ZERO
var door_tile: Vector2i = Vector2i.ZERO
var porch_tile: Vector2i = Vector2i.ZERO
var furniture: Array[Dictionary] = []
var window_tiles: Array[Vector2i] = []
var lamp_tiles: Array[Vector2i] = []
var rug: Rect2i = Rect2i()
var floor_variant: int = 0


static func create(world_seed: int, node_id: int, variant: int, main_chamber: Rect2) -> CottageLayout:
	var layout := CottageLayout.new()
	# DECOR 流独立派生，零种子也不触发 MapRng 的随机默认种子。
	var source := MapRng.new(1)
	source.master_seed = world_seed
	var salt: int = MapRng.mix(node_id, variant)
	var rng: RandomNumberGenerator = source.rng(MapRng.Stream.DECOR, salt)
	# 采用允许尺寸范围的较大部分：2 倍相机下至少覆盖屏幕中心半幅宽。
	var dimensions := Vector2i(rng.randi_range(20, 24), rng.randi_range(16, 18))
	var anchor: Vector2 = main_chamber.get_center() - Vector2(main_chamber.size.x * 0.08, 0.0)
	var top_left := Vector2i(anchor.floor()) - Vector2i(dimensions.x / 2, dimensions.y / 2)
	layout.bounds = Rect2i(top_left, dimensions)
	layout.spawn_tile = top_left + Vector2i(dimensions.x / 2, dimensions.y / 2)
	layout.door_tile = Vector2i(layout.bounds.end.x - 1, layout.spawn_tile.y)
	layout.porch_tile = layout.door_tile + Vector2i(3, 0)
	layout.floor_variant = rng.randi_range(0, 3)
	layout.rug = Rect2i(layout.spawn_tile - Vector2i(3, 2), Vector2i(7, 5))
	layout.window_tiles = [top_left + Vector2i(dimensions.x / 3, 0), top_left + Vector2i(dimensions.x * 2 / 3, dimensions.y - 1), top_left + Vector2i(0, dimensions.y / 2)]
	layout.lamp_tiles = [top_left + Vector2i(2, 0), top_left + Vector2i(dimensions.x - 3, dimensions.y - 1)]
	layout._place_furniture(rng)
	return layout


func _place_furniture(rng: RandomNumberGenerator) -> void:
	var interior := Rect2i(bounds.position + Vector2i.ONE, bounds.size - Vector2i(2, 2))
	var entries: Array[Dictionary] = [
		{"kind": &"bed", "size": Vector2i(3, 4)},
		{"kind": &"table", "size": Vector2i(4, 2)},
		{"kind": &"wardrobe", "size": Vector2i(2, 3)},
		{"kind": &"bookshelf", "size": Vector2i(3, 1)},
		{"kind": &"chest", "size": Vector2i(2, 2)},
	]
	for entry: Dictionary in entries:
		var dimensions: Vector2i = entry["size"]
		var candidates: Array[Vector2i] = [
			interior.position,
			Vector2i(interior.position.x, interior.end.y - dimensions.y),
			Vector2i(interior.end.x - dimensions.x, interior.position.y),
			interior.end - dimensions,
		]
		var first: int = rng.randi_range(0, candidates.size() - 1)
		var placed: bool = false
		for attempt: int in 64:
			var point: Vector2i
			if attempt < candidates.size():
				point = candidates[(first + attempt) % candidates.size()]
			else:
				point = Vector2i(rng.randi_range(interior.position.x, interior.end.x - dimensions.x), rng.randi_range(interior.position.y, interior.end.y - dimensions.y))
			var footprint := Rect2i(point, dimensions)
			if _can_place(footprint):
				furniture.append({"kind": entry["kind"], "rect": footprint})
				placed = true
				break
		# 穷举兜底保证小尺寸屋也有全部家具，不额外消耗随机流。
		if not placed:
			for y: int in range(interior.position.y, interior.end.y - dimensions.y + 1):
				for x: int in range(interior.position.x, interior.end.x - dimensions.x + 1):
					var footprint := Rect2i(Vector2i(x, y), dimensions)
					if _can_place(footprint):
						furniture.append({"kind": entry["kind"], "rect": footprint})
						placed = true
						break
				if placed:
					break


func _can_place(footprint: Rect2i) -> bool:
	# 出生点周围留出 10×7 的净空，避免家具贴脸。
	var safe_area := Rect2i(spawn_tile - Vector2i(3, 3), Vector2i(10, 7))
	var doorway_path := Rect2i(spawn_tile - Vector2i(0, 2), Vector2i(bounds.end.x - spawn_tile.x, 5))
	if footprint.intersects(safe_area) or footprint.intersects(doorway_path):
		return false
	for item: Dictionary in furniture:
		var occupied: Rect2i = item["rect"]
		if footprint.intersects(occupied):
			return false
	return true


func is_door(local_tile: Vector2i) -> bool:
	return local_tile.x == door_tile.x and absi(local_tile.y - door_tile.y) <= 1


func is_wall(local_tile: Vector2i) -> bool:
	if not bounds.has_point(local_tile) or is_door(local_tile):
		return false
	return local_tile.x == bounds.position.x or local_tile.x == bounds.end.x - 1 or local_tile.y == bounds.position.y or local_tile.y == bounds.end.y - 1


func terrain_at(local_tile: Vector2i) -> int:
	if not bounds.has_point(local_tile):
		return -1
	if is_wall(local_tile):
		return Terrain.Kind.MOUNTAIN
	for item: Dictionary in furniture:
		var footprint: Rect2i = item["rect"]
		if footprint.has_point(local_tile):
			return Terrain.Kind.MOUNTAIN
	return Terrain.Kind.STONE


func label_at(local_tile: Vector2i) -> String:
	if not bounds.has_point(local_tile):
		return ""
	if is_wall(local_tile):
		return "木墙"
	for item: Dictionary in furniture:
		var footprint: Rect2i = item["rect"]
		if footprint.has_point(local_tile):
			return "家具"
	return "木地板"
