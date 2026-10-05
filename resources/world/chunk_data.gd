class_name ChunkData
extends RefCounted

## 一个区块的地形与路网数据。
##
## 只保存字节数组，不含任何节点，所以可以安全地在工作线程里生成、
## 也可以长期缓存（32x32 的区块各占 3 KB）。

var coords: Vector2i = Vector2i.ZERO
var size: int = 0
var terrain: PackedByteArray = PackedByteArray()
var biome: PackedByteArray = PackedByteArray()
var route: PackedByteArray = PackedByteArray()

## 生成这份数据时的世界世代号，用于丢弃换种子后残留的异步结果。
var epoch: int = 0

## 最后一次被访问的毫秒时间戳，供 LRU 淘汰使用。
var last_used: int = 0


static func create(chunk_coords: Vector2i, chunk_size: int) -> ChunkData:
	var data := ChunkData.new()
	data.coords = chunk_coords
	data.size = chunk_size
	data.terrain.resize(chunk_size * chunk_size)
	data.biome.resize(chunk_size * chunk_size)
	data.route.resize(chunk_size * chunk_size)
	return data


func get_terrain(local_x: int, local_y: int) -> int:
	return terrain[local_y * size + local_x]


func get_biome(local_x: int, local_y: int) -> int:
	return biome[local_y * size + local_x]


func get_route(local_x: int, local_y: int) -> int:
	return route[local_y * size + local_x]
