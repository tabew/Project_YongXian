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
		_apply_enchant_effects(hurtbox)
		hit_landed.emit(hit, hurtbox)


## 武器附魔：命中后把武器上的炼金属性逐个作用出去。
## need_target 的属性作用到被命中的实体，其余(爆炸这类)作用到命中点；
## enchant_target = WIELDER 的属性(治疗/恢复)作用到持武器的人自己。
func _apply_enchant_effects(hurtbox: CombatHurtbox) -> void:
	if definition == null or definition.enchant_attributes.is_empty():
		return
	var point: Node2D = null
	for attribute: AlchemicalData in definition.enchant_attributes:
		if attribute == null:
			continue
		if attribute.need_target:
			var target: Node = wielder if attribute.enchant_target == AlchemicalData.EnchantTarget.WIELDER else hurtbox.get_parent()
			attribute.use_effect(target)
			continue
		if point == null:
			point = _make_enchant_point(hurtbox.global_position)
		if point != null:
			attribute.use_effect(point)
	if point != null:
		point.queue_free()


## 不需要目标的属性(如爆炸)要求传进去的 Node2D 在世界里，用它的位置当作用点。
## 借一个临时标记点，不挂到怪物身上：怪死了会把挂在它下面的特效一起带走。
func _make_enchant_point(at: Vector2) -> Node2D:
	var world: Node = null
	if is_instance_valid(wielder):
		world = wielder.get_parent()
	if world == null:
		world = get_parent()
	if world == null:
		return null
	var marker := Node2D.new()
	world.add_child(marker)
	marker.global_position = at
	return marker


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
