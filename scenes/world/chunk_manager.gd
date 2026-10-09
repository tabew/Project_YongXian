class_name ChunkManager
extends Node2D

## 区块加载器：把无限世界切成固定大小的区块按需生成与卸载。
##
## 性能设计要点：
##  1. 地形生成只依赖 (种子, 坐标)，因此每个区块可以独立生成，不需要邻居数据，也就没有接缝。
##  2. 数据生成丢到 WorkerThreadPool，主线程只负责把结果铺进 TileMapLayer。
##  3. 铺格子和提交生成都有"每帧上限"，避免一次性卡顿。
##  4. 区块数据做 LRU 缓存，走回头路时直接命中缓存，不再算噪声。
##  5. 每个区块一个 TileMapLayer，格子坐标只用 0..CHUNK_SIZE-1，节点位置承担世界偏移。
##     这样图层内部的四叉树始终很小，坐标不会随玩家走远而膨胀。
##  6. TileMapLayer 节点池化复用，卸载区块不销毁节点。

signal chunk_applied(coords: Vector2i)

@export var tile_set: TileSet

@export_group("加载范围")
## 以玩家所在区块为中心要显示的范围（单位：区块）。
@export var load_radius: int = 2
## 超过这个范围才卸载；比 load_radius 大是为了留迟滞，免得在边界来回抖动。
@export var unload_radius: int = 3

@export_group("每帧预算")
## 每帧最多提交几个区块去生成。
@export var generations_per_frame: int = 4
## 每帧最多把几个区块铺进 TileMapLayer（主线程开销的大头）。
@export var applications_per_frame: int = 2
## 每帧最多回收几个区块；瞬移时几十个区块同时过期，不摊开就会卡一下。
@export var unloads_per_frame: int = 4

@export_group("缓存")
## 区块数据缓存上限（每块 2 KB）。
@export var cache_limit: int = 512

@export_group("调试")
## 关掉则全部在主线程生成，方便对比。
@export var use_worker_threads: bool = true

const MAX_GENERATOR_POOL: int = 16
const MAX_LAYER_POOL: int = 64
## TileSet 里地形图集 / 路网图集所在的 source id。
const TERRAIN_SOURCE_ID: int = 0
const ROAD_SOURCE_ID: int = 1
## 两张图集都是竖排的，列固定 0，行才是编号。
const TILE_ATLAS_COLUMN: int = 0
const NO_CHUNK: Vector2i = Vector2i(2147483647, 2147483647)

var focus_node: Node2D = null

## 每次区块铺好或回收就 +1。小地图等表现层靠它判断"数据有没有变"，
## 不变就不必重画，站着不动时一次重建都不会发生。
var version: int = 0

var _generator: WorldGenerator = null
var _world_seed: int = 0
var _epoch: int = 0
var _focus_chunk: Vector2i = NO_CHUNK

var _layers: Dictionary = {}
var _cache: Dictionary = {}
var _queue: Array[Vector2i] = []
var _unload_queue: Array[Vector2i] = []
var _in_flight: Dictionary = {}
var _apply_queue: Array[ChunkData] = []
var _completed: Array[ChunkData] = []

var _layer_pool: Array[TileMapLayer] = []
var _generator_pool: Array[WorldGenerator] = []

var _result_mutex := Mutex.new()
var _generator_mutex := Mutex.new()

var stat_generated: int = 0
var stat_cache_hits: int = 0
var stat_applied: int = 0
var stat_generate_usec: int = 0
var stat_apply_usec: int = 0
var stat_last_generate_usec: int = 0


func _exit_tree() -> void:
	# 工作线程还在跑的时候释放本节点会踩到已回收的对象，必须等它们结束
	_wait_for_generation_tasks()
	_clear_scene()


# ------------------------------------------------------------ 对外接口

## 换一个世界（新种子）或首次进入时调用。
func setup(generator: WorldGenerator, focus: Node2D) -> void:
	# 旧任务必须先结束，否则相同坐标会被 _in_flight 跳过，旧种子的生成器也可能被复用。
	_epoch += 1
	_wait_for_generation_tasks()
	_generator_pool.clear()
	_clear_scene()

	_generator = generator
	_world_seed = generator.world_seed
	focus_node = focus
	_focus_chunk = NO_CHUNK
	_reset_stats()


func get_stats() -> Dictionary:
	var generate_avg: float = 0.0
	if stat_generated > 0:
		generate_avg = float(stat_generate_usec) / float(stat_generated) / 1000.0

	var apply_avg: float = 0.0
	if stat_applied > 0:
		apply_avg = float(stat_apply_usec) / float(stat_applied) / 1000.0

	return {
		"loaded": _layers.size(),
		"cached": _cache.size(),
		"queued": _queue.size(),
		"in_flight": _in_flight.size(),
		"generated": stat_generated,
		"applied": stat_applied,
		"cache_hits": stat_cache_hits,
		"generate_avg_ms": generate_avg,
		"generate_last_ms": float(stat_last_generate_usec) / 1000.0,
		"apply_avg_ms": apply_avg,
		"focus_chunk": _focus_chunk,
	}


## 即时查询某个世界坐标的地形；不走区块缓存，直接算，结果与铺出来的完全一致。
func get_terrain_at(world_position: Vector2) -> int:
	if _generator == null:
		return Terrain.Kind.WATER
	return _generator.sample_terrain(WorldGenerator.world_to_tile(world_position))


func get_biome_at(world_position: Vector2) -> int:
	if _generator == null:
		return Biome.Kind.OCEAN
	return _generator.sample_biome(WorldGenerator.world_to_tile(world_position))


func get_route_at(world_position: Vector2) -> int:
	if _generator == null:
		return Route.Kind.NONE
	return _generator.sample_route(WorldGenerator.world_to_tile(world_position))


## 当前已经铺出来的区块坐标，供调试或小地图使用。
func loaded_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coords: Vector2i in _layers.keys():
		result.append(coords)
	return result


## 取区块数据（含已卸载但仍在缓存里的）。小地图直接读这个，不重跑噪声。
func get_cached_chunk(coords: Vector2i) -> ChunkData:
	return _cache.get(coords)


# ------------------------------------------------------------ 主循环

func _process(_delta: float) -> void:
	if _generator == null or focus_node == null:
		return

	var focus_chunk: Vector2i = WorldGenerator.tile_to_chunk(
		WorldGenerator.world_to_tile(focus_node.global_position)
	)
	if focus_chunk != _focus_chunk:
		_focus_chunk = focus_chunk
		_rebuild_queue()
		_scan_for_unload()

	_reap_tasks()
	_drain_results()
	_dispatch()
	_unload_due()
	_apply_results()


func _rebuild_queue() -> void:
	_queue.clear()
	for dy: int in range(-load_radius, load_radius + 1):
		for dx: int in range(-load_radius, load_radius + 1):
			var coords: Vector2i = _focus_chunk + Vector2i(dx, dy)
			if _layers.has(coords) or _in_flight.has(coords):
				continue
			_queue.append(coords)
	_sort_queue()


## 近的区块先处理。
func _sort_queue() -> void:
	var center: Vector2i = _focus_chunk
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ax: int = a.x - center.x
		var ay: int = a.y - center.y
		var bx: int = b.x - center.x
		var by: int = b.y - center.y
		var da: int = ax * ax + ay * ay
		var db: int = bx * bx + by * by
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)


## 只在玩家换区块时扫一遍，把过期的区块排进待回收队列。
func _scan_for_unload() -> void:
	if _layers.is_empty():
		return
	var limit: int = unload_radius * unload_radius
	for coords: Vector2i in _layers.keys():
		if _unload_queue.has(coords):
			continue
		var dx: int = coords.x - _focus_chunk.x
		var dy: int = coords.y - _focus_chunk.y
		if dx * dx + dy * dy > limit:
			_unload_queue.append(coords)


## 每帧按预算回收，避免一次释放几十个图层造成掉帧。
func _unload_due() -> void:
	var budget: int = unloads_per_frame
	while budget > 0 and not _unload_queue.is_empty():
		var coords: Vector2i = _unload_queue.pop_front()
		if _layers.has(coords):
			_recycle_layer(coords)
			budget -= 1


## 收掉已经跑完的线程任务，把任务槽释放回作业池。
func _reap_tasks() -> void:
	if _in_flight.is_empty():
		return
	var finished: Array[Vector2i] = []
	for coords: Vector2i in _in_flight.keys():
		var task_id: int = _in_flight[coords]
		if WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
			finished.append(coords)
	for coords: Vector2i in finished:
		_in_flight.erase(coords)


func _drain_results() -> void:
	_result_mutex.lock()
	var incoming: Array[ChunkData] = _completed.duplicate()
	_completed.clear()
	_result_mutex.unlock()

	for data: ChunkData in incoming:
		if data.epoch != _epoch:
			continue
		_apply_queue.append(data)


func _dispatch() -> void:
	var dispatched: int = 0
	while dispatched < generations_per_frame and not _queue.is_empty():
		var coords: Vector2i = _queue[0]
		_queue.remove_at(0)
		if _layers.has(coords) or _in_flight.has(coords):
			continue

		var cached: ChunkData = _cache.get(coords)
		if cached != null:
			cached.last_used = Time.get_ticks_msec()
			stat_cache_hits += 1
			_apply_queue.append(cached)
			dispatched += 1
			continue

		if use_worker_threads:
			_submit_task(coords)
		else:
			_generate_inline(coords)
		dispatched += 1


func _apply_results() -> void:
	if _apply_queue.is_empty():
		return

	var center: Vector2i = _focus_chunk
	_apply_queue.sort_custom(func(a: ChunkData, b: ChunkData) -> bool:
		var ax: int = a.coords.x - center.x
		var ay: int = a.coords.y - center.y
		var bx: int = b.coords.x - center.x
		var by: int = b.coords.y - center.y
		return ax * ax + ay * ay < bx * bx + by * by
	)

	var limit: int = unload_radius * unload_radius
	var applied: int = 0
	var started: int = Time.get_ticks_usec()

	while applied < applications_per_frame and not _apply_queue.is_empty():
		var data: ChunkData = _apply_queue.pop_front()

		# 玩家在生成期间跑远了：不铺，但留进缓存，回来时不用重算
		var dx: int = data.coords.x - center.x
		var dy: int = data.coords.y - center.y
		if dx * dx + dy * dy > limit:
			_store_cache(data)
			continue

		_paint_chunk(data)
		applied += 1

	stat_apply_usec += Time.get_ticks_usec() - started


# ------------------------------------------------------------ 线程侧

func _submit_task(coords: Vector2i) -> void:
	var task_epoch: int = _epoch
	var task_id: int = WorkerThreadPool.add_task(
		_generate_task.bind(coords, task_epoch),
		true,
		"chunk %d,%d" % [coords.x, coords.y]
	)
	_in_flight[coords] = task_id


## 在工作线程里执行：只碰 RefCounted 数据和互斥锁，绝不碰场景树。
func _generate_task(coords: Vector2i, task_epoch: int) -> void:
	var worker: WorldGenerator = _acquire_generator()
	var started: int = Time.get_ticks_usec()
	var data: ChunkData = worker.generate_chunk(coords, task_epoch)
	var elapsed: int = Time.get_ticks_usec() - started
	_release_generator(worker)

	_result_mutex.lock()
	_completed.append(data)
	stat_generated += 1
	stat_generate_usec += elapsed
	stat_last_generate_usec = elapsed
	_result_mutex.unlock()


func _generate_inline(coords: Vector2i) -> void:
	var started: int = Time.get_ticks_usec()
	var data: ChunkData = _generator.generate_chunk(coords, _epoch)
	var elapsed: int = Time.get_ticks_usec() - started

	stat_generated += 1
	stat_generate_usec += elapsed
	stat_last_generate_usec = elapsed
	_apply_queue.append(data)


# 每个工作线程各拿一个生成器实例，避免多个线程共用同一套噪声对象
func _acquire_generator() -> WorldGenerator:
	_generator_mutex.lock()
	var worker: WorldGenerator = null
	if not _generator_pool.is_empty():
		worker = _generator_pool.pop_back()
	_generator_mutex.unlock()

	if worker != null:
		return worker
	return WorldGenerator.new(_world_seed)


func _release_generator(worker: WorldGenerator) -> void:
	_generator_mutex.lock()
	if _generator_pool.size() < MAX_GENERATOR_POOL:
		_generator_pool.append(worker)
	_generator_mutex.unlock()


## 等待当前世代的生成任务结束，供换世界和退出场景时统一收尾。
func _wait_for_generation_tasks() -> void:
	for coords: Vector2i in _in_flight.keys():
		var task_id: int = _in_flight[coords]
		WorkerThreadPool.wait_for_task_completion(task_id)
	_in_flight.clear()


# ------------------------------------------------------------ 铺图与回收

func _paint_chunk(data: ChunkData) -> void:
	var layer: TileMapLayer = _take_layer()
	# 节点位置承担世界偏移，格子坐标只用 0..CHUNK_SIZE-1
	layer.position = Vector2(
		data.coords.x * WorldGenerator.CHUNK_SIZE * WorldGenerator.TILE_SIZE,
		data.coords.y * WorldGenerator.CHUNK_SIZE * WorldGenerator.TILE_SIZE
	)

	var index: int = 0
	for local_y: int in WorldGenerator.CHUNK_SIZE:
		for local_x: int in WorldGenerator.CHUNK_SIZE:
			var cell := Vector2i(local_x, local_y)
			var road: int = data.route[index]
			if road == Route.Kind.NONE:
				layer.set_cell(
					cell,
					TERRAIN_SOURCE_ID,
					Vector2i(TILE_ATLAS_COLUMN, data.terrain[index])
				)
			else:
				# 路直接替换这一格的贴图；地形数据仍然原样保留，
				# 所以生物群系和碰撞判定都不受影响
				layer.set_cell(
					cell,
					ROAD_SOURCE_ID,
					Vector2i(TILE_ATLAS_COLUMN, Route.atlas_row(road))
				)
			index += 1

	add_child(layer)
	_layers[data.coords] = layer

	data.last_used = Time.get_ticks_msec()
	_store_cache(data)
	stat_applied += 1
	version += 1
	chunk_applied.emit(data.coords)


func _take_layer() -> TileMapLayer:
	if not _layer_pool.is_empty():
		return _layer_pool.pop_back()

	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	layer.rendering_quadrant_size = WorldGenerator.CHUNK_SIZE
	return layer


func _recycle_layer(coords: Vector2i) -> void:
	var layer: TileMapLayer = _layers.get(coords)
	if layer == null:
		return
	_layers.erase(coords)
	version += 1

	remove_child(layer)
	# 故意不清空：复用时 _paint_chunk 会把 32x32 全部重写一遍，不会留下旧格子
	if _layer_pool.size() < MAX_LAYER_POOL:
		_layer_pool.append(layer)
	else:
		layer.queue_free()


func _store_cache(data: ChunkData) -> void:
	_cache[data.coords] = data
	if _cache.size() <= cache_limit:
		return

	# LRU：淘汰最久没被碰过的那一块
	var oldest_coords: Vector2i = NO_CHUNK
	var oldest_time: int = 2147483647
	for coords: Vector2i in _cache.keys():
		var entry: ChunkData = _cache[coords]
		if entry.last_used < oldest_time:
			oldest_time = entry.last_used
			oldest_coords = coords
	if oldest_coords != NO_CHUNK:
		_cache.erase(oldest_coords)


# ------------------------------------------------------------ 清理

func _clear_scene() -> void:
	for coords: Vector2i in _layers.keys():
		var layer: TileMapLayer = _layers[coords]
		if is_instance_valid(layer):
			remove_child(layer)
			layer.queue_free()
	_layers.clear()

	for layer: TileMapLayer in _layer_pool:
		if is_instance_valid(layer):
			layer.queue_free()
	_layer_pool.clear()

	_result_mutex.lock()
	_completed.clear()
	_result_mutex.unlock()

	_cache.clear()
	_queue.clear()
	_unload_queue.clear()
	_apply_queue.clear()
	version += 1


func _reset_stats() -> void:
	stat_generated = 0
	stat_cache_hits = 0
	stat_applied = 0
	stat_generate_usec = 0
	stat_apply_usec = 0
	stat_last_generate_usec = 0
