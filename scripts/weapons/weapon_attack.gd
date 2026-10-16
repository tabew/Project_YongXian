class_name WeaponAttack
extends Node2D

signal finished
signal hit_landed(hit: CombatHit, hurtbox: CombatHurtbox)

const QUERY_BATCH: int = 32

var definition: WeaponDefinition
var wielder: Node2D
var wielder_team: int = 1
var aim_direction: Vector2 = Vector2.RIGHT
var elapsed: float = 0.0

var _hit_receivers: Dictionary[int, bool] = {}
var _running: bool = false


## Subclasses validate their resource type here before the controller equips it.
func accepts_definition(_data: WeaponDefinition) -> bool:
	return true


func start(data: WeaponDefinition, actor: Node2D, team: int, aim: Vector2) -> void:
	definition = data.duplicate(true) as WeaponDefinition
	wielder = actor
	wielder_team = team
	aim_direction = aim.normalized() if not aim.is_zero_approx() else Vector2.RIGHT
	elapsed = 0.0
	_hit_receivers.clear()
	_running = true
	_on_started()


func cancel() -> void:
	_running = false
	hide()
	queue_free()


func _physics_process(delta: float) -> void:
	if not _running:
		return
	if not is_instance_valid(wielder):
		_complete()
		return
	var previous: float = elapsed
	elapsed += delta
	_advance(previous, elapsed)
	if _running and elapsed >= definition.attack_duration():
		_complete()


func _complete() -> void:
	_running = false
	finished.emit()
	queue_free()


func _on_started() -> void:
	pass


## Implement animation and hit queries for [previous, current], including skipped frames.
func _advance(_previous: float, _current: float) -> void:
	pass


func _try_hit(hurtbox: CombatHurtbox) -> void:
	if not _running or not hurtbox.can_receive_hit(wielder, wielder_team):
		return
	var target_id: int = hurtbox.receiver_id()
	if _hit_receivers.has(target_id):
		return
	_hit_receivers[target_id] = true
	_land_hit(hurtbox)


## 生成一次命中并交给目标。子类改变“谁在什么时候可以被命中”的规则后，
## 仍然复用这里的伤害、暴击、击退与命中信号。
func _land_hit(hurtbox: CombatHurtbox) -> void:
	var hit: CombatHit = CombatHit.new()
	hit.source = wielder
	hit.weapon_id = definition.id
	hit.critical = MapRng.shared(MapRng.Stream.COMBAT).randf() < definition.critical_chance
	hit.damage = definition.damage * (definition.critical_multiplier if hit.critical else 1.0)
	hit.position = hurtbox.global_position
	var direction: Vector2 = (hurtbox.global_position - wielder.global_position).normalized()
	if direction.is_zero_approx():
		direction = aim_direction
	hit.knockback = direction * definition.knockback
	if hurtbox.receive_hit(hit):
		hit_landed.emit(hit, hurtbox)


## Drain batches so friendly or duplicate hurtboxes cannot hide targets in a crowd.
func _query_hurtboxes(query: PhysicsShapeQueryParameters2D) -> void:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var excluded: Array[RID] = []
	while _running:
		query.exclude = excluded
		var results: Array[Dictionary] = space.intersect_shape(query, QUERY_BATCH)
		for result: Dictionary in results:
			excluded.append(result["rid"])
			var hurtbox: CombatHurtbox = result["collider"] as CombatHurtbox
			if hurtbox != null:
				_try_hit(hurtbox)
		if results.size() < QUERY_BATCH:
			break


## 武器形状掠过时清除范围内的草丛（星露谷式牧草，只长在各群系的自然地面上）。
## 子类每次完成一次形状查询后调用；local_points 为攻击节点本地坐标的多边形顶点，
## 与传给 _query_hurtboxes 的是同一组点。返回清除的簇数；只影响可见地图上的草丛。
func _clear_grass(local_points: PackedVector2Array) -> int:
	if local_points.size() < 3:
		return 0
	var world_points := PackedVector2Array()
	world_points.resize(local_points.size())
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for index: int in local_points.size():
		var point: Vector2 = local_points[index] + global_position
		world_points[index] = point
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	# 按形状包围盒直接取邻近的草丛块，不遍历整棵树的节点，也不扫描全图草簇。
	var cut: int = 0
	for node: Node in GrassView.views_in_rect(
		Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
	):
		var view := node as GrassView
		if view == null or not view.is_visible_in_tree():
			continue
		cut += view.cut_area(world_points)
	if cut > 0:
		_play_sfx(&"cut_grass", global_position)
	return cut


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载。
func _play_sfx(id: StringName, position: Vector2 = Vector2.INF) -> void:
	var manager: Node = get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.call("play_sfx", id, position)
