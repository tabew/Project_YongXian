class_name MapGenerator
extends RefCounted

## 随机地图生成器：噪声地形 + 岛屿衰减 + 河流 + 平滑 + 出生点选址。
##
## 全部是静态方法，直接调用即可：
##     var map: MapData = MapGenerator.generate(64, 64)

const DEFAULT_WIDTH: int = 64
const DEFAULT_HEIGHT: int = 64


## 生成一张地图；seed_value 传 0 表示本次随机取种。
static func generate(
	width: int = DEFAULT_WIDTH,
	height: int = DEFAULT_HEIGHT,
	seed_value: int = 0
) -> MapData:
	var used_seed: int = seed_value if seed_value != 0 else _random_seed()

	var rng := RandomNumberGenerator.new()
	rng.seed = used_seed

	var map := MapData.new()
	map.width = width
	map.height = height
	map.map_seed = used_seed
	map.map_name = "随机地图 %d" % used_seed
	map.resize_terrain()

	_generate_terrain(map, used_seed)
	_carve_rivers(map, rng)
	_smooth(map, 1)
	_clear_center(map)
	map.spawn_tile = map.find_spawn_tile()

	return map


static func _random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 2147483646)


static func _generate_terrain(map: MapData, seed_value: int) -> void:
	var elevation := FastNoiseLite.new()
	elevation.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elevation.seed = seed_value
	elevation.frequency = 0.014
	elevation.fractal_octaves = 5

	var moisture := FastNoiseLite.new()
	moisture.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture.seed = seed_value + 7919
	moisture.frequency = 0.021
	moisture.fractal_octaves = 3

	for y: int in map.height:
		for x: int in map.width:
			var height_value: float = (elevation.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var moist: float = (moisture.get_noise_2d(float(x), float(y)) + 1.0) * 0.5

			# 越靠边越低，四周自然沉入水里，形成一块完整的大陆
			height_value = clampf(height_value - _island_falloff(x, y, map.width, map.height), 0.0, 1.0)
			map.set_tile(x, y, _classify(height_value, moist))


## 返回 0.0（地图中心）~ 0.6（四角）的边缘衰减量。
static func _island_falloff(x: int, y: int, width: int, height: int) -> float:
	var nx: float = (float(x) / float(maxi(width - 1, 1))) * 2.0 - 1.0
	var ny: float = (float(y) / float(maxi(height - 1, 1))) * 2.0 - 1.0
	var distance: float = clampf(sqrt(nx * nx + ny * ny) / 1.41421356, 0.0, 1.0)
	return smoothstep(0.55, 1.0, distance) * 0.6


static func _classify(height_value: float, moisture: float) -> int:
	if height_value < 0.28:
		return MapData.Terrain.WATER
	if height_value < 0.34:
		return MapData.Terrain.BEACH
	if height_value < 0.63:
		if moisture > 0.55:
			return MapData.Terrain.FOREST
		return MapData.Terrain.GRASS
	if height_value < 0.74:
		if moisture > 0.65:
			return MapData.Terrain.FOREST
		return MapData.Terrain.MOUNTAIN
	return MapData.Terrain.SNOW


static func _carve_rivers(map: MapData, rng: RandomNumberGenerator) -> void:
	var river_count: int = maxi(2, int(sqrt(float(map.width * map.height)) / 42.0))

	for _index: int in river_count:
		if rng.randf() < 0.5:
			_carve_river(
				map,
				Vector2i(0, rng.randi_range(map.height / 6, map.height * 5 / 6)),
				Vector2i(1, 0),
				rng
			)
		else:
			_carve_river(
				map,
				Vector2i(rng.randi_range(map.width / 6, map.width * 5 / 6), 0),
				Vector2i(0, 1),
				rng
			)


static func _carve_river(
	map: MapData,
	start: Vector2i,
	direction: Vector2i,
	rng: RandomNumberGenerator
) -> void:
	var perpendicular := Vector2i(-direction.y, direction.x)
	var cursor: Vector2i = start

	for _step: int in maxi(map.width, map.height):
		if not map.is_valid_coord(cursor.x, cursor.y):
			break

		map.set_tile(cursor.x, cursor.y, MapData.Terrain.WATER)
		if rng.randf() < 0.35:
			var bank: Vector2i = cursor + perpendicular
			map.set_tile(bank.x, bank.y, MapData.Terrain.WATER)

		cursor += direction
		if rng.randf() < 0.30:
			cursor += perpendicular * (1 if rng.randf() < 0.5 else -1)


## 多数投票平滑，去掉噪声产生的孤立单格地形。
static func _smooth(map: MapData, iterations: int) -> void:
	for _iteration: int in iterations:
		var smoothed := PackedByteArray()
		smoothed.resize(map.width * map.height)

		for y: int in map.height:
			for x: int in map.width:
				var counts := PackedInt32Array()
				counts.resize(MapData.TERRAIN_COUNT)
				counts.fill(0)
				counts[map.get_tile(x, y)] += 2

				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						counts[map.get_tile(x + dx, y + dy)] += 1

				var best: int = 0
				for terrain: int in MapData.TERRAIN_COUNT:
					if counts[terrain] > counts[best]:
						best = terrain
				smoothed[y * map.width + x] = best

		map.terrain_tiles = smoothed


## 清出一块平整的出生区，避免主角一出生就被水或山围住。
static func _clear_center(map: MapData) -> void:
	var center := Vector2i(map.width / 2, map.height / 2)
	var radius: int = 5

	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var x: int = center.x + dx
			var y: int = center.y + dy
			if map.is_valid_coord(x, y) and not map.is_walkable(x, y):
				map.set_tile(x, y, MapData.Terrain.GRASS)
