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
## 由 WeaponController 注入的炼金组合伤害倍率；默认 1.0。
var damage_multiplier: float = 1.0
## 由 WeaponController 注入的额外暴击率（炼金遗物「暴击之眼」等）；默认 0。
var critical_chance_bonus: float = 0.0
## 由 WeaponController 注入的行为词条效果表（AlchemyHitEffects.profile）；默认空表。
var hit_effects: Dictionary = {}

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
	var crit_chance: float = clampf(definition.critical_chance + critical_chance_bonus, 0.0, 1.0)
	hit.critical = MapRng.shared(MapRng.Stream.COMBAT).randf() < crit_chance
	hit.damage = definition.damage * damage_multiplier * (definition.critical_multiplier if hit.critical else 1.0)
	hit.position = hurtbox.global_position
	var direction: Vector2 = (hurtbox.global_position - wielder.global_position).normalized()
	if direction.is_zero_approx():
		direction = aim_direction
	hit.knockback = direction * definition.knockback
	if hurtbox.receive_hit(hit):
		hit_landed.emit(hit, hurtbox)
		_apply_extra_hits(hit, hurtbox)


## 行为词条的额外命中：爆炸范围伤害、连锁跳目标、回旋二次打击。
## 这些伤害直接走 receive_hit，不经过 _land_hit，所以不会再递归触发额外命中。
func _apply_extra_hits(hit: CombatHit, center: CombatHurtbox) -> void:
	if hit_effects.is_empty() or not AlchemyHitEffects.has_any(hit_effects):
		return
	_apply_whirl(hit, center)
	_spawn_summons(hit)
	var radius_tiles: float = AlchemyHitEffects.extra_hit_radius_tiles(hit_effects)
	if radius_tiles <= 0.0:
		return
	var targets: Array[CombatHurtbox] = _targets_within(hit.position, radius_tiles, center)
	if targets.is_empty():
		return
	_apply_explosion(hit, targets)
	_apply_chain(hit, targets)


## 召唤：召唤词条 / 骨 V 骷髅 / 灵魂 V 游魂都走这里，按来源表逐条掷概率生成召唤物。
## 召唤物挂在持械者所在的世界节点下，寿命到期自行消散。
func _spawn_summons(hit: CombatHit) -> void:
	var specs: Array[Dictionary] = AlchemyHitEffects.summon_specs(hit_effects)
	if specs.is_empty() or not is_instance_valid(wielder):
		return
	var parent: Node = wielder.get_parent()
	if parent == null:
		return
	var rng: RandomNumberGenerator = MapRng.shared(MapRng.Stream.COMBAT)
	for spec: Dictionary in specs:
		if rng.randf() >= float(spec.get("chance", 0.0)):
			continue
		var count: int = maxi(int(spec.get("count", 1)), 1)
		for index: int in range(count):
			var summon: AlchemySummon = AlchemySummon.new()
			summon.damage = definition.damage * damage_multiplier * AlchemyRules.SUMMON_DAMAGE_RATIO
			summon.lifetime = float(spec.get("duration", 5.0))
			summon.explodes = bool(spec.get("explode", false))
			summon.tint = AlchemyHitEffects.flavor_color(StringName(spec.get("flavor", &"summon")))
			summon.owner_actor = wielder
			parent.add_child(summon)
			var offset: float = float(index) * 12.0 - float(count - 1) * 6.0
			summon.global_position = hit.position + Vector2(offset, -6.0)


## 回旋：按概率对刚命中的目标再补一次伤害。
func _apply_whirl(hit: CombatHit, center: CombatHurtbox) -> void:
	var whirl: Dictionary = hit_effects.get("whirl", {})
	if whirl.is_empty() or center == null:
		return
	if MapRng.shared(MapRng.Stream.COMBAT).randf() >= float(whirl.get("chance", 0.0)):
		return
	var extra: CombatHit = _spawn_hit(hit, float(whirl.get("damage", 0.60)), center.global_position)
	center.receive_hit(extra)
	if bool(whirl.get("double", false)):
		center.receive_hit(_spawn_hit(hit, float(whirl.get("damage", 0.60)), center.global_position))


## 爆炸：半径内所有其它目标吃一次按比例衰减的范围伤害。
func _apply_explosion(hit: CombatHit, targets: Array[CombatHurtbox]) -> void:
	var explode: Dictionary = hit_effects.get("explode", {})
	if explode.is_empty():
		return
	if MapRng.shared(MapRng.Stream.COMBAT).randf() >= float(explode.get("chance", 0.0)):
		return
	var ratio: float = float(explode.get("damage", 0.5))
	for target: CombatHurtbox in targets:
		target.receive_hit(_spawn_hit(hit, ratio, target.global_position))


## 连锁 / 弹射：按概率把伤害跳到最近的若干个其它目标上。
func _apply_chain(hit: CombatHit, targets: Array[CombatHurtbox]) -> void:
	var chain: Dictionary = hit_effects.get("chain", {})
	var bounce: Dictionary = hit_effects.get("bounce", {})
	var jumps: int = 0
	var ratio: float = 0.0
	var chance: float = 1.0
	if not chain.is_empty():
		chance = float(chain.get("chance", 0.0))
		jumps = int(chain.get("targets", 0))
		ratio = float(chain.get("damage", 0.5))
	elif not bounce.is_empty():
		jumps = int(bounce.get("bounces", 0))
		ratio = float(bounce.get("damage", 0.5))
	if jumps <= 0 or ratio <= 0.0:
		return
	if MapRng.shared(MapRng.Stream.COMBAT).randf() >= chance:
		return
	var ordered: Array[CombatHurtbox] = targets.duplicate()
	ordered.sort_custom(_closer_to.bind(hit.position))
	for index: int in range(mini(jumps, ordered.size())):
		var target: CombatHurtbox = ordered[index]
		target.receive_hit(_spawn_hit(hit, ratio, target.global_position))


## 以 base 为模板生成一次派生命中：不继承暴击，方向由命中点向外。
func _spawn_hit(base: CombatHit, ratio: float, position: Vector2) -> CombatHit:
	var extra: CombatHit = CombatHit.new()
	extra.source = base.source
	extra.weapon_id = base.weapon_id
	extra.critical = false
	extra.damage = base.damage * ratio
	extra.position = position
	var direction: Vector2 = (position - wielder.global_position).normalized() if is_instance_valid(wielder) else Vector2.ZERO
	if direction.is_zero_approx():
		direction = aim_direction
	extra.knockback = direction * definition.knockback * 0.5
	return extra


## 半径内的可命中目标（排除命中点自身与同队目标）。
func _targets_within(center: Vector2, radius_tiles: float, exclude: CombatHurtbox) -> Array[CombatHurtbox]:
	var found: Array[CombatHurtbox] = []
	if not is_inside_tree():
		return found
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = radius_tiles * float(WorldGenerator.TILE_SIZE)
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, center)
	query.collision_mask = definition.hit_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for result: Dictionary in space.intersect_shape(query, QUERY_BATCH):
		var hurtbox: CombatHurtbox = result["collider"] as CombatHurtbox
		if hurtbox == null or hurtbox == exclude:
			continue
		if not hurtbox.can_receive_hit(wielder, wielder_team):
			continue
		if found.has(hurtbox):
			continue
		found.append(hurtbox)
	return found


static func _closer_to(a: CombatHurtbox, b: CombatHurtbox, center: Vector2) -> bool:
	return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center)


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
