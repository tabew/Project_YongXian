class_name MapData
extends Resource

## 一张随机地图的纯数据表示：只保存地形格子与元信息，不依赖任何渲染节点。
##
## 地形编号同时是地形图集里的行坐标（图集竖排 6 格），可以直接交给 TileMapLayer。

enum Terrain {
	GRASS = 0,     ## 草地，可通行
	WATER = 1,     ## 水域，不可通行
	MOUNTAIN = 2,  ## 山地，不可通行
	FOREST = 3,    ## 森林，可通行
	BEACH = 4,     ## 沙滩，可通行
	SNOW = 5,      ## 雪地，不可通行
}

const TILE_SIZE: int = 16
const TERRAIN_COUNT: int = 6
const TERRAIN_NAMES: Array[String] = ["草地", "水域", "山地", "森林", "沙滩", "雪地"]

@export var map_name: String = "新地图"
@export var map_seed: int = 0
@export var width: int = 64
@export var height: int = 64
@export var spawn_tile: Vector2i = Vector2i(32, 32)

## 逐行存放的地形编号，长度 = width * height。
@export var terrain_tiles: PackedByteArray = PackedByteArray()


## 按当前 width/height 重建地形数组。
func resize_terrain(fill_terrain: int = Terrain.GRASS) -> void:
	terrain_tiles.resize(width * height)
	terrain_tiles.fill(fill_terrain)


func is_valid_coord(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


## 越界一律当作水域，方便平滑与渲染时不用到处判边界。
func get_tile(x: int, y: int) -> int:
	if not is_valid_coord(x, y):
		return Terrain.WATER
	return terrain_tiles[y * width + x]


func set_tile(x: int, y: int, terrain: int) -> void:
	if not is_valid_coord(x, y):
		return
	terrain_tiles[y * width + x] = terrain


## 水面、山地、雪地不可通行。
func is_walkable(x: int, y: int) -> bool:
	if not is_valid_coord(x, y):
		return false
	var terrain: int = terrain_tiles[y * width + x]
	return terrain != Terrain.WATER and terrain != Terrain.MOUNTAIN and terrain != Terrain.SNOW


## 格子中心点的世界坐标。
func terrain_to_world(tile: Vector2i) -> Vector2:
	return Vector2(
		tile.x * TILE_SIZE + TILE_SIZE * 0.5,
		tile.y * TILE_SIZE + TILE_SIZE * 0.5
	)


func world_to_terrain(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))


## 从地图中心向外螺旋搜索最近的可行走格子。
func find_spawn_tile() -> Vector2i:
	var center := Vector2i(width / 2, height / 2)
	if is_walkable(center.x, center.y):
		return center

	for radius: int in range(1, maxi(width, height)):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				if is_walkable(center.x + dx, center.y + dy):
					return Vector2i(center.x + dx, center.y + dy)

	return center


## 各地形数量，索引与 Terrain 对齐。
func count_terrain() -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(TERRAIN_COUNT)
	counts.fill(0)
	for terrain: int in terrain_tiles:
		counts[terrain] += 1
	return counts
