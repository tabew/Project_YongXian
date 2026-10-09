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
	var hit: CombatHit = CombatHit.new()
	hit.source = wielder
	hit.weapon_id = definition.id
	hit.critical = randf() < definition.critical_chance
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
