extends Node

## 多怪物共享感知服务（autoload：PerceptionManager）。
##
## 怪物不直接每帧做全量视线检测，而是通过 request_evaluation() 提交；预算内的立即
## 评估，超预算的排队到后续帧，避免同一帧所有怪物一起做昂贵的射线 + 地形采样。
## 同时把 EventBus 上的噪音/警报广播给半径内的怪物，作为可疑信息写入它们的黑板。

@export_range(1, 64, 1) var max_evaluations_per_frame: int = 6
@export_range(1, 4096, 1) var max_queue_size: int = 512

var _queue: Array[BaseMonster] = []
var _budget_used: int = 0


func _ready() -> void:
	# 用 /root 路径取事件总线，不直接引用 EventBus 单例标识符。
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus == null:
		return
	bus.connect(&"noise_reported", _on_suspicious_event)
	bus.connect(&"alert_raised", _on_suspicious_event)


## 返回 true 表示本帧已完成评估；false 表示已排队到后续帧。
func request_evaluation(host: BaseMonster) -> bool:
	if host == null or not is_instance_valid(host):
		return false
	if _budget_used < max_evaluations_per_frame:
		_budget_used += 1
		host.evaluate_perception()
		return true
	if not _queue.has(host):
		if _queue.size() >= max_queue_size:
			_queue.pop_front()
		_queue.append(host)
	return false


func _process(_delta: float) -> void:
	while _budget_used < max_evaluations_per_frame and not _queue.is_empty():
		# 切图会释放排队中的怪物，先检查 Variant 再赋值为节点类型。
		var pending: Variant = _queue.pop_front()
		if not is_instance_valid(pending):
			continue
		var host: BaseMonster = pending as BaseMonster
		if host.is_queued_for_deletion() or not host.is_inside_tree() or not host.can_process():
			continue
		_budget_used += 1
		host.evaluate_perception()
	_budget_used = 0


## 噪音 / 队友警报走同一条通道：半径内（或怪物自身听觉半径内）的怪物记为可疑。
func _on_suspicious_event(position: Vector2, radius: float, _source: Node = null) -> void:
	for node: Node in get_tree().get_nodes_in_group("monsters"):
		var monster := node as BaseMonster
		if monster == null or not is_instance_valid(monster):
			continue
		var hearing: float = maxf(radius, monster.ai_hearing_radius())
		if hearing <= 0.0:
			continue
		if monster.global_position.distance_to(position) <= hearing:
			monster.report_suspicious(position)
			var owner: Node = monster.get_parent()
			if owner != null and owner.has_method("wake_for_suspicious_event"):
				owner.call("wake_for_suspicious_event", monster)
