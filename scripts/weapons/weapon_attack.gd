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
	_spawn_orbit_balls()


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
	var multiplier: float = 1.0
	if wielder != null and wielder.has_method("outgoing_damage_multiplier"):
		multiplier = float(wielder.call("outgoing_damage_multiplier", hurtbox))
	hit.damage = definition.damage * multiplier * (definition.critical_multiplier if hit.critical else 1.0)
	hit.position = hurtbox.global_position
	var direction: Vector2 = (hurtbox.global_position - wielder.global_position).normalized()
	if direction.is_zero_approx():
		direction = aim_direction
	hit.knockback = direction * definition.knockback
	if hurtbox.receive_hit(hit):
		hit_landed.emit(hit, hurtbox)
		_apply_on_hit_effects(hurtbox)


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


## 命中后的升级卡效果：定身、连击计数、连击窗口、前冲。
func _apply_on_hit_effects(hurtbox: CombatHurtbox) -> void:
	if definition.slow_ratio > 0.0 and definition.slow_seconds > 0.0:
		var receiver: Node = hurtbox.health.get_parent() if hurtbox.health != null else null
		if receiver != null and receiver.has_method("apply_slow"):
			receiver.call("apply_slow", definition.slow_ratio, definition.slow_seconds)
	if wielder != null and wielder.has_method("register_hit"):
		wielder.call("register_hit", hurtbox)
	if definition.combo_window > 0.0:
		# 命中后缩短后摇，形成可以连打的窗口。
		definition.recovery_seconds = maxf(definition.recovery_seconds - definition.combo_window, 0.0)
	if definition.lunge_tiles > 0.0:
		_lunge()


## 朝准心短距离前冲，逐格检查可站立，避免冲进不可通行地形。
func _lunge() -> void:
	var actor := wielder as PlayerCharacter
	if actor == null:
		return
	var distance: float = definition.lunge_tiles * float(WorldGenerator.TILE_SIZE)
	var target: Vector2 = actor.global_position + aim_direction * distance
	var steps: int = maxi(ceili(distance / 4.0), 1)
	var last_ok: Vector2 = actor.global_position
	for index: int in range(1, steps + 1):
		var point: Vector2 = actor.global_position.lerp(target, float(index) / float(steps))
		if not actor.can_stand_at(point):
			break
		last_ok = point
	actor.global_position = last_ok


## 攻击期间额外环绕自身的球；作为攻击实例的子节点，攻击结束自动释放。
func _spawn_orbit_balls() -> void:
	if definition == null or definition.orbit_balls <= 0 or not is_instance_valid(wielder):
		return
	for index: int in definition.orbit_balls:
		var ball := OrbitBall.new()
		ball.name = "OrbitBall%d" % index
		ball.setup(wielder, definition, wielder_team, index, definition.orbit_balls)
		ball.hit_landed.connect(func(hit: CombatHit, box: CombatHurtbox) -> void: hit_landed.emit(hit, box))
		add_child(ball)
