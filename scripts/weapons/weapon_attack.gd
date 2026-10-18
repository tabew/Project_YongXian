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
	elapsed += delta * speed_multiplier()
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


## 暴击率：武器基础值 + 持有者的暴击加成
func critical_chance_total() -> float:
	var chance: float = definition.critical_chance if definition != null else 0.0

	if wielder != null and is_instance_valid(wielder) and wielder.has_method("read_stat"):
		chance += maxf(float(wielder.call("read_stat", &"crit_chance")), 0.0)
	return clampf(chance, 0.0, 1.0)


## 出手速度倍率：持有者的攻速加成 + 武器附魔直接加的攻速（急速）
func speed_multiplier() -> float:
	var bonus: float = 0.0

	if wielder != null and is_instance_valid(wielder) and wielder.has_method("read_stat"):
		bonus += maxf(float(wielder.call("read_stat", &"attack_speed")), 0.0)
	if definition != null:
		bonus += definition.enchant_attack_speed()
	return 1.0 + bonus


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
func _land_hit(hurtbox: CombatHurtbox, damage_scale: float = 1.0) -> void:
	var hit: CombatHit = CombatHit.new()
	hit.source = wielder
	hit.weapon_id = definition.id
	hit.critical = MapRng.shared(MapRng.Stream.COMBAT).randf() < critical_chance_total()
	var multiplier: float = 1.0
	if wielder != null and wielder.has_method("outgoing_damage_multiplier"):
		multiplier = float(wielder.call("outgoing_damage_multiplier", hurtbox))
	#buff / 附魔的加成：固定加值加在基础伤害上，倍率乘在后面
	var flat_add: float = 0.0
	if wielder != null and wielder.has_method("read_stat"):
		flat_add = maxf(float(wielder.call("read_stat", &"damage_add")), 0.0)
		multiplier *= maxf(float(wielder.call("read_stat", &"damage_dealt")), 0.0)
	hit.damage = (definition.damage + flat_add + definition.enchant_damage()) * damage_scale * multiplier * (definition.critical_multiplier if hit.critical else 1.0)
	hit.position = hurtbox.global_position
	var direction: Vector2 = (hurtbox.global_position - wielder.global_position).normalized()
	if direction.is_zero_approx():
		direction = aim_direction
	hit.knockback = direction * definition.knockback
	if hurtbox.receive_hit(hit):
		_apply_enchant_effects(hurtbox, hit)
		hit_landed.emit(hit, hurtbox)
		_apply_on_hit_effects(hurtbox)


## 武器附魔：命中后把武器上的炼金属性逐个作用出去。
## 附魔效果在武器命中结算之后单独触发，不并入 hit.damage；
## 爆炸等 need_target = false 的属性会用自己的 use_effect 再生成一次伤害判定。
## need_target 的属性作用到被命中的实体，其余作用到命中点；
## enchant_target = WIELDER 的属性(治疗/恢复)作用到持武器的人自己。
func _apply_enchant_effects(hurtbox: CombatHurtbox, hit: CombatHit) -> void:
	if definition == null or definition.enchant_attributes.is_empty():
		return
	var point: Node2D = null
	for attribute: AlchemicalData in definition.enchant_attributes:
		if attribute == null:
			continue
		if attribute.need_target:
			var target: Node = wielder if attribute.enchant_target == AlchemicalData.EnchantTarget.WIELDER else hurtbox.get_parent()
			attribute.apply_weapon_enchant(target, hit)
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
