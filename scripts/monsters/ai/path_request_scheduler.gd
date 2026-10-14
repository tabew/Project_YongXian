extends Node

## 多怪物共享寻路服务（autoload：PathRequestScheduler）。
##
## 每帧只执行 max_requests_per_frame 次 A*，其余请求排队，避免同一帧所有怪物一起算路径。
## 结果通过 Callable 回传，调用方（EnemyNavigator）用 generation 丢弃过期结果。

@export_range(1, 64, 1) var max_requests_per_frame: int = 3
@export_range(1, 4096, 1) var max_queue_size: int = 256

var _queue: Array[Dictionary] = []
var _budget_used: int = 0
var _next_request_id: int = 1


func request_path(
	host: BaseMonster,
	start_tile: Vector2i,
	target_tile: Vector2i,
	callback: Callable,
	margin_tiles: int = 6,
	physics_solids: Dictionary = {}
) -> int:
	var request_id: int = _next_request_id
	_next_request_id += 1
	if host == null or not is_instance_valid(host) or not callback.is_valid():
		return 0
	var entry: Dictionary = {
		"host": host,
		"start": start_tile,
		"target": target_tile,
		"callback": callback,
		"margin": margin_tiles,
		"solids": physics_solids,
	}
	if _budget_used < max_requests_per_frame:
		_budget_used += 1
		_deliver(entry)
	else:
		if _queue.size() >= max_queue_size:
			_queue.pop_front()
		_queue.append(entry)
	return request_id


func _process(_delta: float) -> void:
	while _budget_used < max_requests_per_frame and not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		_budget_used += 1
		_deliver(entry)
	_budget_used = 0


func _deliver(entry: Dictionary) -> void:
	# 切图后的旧排队目标可能已被释放；必须先检查Variant，再赋给强类型。
	if not is_instance_valid(entry["host"]):
		return
	var host: BaseMonster = entry["host"]
	var callback: Callable = entry["callback"]
	if not host.is_inside_tree() or not host.can_process() or not host.is_visible_in_tree() or not callback.is_valid():
		return
	var result: Array[Vector2i] = EnemyPathfinder.build_path(
		host,
		entry["start"],
		entry["target"],
		entry["margin"],
		entry["solids"]
	)
	callback.call(result)
