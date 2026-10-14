class_name InspirationField
extends Node2D

## 灵感光点对象池：预分配 200 个，超出阈值时把光点合并成光团。
## 挂在世界层（局内）或工坊层（训练场演示）下。

## 光点飞入完成：携带本光点的灵感数量与是否光团。
signal collected(amount: int, source: int, is_cluster: bool)
## 合并成光团（表现层可播提示音）。
signal merged(total: int)

## 目标节点（玩家）。
var target: Node2D = null

var _pool: Array[InspirationPickup] = []
var _active: Array[InspirationPickup] = []
## 超过阈值时，后续掉落先攒在这里，合成一个光团。
var _cluster_amount: int = 0
var _cluster_source: int = InspirationRules.Source.NORMAL
var _cluster_position: Vector2 = Vector2.ZERO
var _cluster_pickup: InspirationPickup = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_pool()


func _build_pool() -> void:
	for index: int in InspirationDrop.POOL_SIZE:
		var pickup := InspirationPickup.new()
		pickup.arrived.connect(_on_pickup_arrived.bind(pickup))
		add_child(pickup)
		pickup.deactivate()
		_pool.append(pickup)


## 生成一次掉落：按来源拆成若干光点；超过阈值则合并成光团。
func spawn(position: Vector2, amount: int, source: int) -> int:
	if amount <= 0:
		return 0
	if InspirationFlight.should_merge(active_count()):
		return _merge(position, amount, source)
	var points: int = InspirationDrop.point_count(amount, source)
	var splits: PackedInt32Array = InspirationDrop.split_amount(amount, points)
	var spawned: int = 0
	for value: int in splits:
		if _spawn_point(position, value, source) != null:
			spawned += value
	return spawned


## 合并成光团：金额累加到一个大光点上，飞入后由 UI 拆分数字。
func _merge(position: Vector2, amount: int, source: int) -> int:
	_cluster_amount += amount
	_cluster_position = position
	if _cluster_pickup == null or not _cluster_pickup.is_active():
		_cluster_source = source
		_cluster_pickup = _spawn_point(position, _cluster_amount, source)
		if _cluster_pickup != null:
			_cluster_pickup.is_cluster = true
		merged.emit(_cluster_amount)
	else:
		# 已有光团在飞：直接加数量，稍后一起结算。
		_cluster_pickup.amount = _cluster_amount
	return amount


func _spawn_point(position: Vector2, amount: int, source: int) -> InspirationPickup:
	var pickup: InspirationPickup = _take()
	if pickup == null:
		return null
	pickup.launch(position, amount, source, target, _rng.randi())
	if not _active.has(pickup):
		_active.append(pickup)
	return pickup


func _take() -> InspirationPickup:
	for pickup: InspirationPickup in _pool:
		if not pickup.is_active():
			return pickup
	return null


func _on_pickup_arrived(amount: int, pickup: InspirationPickup) -> void:
	_active.erase(pickup)
	var is_cluster: bool = pickup.is_cluster
	var parts: PackedInt32Array = pickup.cluster_parts
	if is_cluster:
		_cluster_amount = 0
		_cluster_pickup = null
		if parts.is_empty():
			parts = InspirationDrop.split_amount(amount, InspirationDrop.point_count(amount, _cluster_source))
		collected.emit(amount, _cluster_source, true)
	else:
		collected.emit(amount, pickup.source, false)
	pickup.deactivate()


func active_count() -> int:
	return _active.size()


func pool_size() -> int:
	return _pool.size()


## 立即回收全部光点（切场景 / 重开时用）。
func clear_all() -> void:
	for pickup: InspirationPickup in _pool:
		pickup.deactivate()
	_active.clear()
	_cluster_amount = 0
	_cluster_pickup = null
