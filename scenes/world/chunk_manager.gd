class_name ChunkManager
extends Node2D

## 箱庭区块加载器：每张地图拥有独立 root 和裁剪到矩形边界的图层。
## 只显示当前地图，直连邻图先生成缓存、过场再铺到达视口；区块数据按世界坐标共享同种子缓存。
## 首次进入同步铺好相机视口，其余当前地图的铺图按每帧预算分摊。
## 每个区块一个 TileMapLayer，本地格子坐标和节点偏移保持图层四叉树较小。

signal chunk_applied(coords: Vector2i)

@export var tile_set: TileSet

## 保留旧组件查询接口；箱庭加载范围实际由完整地图矩形决定。
var load_radius: int = 2
var unload_radius: int = 3
var unloads_per_frame: int = 4
const NO_CHUNK: Vector2i = Vector2i(2147483647, 2147483647)

@export_group("每帧预算")
## 每帧最多提交几个区块去生成。
@export var generations_per_frame: int = 4
## 每帧最多把几个区块铺进 TileMapLayer（主线程开销的大头）。
@export var applications_per_frame: int = 4

@export_group("缓存")
## 区块数据缓存上限（每块 3 KB）。跨地图也保留，回头再进同一张图就能直接命中。
@export var cache_limit: int = 512

@export_group("调试")
## 关掉则全部在主线程生成，方便对比。
@export var use_worker_threads: bool = true

## 兼容旧测试的常量；加载范围现在由地图完整矩形决定。
const RENDER_RADIUS: int = 3
const RETAIN_RADIUS: int = 4
const MAX_GENERATOR_POOL: int = 16
const MAX_LAYER_POOL: int = 512
const APPLY_BUDGET_USEC: int = 2500
const TERRAIN_SOURCE_ID: int = 0
const ROAD_SOURCE_ID: int = 1
const TILE_ATLAS_COLUMN: int = 0

var focus_node: Node2D = null

## 世界重建、当前地图变化或已加载区块变化时递增，供小地图判断是否刷新。
var version: int = 0

var _generator: WorldGenerator = null
var _world_seed: int = 0
## 工作线程必须沿用主生成器的布局变体与配置，否则会生成另一张地图。
var _variant: int = 0
var _config: MapConfig = null
var _epoch: int = 0
var _spec: MapSpec = null
var _focus_chunk: Vector2i = Vector2i.ZERO
var _prewarm_map_id: int = -1
var _prewarm_chunks: Dictionary = {}

## _layers 始终引用当前地图的 dictionary，供小地图和测试读取。
var _layers: Dictionary = {}
## node_id -> {root, spec, layers, chunks}；chunks 覆盖该地图完整矩形。
var _regions: Dictionary = {}
var _desired: Dictionary = {}
var _cache: Dictionary = {}
var _queue: Array[Vector2i] = []
var _in_flight: Dictionary = {}
## 每项包含 map_id 和 data；共享区块会分别裁剪铺入多个地图。
var _apply_queue: Array[Dictionary] = []
var _pending: Dictionary = {}
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
	_wait_for_tasks()
	_free_all_layers()


# ------------------------------------------------------------ 对外接口

## 重建世界：旧任务结束前不能替换种子或生成器，也不能清空生成器池。
func setup(generator: WorldGenerator, focus: Node2D) -> void:
	_wait_for_tasks()
	TerrainTransitions.install(tile_set)
	_epoch += 1
	_free_all_layers()
	_cache.clear()
	_queue.clear()
	_generator_mutex.lock()
	_generator_pool.clear()
	_generator_mutex.unlock()
	_generator = generator
	_world_seed = generator.world_seed
	_variant = generator.variant
	_config = generator.config
	focus_node = focus
	_spec = null
	_focus_chunk = Vector2i.ZERO
	_prewarm_map_id = -1
	_prewarm_chunks.clear()
	_reset_stats()
	version += 1


## 切换可见地图，不更换 epoch；旧任务仍可为同一种子的缓存提供数据。
func load_map(map_node_id: int) -> void:
	if _generator == null:
		return
	var next_spec: MapSpec = _generator.map_spec(map_node_id)
	if next_spec == null:
		return
	_spec = next_spec
	_desired.clear()
	_desired[map_node_id] = true
	# gate_links 包含入口与出口，先生成直连邻图的数据，过场再铺入口视口。
	for link: Dictionary in _generator.gate_links(map_node_id):
		var target: int = int(link["target"])
		if _generator.map_spec(target) != null:
			_desired[target] = true
	for id: int in _regions.keys():
		if not _desired.has(id):
			_release_region(id)
	for id: int in _desired.keys():
		if not _regions.has(id):
			_create_region(_generator.map_spec(id))
		var root: Node2D = _regions[id]["root"]
		root.visible = id == map_node_id
	_layers = _regions[map_node_id]["layers"]
	_reap_tasks()
	_drain_results()
	prepare_visible()
	_prewarm_map_id = -1
	_prewarm_chunks.clear()
	_rebuild_queue()
	version += 1


## 过场时先生成并铺好目标入口的视口，避免把缺块留给切图当帧。
func prewarm_arrival(map_node_id: int, at: Vector2) -> void:
	if not _desired.has(map_node_id) or not _regions.has(map_node_id) or map_node_id == _spec.node_id:
		return
	_prewarm_map_id = map_node_id
	_prewarm_chunks.clear()
	var center: Vector2i = WorldGenerator.tile_to_chunk(WorldGenerator.world_to_tile(at))
	var chunks: Array[Vector2i] = _regions[map_node_id]["chunks"]
	var layers: Dictionary = _regions[map_node_id]["layers"]
	var queued: Array[Vector2i] = []
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			var coords: Vector2i = center + Vector2i(x, y)
			if not chunks.has(coords):
				continue
			_prewarm_chunks[coords] = true
			if layers.has(coords):
				continue
			var data: ChunkData = _available_chunk(coords)
			if data != null:
				_enqueue_application(map_node_id, data)
			elif not _in_flight.has(coords) and _queue.has(coords):
				_queue.erase(coords)
				queued.append(coords)
	queued.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() > (b - center).length_squared()
	)
	for coords: Vector2i in queued:
		_queue.push_front(coords)


## 同步补齐当前相机视口。若该坐标已在线程中生成，等待它而不重复生成。
func prepare_visible() -> void:
	if _spec == null or focus_node == null or not _regions.has(_spec.node_id):
		return
	var viewport: Viewport = focus_node.get_viewport()
	var camera: Camera2D = viewport.get_camera_2d()
	var half_view: Vector2 = viewport.get_visible_rect().size * 0.5
	var center: Vector2 = focus_node.global_position
	if camera != null:
		half_view /= camera.zoom.abs().max(Vector2.ONE * 0.001)
		# 使用传送后的焦点位置，避免切换当帧 Camera2D 的上一帧屏幕中心。
		center += camera.offset
	var bounds := Rect2(Vector2(_spec.origin) * WorldGenerator.TILE_SIZE,
		Vector2(_spec.extent) * WorldGenerator.TILE_SIZE)
	var low: Vector2 = bounds.position + half_view
	var high: Vector2 = bounds.end - half_view
	center.x = clampf(center.x, low.x, high.x) if low.x <= high.x else bounds.get_center().x
	center.y = clampf(center.y, low.y, high.y) if low.y <= high.y else bounds.get_center().y
	# 额外一格覆盖边缘 tile 和相机的像素取整。
	var visible: Rect2 = Rect2(center - half_view, half_view * 2.0).grow(WorldGenerator.TILE_SIZE).intersection(bounds)
	if not visible.has_area():
		return
	var first: Vector2i = WorldGenerator.tile_to_chunk(WorldGenerator.world_to_tile(visible.position))
	var last: Vector2i = WorldGenerator.tile_to_chunk(WorldGenerator.world_to_tile(visible.end - Vector2.ONE * 0.001))
	var started: int = Time.get_ticks_usec()
	for cy: int in range(first.y, last.y + 1):
		for cx: int in range(first.x, last.x + 1):
			var coords := Vector2i(cx, cy)
			if _layers.has(coords):
				continue
			var data: ChunkData = _available_chunk(coords)
			if data != null:
				stat_cache_hits += 1
			elif _in_flight.has(coords):
				WorkerThreadPool.wait_for_task_completion(_in_flight[coords])
				_in_flight.erase(coords)
				# 保留直接结果，即使极小的 LRU 限额立即淘汰了这一块。
				var incoming: Dictionary = _drain_results()
				data = incoming.get(coords, _cache.get(coords))
			if data == null:
				data = _generate_inline(coords)
			_paint_chunk(data, _spec.node_id)
	stat_apply_usec += Time.get_ticks_usec() - started


func get_generator() -> WorldGenerator:
	return _generator


func get_map_spec() -> MapSpec:
	return _spec


## 当前地图在整局里的描述，例如"第 3 层（岔路）"。
func describe_map() -> String:
	if _generator == null or _spec == null:
		return "—"
	return _generator.run.describe(_spec.node_id)


func map_ready() -> bool:
	if _spec == null or not _regions.has(_spec.node_id):
		return false
	var chunks: Array[Vector2i] = _regions[_spec.node_id]["chunks"]
	return _layers.size() == chunks.size()


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
		return Terrain.Kind.DEEP_WATER
	return _generator.sample_terrain(WorldGenerator.world_to_tile(world_position))


func get_biome_at(world_position: Vector2) -> int:
	if _generator == null:
		return Biome.Kind.DEEP_OCEAN
	return _generator.sample_biome(WorldGenerator.world_to_tile(world_position))


func get_route_at(world_position: Vector2) -> int:
	if _generator == null:
		return Route.Kind.NONE
	return _generator.sample_route(WorldGenerator.world_to_tile(world_position))


## 这个位置踩没踩到路口：-1 没有，0 西侧入口，1 起是东侧第 n 个出口。
func get_gate_at(world_position: Vector2) -> int:
	if _generator == null:
		return -1
	return _generator.sample_gate(WorldGenerator.world_to_tile(world_position))


## 取区块数据（含已卸载但仍在缓存里的）。小地图直接读这个，不重跑噪声。
func get_cached_chunk(coords: Vector2i) -> ChunkData:
	return _cache.get(coords)


func loaded_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coords: Vector2i in _layers.keys():
		result.append(coords)
	return result


# ------------------------------------------------------------ 主循环

func _process(_delta: float) -> void:
	if _generator == null or _spec == null or focus_node == null:
		return
	_reap_tasks()
	_drain_results()
	# 移动或改变 zoom 后也补齐视口，其余区块继续使用后台预算。
	prepare_visible()
	# 玩家跨区块时才重排视口外的后台任务。
	var focus: Vector2i = WorldGenerator.tile_to_chunk(
		WorldGenerator.world_to_tile(focus_node.global_position)
	)
	if focus != _focus_chunk:
		_rebuild_queue()
	_dispatch()
	_apply_results()


func _create_region(spec: MapSpec) -> void:
	var root := Node2D.new()
	root.name = "Map_%d" % spec.node_id
	root.visible = false
	add_child(root)
	var chunks: Array[Vector2i] = []
	var first: Vector2i = WorldGenerator.tile_to_chunk(spec.origin)
	var last: Vector2i = WorldGenerator.tile_to_chunk(spec.origin + spec.extent - Vector2i.ONE)
	for cy: int in range(first.y, last.y + 1):
		for cx: int in range(first.x, last.x + 1):
			chunks.append(Vector2i(cx, cy))
	_regions[spec.node_id] = {"root": root, "spec": spec, "layers": {}, "chunks": chunks}


func _rebuild_queue() -> void:
	# 待铺结果持有数据引用，不因 LRU 淘汰而丢块或重复生成。
	var available: Dictionary = {}
	for entry: Dictionary in _apply_queue:
		var id: int = entry["map_id"]
		var data: ChunkData = entry["data"]
		if _desired.has(id) and _regions.has(id) and data.epoch == _epoch:
			available[data.coords] = data
	_queue.clear()
	_apply_queue.clear()
	_pending.clear()
	if _generator == null or _spec == null:
		return
	if focus_node != null:
		_focus_chunk = WorldGenerator.tile_to_chunk(WorldGenerator.world_to_tile(focus_node.global_position))
	var queued: Dictionary = {}
	# 当前整图优先，其余直接邻居随后；同坐标只提交一次生成。
	var ids: Array[int] = [_spec.node_id]
	for id: int in _desired.keys():
		if id != _spec.node_id:
			ids.append(id)
	for id: int in ids:
		var layers: Dictionary = _regions[id]["layers"]
		var chunks: Array[Vector2i] = _regions[id]["chunks"]
		for coords: Vector2i in chunks:
			if layers.has(coords):
				continue
			var data: ChunkData = available.get(coords, _cache.get(coords))
			if data != null and data.epoch == _epoch:
				if not available.has(coords):
					stat_cache_hits += 1
				_enqueue_application(id, data)
			elif not _in_flight.has(coords) and not queued.has(coords):
				queued[coords] = true
				_queue.append(coords)
	_sort_queue()


func _available_chunk(coords: Vector2i) -> ChunkData:
	var cached: ChunkData = _cache.get(coords)
	if cached != null and cached.epoch == _epoch:
		return cached
	for entry: Dictionary in _apply_queue:
		var data: ChunkData = entry["data"]
		if data.coords == coords and data.epoch == _epoch:
			return data
	return null


func _enqueue_application(map_id: int, data: ChunkData) -> void:
	if not _desired.has(map_id) or not _regions.has(map_id):
		return
	var layers: Dictionary = _regions[map_id]["layers"]
	if layers.has(data.coords):
		return
	if not _pending.has(map_id):
		_pending[map_id] = {}
	var pending: Dictionary = _pending[map_id]
	if pending.has(data.coords):
		return
	pending[data.coords] = true
	_apply_queue.append({"map_id": map_id, "data": data})


func _enqueue_data(data: ChunkData) -> void:
	for id: int in _desired.keys():
		var spec: MapSpec = _regions[id]["spec"]
		var chunk_bounds := Rect2i(data.coords * WorldGenerator.CHUNK_SIZE, Vector2i.ONE * WorldGenerator.CHUNK_SIZE)
		if Rect2i(spec.origin, spec.extent).intersects(chunk_bounds):
			_enqueue_application(id, data)


func _current_needs(coords: Vector2i) -> bool:
	if _spec == null or _layers.has(coords):
		return false
	return Rect2i(_spec.origin, _spec.extent).intersects(
		Rect2i(coords * WorldGenerator.CHUNK_SIZE, Vector2i.ONE * WorldGenerator.CHUNK_SIZE))


## 玩家脚下的区块先铺，其余按距离排队。
func _sort_queue() -> void:
	var center: Vector2i = _focus_chunk
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_current: bool = _current_needs(a)
		var b_current: bool = _current_needs(b)
		if a_current != b_current:
			return a_current
		var a_prewarm: bool = _prewarm_chunks.has(a)
		var b_prewarm: bool = _prewarm_chunks.has(b)
		if a_prewarm != b_prewarm:
			return a_prewarm
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


func _reap_tasks() -> bool:
	if _in_flight.is_empty():
		return false
	var finished: Array[Vector2i] = []
	for coords: Vector2i in _in_flight.keys():
		var task_id: int = _in_flight[coords]
		if WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
			finished.append(coords)
	for coords: Vector2i in finished:
		_in_flight.erase(coords)
	return not finished.is_empty()


func _drain_results() -> Dictionary:
	_result_mutex.lock()
	var incoming: Array[ChunkData] = _completed.duplicate()
	_completed.clear()
	_result_mutex.unlock()
	var result: Dictionary = {}
	for data: ChunkData in incoming:
		if data.epoch != _epoch:
			continue
		data.last_used = Time.get_ticks_msec()
		_store_cache(data)
		result[data.coords] = data
		# 已回收区域不会重建；迟到结果只向目前仍 desired 的区域铺图。
		_enqueue_data(data)
	return result


func _dispatch() -> void:
	var dispatched: int = 0
	while dispatched < generations_per_frame and not _queue.is_empty():
		var coords: Vector2i = _queue[0]
		_queue.remove_at(0)
		if _in_flight.has(coords):
			continue

		var cached: ChunkData = _cache.get(coords)
		if cached != null and cached.epoch == _epoch:
			cached.last_used = Time.get_ticks_msec()
			stat_cache_hits += 1
			_enqueue_data(cached)
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
	var current_id: int = _spec.node_id
	_apply_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_current: bool = int(a["map_id"]) == current_id
		var b_current: bool = int(b["map_id"]) == current_id
		if a_current != b_current:
			return a_current
		var a_data: ChunkData = a["data"]
		var b_data: ChunkData = b["data"]
		var a_prewarm: bool = int(a["map_id"]) == _prewarm_map_id and _prewarm_chunks.has(a_data.coords)
		var b_prewarm: bool = int(b["map_id"]) == _prewarm_map_id and _prewarm_chunks.has(b_data.coords)
		if a_prewarm != b_prewarm:
			return a_prewarm
		return (a_data.coords - center).length_squared() < (b_data.coords - center).length_squared()
	)
	var applied: int = 0
	var started: int = Time.get_ticks_usec()
	while applied < applications_per_frame and not _apply_queue.is_empty():
		var next: Dictionary = _apply_queue[0]
		var next_id: int = next["map_id"]
		var next_data: ChunkData = next["data"]
		# 不可见邻图保留数据，只有过场到达视口需要提前铺图。
		if next_id != current_id and (next_id != _prewarm_map_id or not _prewarm_chunks.has(next_data.coords)):
			break
		var entry: Dictionary = _apply_queue.pop_front()
		var data: ChunkData = entry["data"]
		var map_id: int = entry["map_id"]
		if _pending.has(map_id):
			_pending[map_id].erase(data.coords)
		if data.epoch != _epoch or not _desired.has(map_id) or not _regions.has(map_id):
			continue
		var layers: Dictionary = _regions[map_id]["layers"]
		if layers.has(data.coords):
			continue
		_paint_chunk(data, map_id)
		applied += 1
		if Time.get_ticks_usec() - started >= APPLY_BUDGET_USEC:
			break
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


func _generate_inline(coords: Vector2i) -> ChunkData:
	var started: int = Time.get_ticks_usec()
	var data: ChunkData = _generator.generate_chunk(coords, _epoch)
	var elapsed: int = Time.get_ticks_usec() - started

	_result_mutex.lock()
	stat_generated += 1
	stat_generate_usec += elapsed
	stat_last_generate_usec = elapsed
	_result_mutex.unlock()
	data.last_used = Time.get_ticks_msec()
	_store_cache(data)
	_enqueue_data(data)
	return data


# 每个工作线程各拿一个生成器实例，避免多个线程共用同一套噪声对象
func _acquire_generator() -> WorldGenerator:
	_generator_mutex.lock()
	var worker: WorldGenerator = null
	if not _generator_pool.is_empty():
		worker = _generator_pool.pop_back()
	_generator_mutex.unlock()

	if worker != null:
		return worker
	return WorldGenerator.new(_world_seed, _config, _variant, _generator.population_snapshot())


func _release_generator(worker: WorldGenerator) -> void:
	_generator_mutex.lock()
	if _generator_pool.size() < MAX_GENERATOR_POOL:
		_generator_pool.append(worker)
	_generator_mutex.unlock()


# ------------------------------------------------------------ 铺图与回收

func _paint_chunk(data: ChunkData, map_id: int = -1) -> void:
	if map_id == -1:
		if _spec == null:
			return
		map_id = _spec.node_id
	if data.epoch != _epoch or not _desired.has(map_id) or not _regions.has(map_id):
		return
	var region: Dictionary = _regions[map_id]
	var layers: Dictionary = region["layers"]
	if layers.has(data.coords):
		return
	var spec: MapSpec = region["spec"]
	var bounds := Rect2i(spec.origin, spec.extent)
	var tile_origin: Vector2i = data.coords * WorldGenerator.CHUNK_SIZE
	if not bounds.intersects(Rect2i(tile_origin, Vector2i.ONE * WorldGenerator.CHUNK_SIZE)):
		return
	var layer: TileMapLayer = _take_layer()
	# 裁剪后的边缘区块不会重写每格，复用前必须清掉上一张地图的格子。
	layer.clear()
	# 节点位置承担世界偏移，格子坐标只用 0..CHUNK_SIZE-1
	layer.position = Vector2(
		data.coords.x * WorldGenerator.CHUNK_SIZE * WorldGenerator.TILE_SIZE,
		data.coords.y * WorldGenerator.CHUNK_SIZE * WorldGenerator.TILE_SIZE
	)

	var samples: PackedByteArray = TerrainTransitions.halo(_generator, data, spec)
	var index: int = 0
	for local_y: int in WorldGenerator.CHUNK_SIZE:
		for local_x: int in WorldGenerator.CHUNK_SIZE:
			var cell := Vector2i(local_x, local_y)
			if not bounds.has_point(tile_origin + cell):
				index += 1
				continue
			var road: int = data.route[index]
			var kind: int = TerrainTransitions.display_kind(data.terrain[index], road)
			var edge: Vector2i = TerrainTransitions.seam_at(_generator, spec, tile_origin + cell, kind)
			if edge == TerrainTransitions.NO_BLEND:
				edge = TerrainTransitions.edge_at(samples, cell)
			if edge == TerrainTransitions.NO_BLEND:
				edge = TerrainTransitions.gate_at(_generator, spec, tile_origin + cell, kind)
			if edge != TerrainTransitions.NO_BLEND:
				layer.set_cell(cell, TerrainTransitions.SOURCE_ID, edge)
			elif road == Route.Kind.NONE:
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

	var root: Node2D = region["root"]
	root.add_child(layer)
	layers[data.coords] = layer

	data.last_used = Time.get_ticks_msec()
	_store_cache(data)
	stat_applied += 1
	if _spec != null and map_id == _spec.node_id:
		version += 1
		chunk_applied.emit(data.coords)


func _take_layer() -> TileMapLayer:
	if not _layer_pool.is_empty():
		return _layer_pool.pop_back()

	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	layer.rendering_quadrant_size = WorldGenerator.CHUNK_SIZE
	return layer


func _recycle_layer(coords: Vector2i, layers: Dictionary) -> void:
	var layer: TileMapLayer = layers.get(coords)
	if layer == null:
		return
	layers.erase(coords)
	layer.get_parent().remove_child(layer)
	layer.clear()
	if _layer_pool.size() < MAX_LAYER_POOL:
		_layer_pool.append(layer)
	else:
		layer.queue_free()


func _release_region(map_id: int) -> void:
	var region: Dictionary = _regions[map_id]
	var layers: Dictionary = region["layers"]
	for coords: Vector2i in layers.keys():
		_recycle_layer(coords, layers)
	var root: Node2D = region["root"]
	root.visible = false
	remove_child(root)
	root.queue_free()
	_regions.erase(map_id)


func _store_cache(data: ChunkData) -> void:
	_cache[data.coords] = data
	if _cache.size() <= cache_limit:
		return

	# LRU：淘汰最久没被碰过的那一块
	var oldest_coords: Vector2i = Vector2i(2147483647, 2147483647)
	var oldest_time: int = 2147483647
	for coords: Vector2i in _cache.keys():
		var entry: ChunkData = _cache[coords]
		if entry.last_used < oldest_time:
			oldest_time = entry.last_used
			oldest_coords = coords
	if oldest_coords.x != 2147483647:
		_cache.erase(oldest_coords)


# ------------------------------------------------------------ 清理

func _wait_for_tasks() -> void:
	# 等待时不持有互斥锁：任务需要归还生成器和提交结果后才能结束。
	for coords: Vector2i in _in_flight.keys():
		var task_id: int = _in_flight[coords]
		WorkerThreadPool.wait_for_task_completion(task_id)
	_in_flight.clear()


func _free_all_layers() -> void:
	for id: int in _regions.keys():
		_release_region(id)
	_layers = {}
	_desired.clear()
	_pending.clear()
	_queue.clear()

	for layer: TileMapLayer in _layer_pool:
		if is_instance_valid(layer):
			layer.queue_free()
	_layer_pool.clear()

	_result_mutex.lock()
	_completed.clear()
	_result_mutex.unlock()

	_apply_queue.clear()


func _reset_stats() -> void:
	stat_generated = 0
	stat_cache_hits = 0
	stat_applied = 0
	stat_generate_usec = 0
	stat_apply_usec = 0
	stat_last_generate_usec = 0
