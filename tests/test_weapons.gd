extends SceneTree

const LONGSWORD: SwingWeaponDefinition = preload("res://resources/weapons/longsword.tres")
const SPEAR: SpearWeaponDefinition = preload("res://resources/weapons/spear.tres")
const YOYO: YoyoWeaponDefinition = preload("res://resources/weapons/yoyo.tres")
const DUMMY: PackedScene = preload("res://scenes/combat/training_dummy.tscn")

var _failures: int = 0
var _checks: int = 0
var _arena: Node2D
var _actor: Node2D
var _controller: WeaponController
var _data: WeaponDefinition


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _fixture(data: WeaponDefinition = LONGSWORD) -> void:
	if is_instance_valid(_arena):
		_arena.free()
	_arena = Node2D.new()
	root.add_child(_arena)
	_actor = Node2D.new()
	_arena.add_child(_actor)
	_controller = WeaponController.new()
	_actor.add_child(_controller)
	_controller.set_physics_process(false)
	_data = data.duplicate(true) as WeaponDefinition
	_data.critical_chance = 0.0
	_check(_controller.equip(_data), "Weapon equips")


func _target(at: Vector2, team: int = 2, layer: int = 4, boxes: int = 1) -> HealthComponent:
	var target: Node2D = Node2D.new()
	target.position = at
	var health: HealthComponent = HealthComponent.new()
	health.max_health = 1000.0
	target.add_child(health)
	for index: int in range(boxes):
		var hurtbox: CombatHurtbox = CombatHurtbox.new()
		hurtbox.health = health
		hurtbox.team = team
		hurtbox.collision_layer = layer
		hurtbox.collision_mask = 0
		var shape_node: CollisionShape2D = CollisionShape2D.new()
		var shape: CircleShape2D = CircleShape2D.new()
		shape.radius = 3.0
		shape_node.shape = shape
		hurtbox.position.y = float(index)
		hurtbox.add_child(shape_node)
		target.add_child(hurtbox)
	_arena.add_child(target)
	return health


func _sync_physics() -> void:
	await physics_frame
	await physics_frame


func _start(aim: Vector2 = Vector2.RIGHT) -> WeaponAttack:
	_controller.set_aim(aim)
	_check(_controller.try_attack(), "Attack starts")
	return _current_attack()


func _current_attack() -> WeaponAttack:
	for child: Node in _controller.get_children():
		if child is WeaponAttack and not child.is_queued_for_deletion():
			child.set_physics_process(false)
			return child as WeaponAttack
	return null


func _run() -> void:
	_check(LONGSWORD.validation_errors().is_empty(), "Longsword resource is valid")
	await _test_weapon_templates()
	_check(is_equal_approx(LONGSWORD.attacks_per_second(), 2.0), "Timings produce two attacks per second")
	_fixture()
	var front: HealthComponent = _target(Vector2(35, 0), 2, 4, 2)
	var second: HealthComponent = _target(Vector2(25, 20))
	var behind: HealthComponent = _target(Vector2(-35, 0))
	var far: HealthComponent = _target(Vector2(70, 0))
	var friendly: HealthComponent = _target(Vector2(30, 0), 1)
	var wrong_layer: HealthComponent = _target(Vector2(30, 0), 2, 2)
	await _sync_physics()
	var orphans_before: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var attack: WeaponAttack = _start()
	_check(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans_before, "Starting an attack never leaks an unattached instance")
	attack._physics_process(0.07)
	_check(front.current_health == 1000.0, "Windup causes no damage")
	_check(not _controller.try_attack(), "Cannot stack attacks during a swing")
	attack._physics_process(0.19)
	_check(front.current_health == 982.0, "One hit across multiple hurtboxes and sweep samples")
	_check(second.current_health == 982.0, "Swing cleaves a second target")
	_check(behind.current_health == 1000.0, "Target behind the arc is safe")
	_check(far.current_health == 1000.0, "Target outside blade reach is safe")
	_check(friendly.current_health == 1000.0, "Same team is ignored")
	_check(wrong_layer.current_health == 1000.0, "Hit mask filters other layers")
	var recovery_target: HealthComponent = _target(Vector2(10, 35))
	await _sync_physics()
	attack._physics_process(0.2)
	_check(recovery_target.current_health == 1000.0, "Recovery causes no damage to newly entered targets")
	_check(not _controller.is_attacking(), "Attack finishes after recovery")
	_check(not _controller.try_attack(), "Reuse delay blocks immediate attack")
	_controller._physics_process(0.041)
	attack = _start()
	attack._physics_process(1.0)
	_check(front.current_health == 964.0, "Next swing may hit the same target again")

	_fixture()
	var left: HealthComponent = _target(Vector2(-35, 0))
	await _sync_physics()
	attack = _start(Vector2.LEFT)
	_controller.set_aim(Vector2.RIGHT)
	attack._physics_process(1.0)
	_check(left.current_health == 982.0, "Left-facing swing works and aim stays locked")
	_fixture()
	var above: HealthComponent = _target(Vector2(0, -35))
	await _sync_physics()
	attack = _start(Vector2.UP)
	attack._physics_process(1.0)
	_check(above.current_health == 982.0, "Vertical mouse aiming works")

	_fixture()
	_data.active_seconds = 0.005
	_data.windup_seconds = 0.0
	_data.recovery_seconds = 0.0
	front = _target(Vector2(35, 0))
	await _sync_physics()
	attack = _start()
	attack._physics_process(0.1)
	_check(front.current_health == 982.0, "An entire active phase within one frame still hits")

	_fixture()
	front = _target(Vector2(70, 0))
	await _sync_physics()
	attack = _start()
	_actor.position.x = 100.0
	attack._physics_process(0.3)
	_check(front.current_health == 982.0, "Sweep includes wielder translation between frames")

	_fixture()
	front = _target(Vector2(35, 0))
	await _sync_physics()
	attack = _start()
	_data.damage = 99.0
	attack._physics_process(1.0)
	_check(front.current_health == 982.0, "Current swing uses an immutable stat snapshot")
	_check(LONGSWORD.damage == 18.0, "Shared source resource is unchanged")

	_fixture()
	front = _target(Vector2(35, 0))
	var self_health: HealthComponent = _target(Vector2(30, 0))
	(self_health.get_parent() as Node2D).reparent(_actor)
	await _sync_physics()
	attack = _start()
	_controller.cancel_attack()
	attack._physics_process(1.0)
	_check(front.current_health == 1000.0, "Cancelled attack cannot hit")
	attack = _start()
	attack._physics_process(1.0)
	_check(self_health.current_health == 1000.0, "Self-hits are rejected even with a different team value")

	_fixture()
	_data.critical_chance = 1.0
	front = _target(Vector2(35, 0))
	front.defense = 5.0
	await _sync_physics()
	var received: Array[CombatHit] = []
	front.damaged.connect(func(hit: CombatHit, _amount: float) -> void: received.append(hit))
	attack = _start()
	attack._physics_process(1.0)
	_check(front.current_health == 969.0, "Critical multiplier applies before defense")
	_check(received.size() == 1 and received[0].critical, "Hit carries critical flag")
	_check(received.size() == 1 and received[0].knockback.is_equal_approx(Vector2(110, 0)), "Hit carries configured directional knockback")
	var lethal: CombatHit = CombatHit.new()
	lethal.damage = 2000.0
	_check(front.receive_hit(lethal) and not front.is_alive(), "Lethal damage is clamped to zero health")
	_check(not front.receive_hit(lethal), "Dead target rejects additional hits")
	front.reset()
	_check(front.current_health == front.max_health, "Health reset restores target")

	_fixture()
	_data.auto_repeat = false
	_controller.set_trigger_pressed(true)
	_controller._physics_process(0.01)
	attack = _current_attack()
	_check(attack != null, "Press starts semi-automatic weapon")
	attack._physics_process(1.0)
	_controller._physics_process(1.0)
	_check(not _controller.is_attacking(), "Held semi-automatic weapon does not repeat")
	_controller.set_trigger_pressed(false)
	_controller.set_trigger_pressed(true)
	_controller.set_trigger_pressed(false)
	_controller._physics_process(0.01)
	_check(_controller.is_attacking(), "Fast press/release between physics frames is not lost")
	_controller.cancel_attack()
	_data.auto_repeat = true
	_controller.set_trigger_pressed(true)
	_controller._physics_process(0.01)
	_current_attack()._physics_process(1.0)
	_controller._physics_process(1.0)
	_check(_controller.is_attacking(), "Held automatic weapon repeats after cooldown")
	_controller.set_trigger_pressed(false)
	_current_attack()._physics_process(1.0)
	_controller._physics_process(1.0)
	_check(not _controller.is_attacking(), "Release stops automatic attacks")

	var invalid: SwingWeaponDefinition = _data.duplicate(true) as SwingWeaponDefinition
	invalid.active_seconds = 0.0
	_check(not invalid.validation_errors().is_empty(), "Invalid timing is rejected")
	_check(not _controller.equip(invalid) and _controller.equipped_weapon == _data, "Failed equip preserves previous weapon")
	invalid.active_seconds = 0.1
	invalid.blade_inset = invalid.blade_length
	_check(not invalid.validation_errors().is_empty(), "Invalid blade geometry is rejected")
	attack = _start()
	_check(_controller.equip(null) and not _controller.is_attacking(), "Unequip cancels current attack")
	_check(not _controller.try_attack(), "Unarmed controller cannot attack")

	var alternate: WeaponDefinition = WeaponDefinition.new()
	alternate.attack_scene = load("res://tests/fixtures/alternate_attack.tscn") as PackedScene
	_check(_controller.equip(alternate), "A different attack type equips without controller changes")
	attack = _start()
	_check(attack.get_meta("alternate_started", false), "Different behavior initialization is dispatched")
	attack._physics_process(1.0)
	_check(not _controller.is_attacking(), "Different behavior uses shared lifecycle")

	_fixture()
	var crowd: Array[HealthComponent] = []
	for index: int in range(40):
		crowd.append(_target(Vector2(34 + index % 3, index % 2)))
	await _sync_physics()
	attack = _start()
	attack._physics_process(1.0)
	var all_hit: bool = true
	for health: HealthComponent in crowd:
		all_hit = all_hit and health.current_health == 982.0
	_check(all_hit, "Crowds larger than physics query batch are all hit once")

	_fixture()
	var dummy: TrainingDummy = DUMMY.instantiate() as TrainingDummy
	dummy.position = Vector2(35, 0)
	dummy.respawn_seconds = 0.01
	_arena.add_child(dummy)
	dummy.set_physics_process(false)
	var dummy_hit: CombatHit = CombatHit.new()
	dummy_hit.damage = 1000.0
	dummy_hit.knockback = Vector2(110, 0)
	dummy.health.receive_hit(dummy_hit)
	_check(not dummy.sprite.visible and not dummy.health.is_alive(), "Training dummy disappears on death")
	dummy._physics_process(0.02)
	_check(dummy.sprite.visible and dummy.health.current_health == 100.0, "Training dummy respawns with full health")

	await _test_spear()
	await _test_yoyo()

	_arena.free()
	await process_frame
	print("WEAPON TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_weapon_templates() -> void:
	var templates: Array[WeaponDefinition] = [
		load("res://resources/weapons/templates/swing_weapon_template.tres") as WeaponDefinition,
		load("res://resources/weapons/templates/spear_weapon_template.tres") as WeaponDefinition,
	]
	for template: WeaponDefinition in templates:
		_check(template != null and template.validation_errors().is_empty(), "Template is ready to equip")
		var original_id: StringName = template.id
		var original_damage: float = template.damage
		var sibling: WeaponDefinition = template.duplicate(true) as WeaponDefinition
		_fixture(template)
		_data.id = StringName("custom_" + str(original_id))
		_data.display_name = "Custom template copy"
		_data.damage = original_damage + 7.0
		_check(_controller.equip(_data), "Template copy equips after independently editing its stats")
		var front: HealthComponent = _target(Vector2(30, 0), 2, 4, 2)
		var wide: HealthComponent = _target(Vector2.from_angle(deg_to_rad(50.0)) * 25.0)
		var received: Array[CombatHit] = []
		front.damaged.connect(func(hit: CombatHit, _amount: float) -> void: received.append(hit))
		await _sync_physics()
		var attack: WeaponAttack = _start()
		var is_sword: bool = template is SwingWeaponDefinition
		_check((attack is SwingAttack) if is_sword else (attack is SpearAttack), "Template instantiates its matching attack behavior")
		attack._physics_process(1.0)
		_check(front.current_health == front.max_health - _data.damage, "Template copy deals its edited damage exactly once")
		_check(received.size() == 1 and received[0].weapon_id == _data.id, "Copied weapon reports its new ID on hit")
		_check((wide.current_health < wide.max_health) == is_sword, "Templates retain distinct sword fan and spear thrust ranges")
		_check(not _controller.is_attacking(), "Template attack completes normally")
		_check(template.id == original_id and template.damage == original_damage, "Editing and attacking with a copy leaves its template unchanged")
		_check(sibling.id == original_id and sibling.damage == original_damage, "Other copies retain their independent values")


func _test_spear() -> void:
	_check(SPEAR.validation_errors().is_empty(), "Spear configuration is valid")
	for direction_index: int in range(8):
		_fixture(SPEAR)
		var aim: Vector2 = Vector2.from_angle(float(direction_index) * TAU / 8.0)
		var front: HealthComponent = _target(aim * 30.0, 2, 4, 2)
		var tip: HealthComponent = _target(aim * 68.0)
		var behind: HealthComponent = _target(-aim * 24.0)
		var side: HealthComponent = _target(aim * 30.0 + aim.orthogonal() * 12.0)
		var far: HealthComponent = _target(aim * 80.0)
		var friendly: HealthComponent = _target(aim * 50.0, 1)
		var wrong_layer: HealthComponent = _target(aim * 50.0, 2, 2)
		await _sync_physics()
		var attack: SpearAttack = _start(aim) as SpearAttack
		_check(attack != null, "Spear uses the thrust attack")
		attack._physics_process(SPEAR.windup_seconds * 0.5)
		_check(front.current_health == front.max_health, "Spear windup cannot hit")
		_controller.set_aim(-aim)
		attack._physics_process(1.0)
		_check(front.current_health == front.max_health - SPEAR.damage, "Each thrust deduplicates multiple hurtboxes in direction %d" % direction_index)
		_check(tip.current_health == tip.max_health - SPEAR.damage, "A skipped frame still reaches and pierces the distant target")
		_check(behind.current_health == behind.max_health, "Thrust keeps the cursor direction locked")
		_check(side.current_health == side.max_health, "Spear misses enemies alongside the narrow thrust")
		_check(far.current_health == far.max_health, "Spear cannot hit beyond its tip")
		_check(friendly.current_health == friendly.max_health and wrong_layer.current_health == wrong_layer.max_health, "Spear filters teams and collision layers")

	_fixture(SPEAR)
	var attack: SpearAttack = _start(Vector2.UP) as SpearAttack
	attack._physics_process(SPEAR.windup_seconds)
	var start_position: Vector2 = attack.shaft.position
	var start_rotation: float = attack.shaft.rotation
	var start_scale: Vector2 = attack.shaft.scale
	attack._physics_process(SPEAR.active_seconds * SpearAttack.EXTEND_RATIO)
	_check(is_equal_approx(attack._tip(attack.elapsed).length(), 72.0), "Visual tip and damage reach extend to 72 pixels")
	_check(attack.shaft.position.distance_to(start_position) > 30.0, "Spear visibly slides forward")
	_check(is_equal_approx(attack.shaft.rotation, start_rotation) and attack.shaft.scale == start_scale, "Thrust never rotates through a fan or changes scale")
	var returning_target: HealthComponent = _target(Vector2.UP * 45.0)
	await _sync_physics()
	attack._physics_process(SPEAR.attack_duration())
	_check(returning_target.current_health == returning_target.max_health, "Retraction and recovery cannot damage new targets")

	_fixture(SPEAR)
	var moving_target: HealthComponent = _target(Vector2(100, 0))
	await _sync_physics()
	attack = _start() as SpearAttack
	attack._physics_process(SPEAR.windup_seconds)
	_actor.position.x = 60.0
	attack._physics_process(SPEAR.active_seconds * SpearAttack.EXTEND_RATIO)
	_check(moving_target.current_health == moving_target.max_health - SPEAR.damage, "Thrust sweep includes wielder translation")

	for single_frame: bool in [false, true]:
		_fixture(SPEAR)
		UpgradePool.apply_weapon_cards(_data, {&"spear_flurry": 1})
		var target: HealthComponent = _target(Vector2(60, 0), 2, 4, 3)
		await _sync_physics()
		attack = _start() as SpearAttack
		if single_frame:
			attack._physics_process(1.0)
		else:
			for frame: int in 70:
				attack._physics_process(0.01)
		_check(is_equal_approx(target.current_health, target.max_health - SPEAR.damage * 0.8 * 2.0), "Flurry hits exactly once per thrust at either frame rate")

	_fixture(SPEAR)
	UpgradePool.apply_weapon_cards(_data, {&"spear_reach": 1})
	var distant: HealthComponent = _target(Vector2(90, 0))
	await _sync_physics()
	attack = _start() as SpearAttack
	attack._physics_process(1.0)
	_check(distant.current_health == distant.max_health - SPEAR.damage, "Reach upgrade extends actual collision reach")

	_fixture(SPEAR)
	var cancelled_target: HealthComponent = _target(Vector2(50, 0))
	await _sync_physics()
	attack = _start() as SpearAttack
	_controller.cancel_attack()
	attack._physics_process(1.0)
	_check(cancelled_target.current_health == cancelled_target.max_health, "Cancelled thrust cannot hit")

	var invalid: SpearWeaponDefinition = SPEAR.duplicate(true) as SpearWeaponDefinition
	invalid.hit_width = 0.0
	_check(not invalid.validation_errors().is_empty(), "Spear rejects zero-width hit geometry")
	invalid.hit_width = SPEAR.hit_width
	invalid.pullback_distance = invalid.hand_distance + 1.0
	_check(not invalid.validation_errors().is_empty(), "Spear rejects a grip pulled behind the wielder")
	invalid.pullback_distance = SPEAR.pullback_distance
	invalid.thrust_count = 0
	_check(not invalid.validation_errors().is_empty(), "Spear rejects an empty thrust sequence")

func _test_yoyo() -> void:
	_check(YOYO.validation_errors().is_empty(), "Yoyo configuration is valid")

	# 指针在攻击范围内：球停在指针处，指针之外的敌人打不到。
	_fixture(YOYO)
	var at_cursor: HealthComponent = _target(Vector2(50, 0), 2, 4, 2)
	var past_cursor: HealthComponent = _target(Vector2(78, 0))
	var behind: HealthComponent = _target(Vector2(-60, 0))
	await _sync_physics()
	var attack: WeaponAttack = _start(Vector2(50, 0))
	_check(attack is YoyoAttack, "Yoyo uses its own flight behavior, not a swing")
	var ball: YoyoAttack = attack as YoyoAttack
	attack._physics_process(0.05)
	_check(at_cursor.current_health == 1000.0, "Yoyo windup cannot hit")
	attack._physics_process(0.2)
	_check(is_equal_approx(ball._distance, 50.0), "Ball rests exactly on the cursor when it is inside the rope length")
	_check(at_cursor.current_health == 1000.0 - _data.damage, "Cursor-positioned ball hits the target under it")
	_check(past_cursor.current_health == 1000.0, "Ball never travels past the cursor")
	_check(behind.current_health == 1000.0, "Yoyo stays on the aimed side")

	# 指针超出绳长：球贴在边界上。
	_fixture(YOYO)
	var edge: HealthComponent = _target(Vector2(80, 0), 2, 4, 2)
	var unreachable: HealthComponent = _target(Vector2(200, 0))
	var friendly: HealthComponent = _target(Vector2(80, 0), 1)
	var wrong_layer: HealthComponent = _target(Vector2(80, 0), 2, 2)
	var hits: Array[CombatHit] = []
	edge.damaged.connect(func(hit: CombatHit, _amount: float) -> void: hits.append(hit))
	await _sync_physics()
	attack = _start(Vector2(200, 0))
	attack._physics_process(0.3)
	_check(is_equal_approx((attack as YoyoAttack)._distance, _data.max_range), "Ball stops at the rope boundary when the cursor is out of range")
	_check(hits.size() == 1 and edge.current_health == 1000.0 - _data.damage, "Boundary ball hits what it touches")
	_check(hits[0].weapon_id == _data.id, "Yoyo reports its own weapon id")
	_check(unreachable.current_health == 1000.0, "Boundary ball cannot reach past the rope length")
	_check(friendly.current_health == 1000.0, "Yoyo ignores the same team")
	_check(wrong_layer.current_health == 1000.0, "Hit mask filters other layers")
	attack._physics_process(0.1)
	_check(hits.size() == 1, "Repeat hits respect the invulnerability interval")
	attack._physics_process(_data.hit_interval)
	_check(hits.size() == 2, "A parked yoyo keeps damaging the same target")

	# 按住维持，松手立刻收回。
	_controller.set_trigger_pressed(true)
	attack._physics_process(0.05)
	_check(_controller.is_attacking() and (attack as YoyoAttack)._phase == YoyoAttack.Phase.FOLLOW, "Holding keeps the ball out on its rope")
	_controller.set_trigger_pressed(false)
	attack._physics_process(0.05)
	_check((attack as YoyoAttack)._phase == YoyoAttack.Phase.RETURN, "Releasing starts the reel-in")
	attack._physics_process(1.0)
	_check(not _controller.is_attacking(), "Releasing reels the yoyo back and ends the throw")
	_check(not _controller.try_attack(), "Reuse delay blocks an immediate second throw")

	# 指针换边时球跟着走，速度受 follow_speed 限制。
	_fixture(YOYO)
	var left: HealthComponent = _target(Vector2(-40, 0), 2, 4, 2)
	await _sync_physics()
	attack = _start(Vector2(8, 0))
	attack._physics_process(0.2)
	_check(left.current_health == 1000.0, "Ball has not crossed to the other side yet")
	_controller.set_aim(Vector2(-40, 0))
	attack._physics_process(0.02)
	_check((attack as YoyoAttack)._direction.x < 0.0, "Ball turns toward the new cursor position")
	_check(left.current_health == 1000.0, "Limited follow speed means the ball has not arrived yet")
	attack._physics_process(0.1)
	_check(left.current_health == 1000.0 - _data.damage, "Ball follows the cursor across the wielder")

	# 没有按住过（AI 或测试直接出手）时，球滞空到有效期结束再自己回来。
	_fixture(YOYO)
	attack = _start(Vector2(60, 0))
	attack._physics_process(_data.windup_seconds + 0.2)
	_check(is_equal_approx((attack as YoyoAttack)._distance, 60.0), "Unheld yoyo still reaches the cursor")
	attack._physics_process(_data.active_seconds)
	_check(not _controller.is_attacking(), "An unheld yoyo reels itself in once the active window ends")

	var template: YoyoWeaponDefinition = load("res://resources/weapons/templates/yoyo_weapon_template.tres") as YoyoWeaponDefinition
	_check(template != null and template.validation_errors().is_empty(), "Yoyo template is ready to equip")
	_fixture(template)
	_data.id = &"custom_yoyo"
	_data.damage = 25.0
	_check(_controller.equip(_data), "Yoyo template copy equips after editing its stats")
	var copy_target: HealthComponent = _target(Vector2(50, 0), 2, 4, 2)
	await _sync_physics()
	attack = _start(Vector2(50, 0))
	attack._physics_process(1.0)
	_check(copy_target.current_health == 975.0, "Yoyo template copy deals its edited damage")
	_check(template.damage == 12.0 and template.id == &"new_yoyo_weapon", "Editing a copy leaves the yoyo template unchanged")

	var invalid: YoyoWeaponDefinition = YOYO.duplicate(true) as YoyoWeaponDefinition
	invalid.max_range = invalid.hand_distance
	_check(not invalid.validation_errors().is_empty(), "Yoyo rejects a rope shorter than the hand distance")
	invalid.max_range = 84.0
	invalid.recovery_seconds = 0.05
	_check(not invalid.validation_errors().is_empty(), "Yoyo requires the recovery to cover the return")
	invalid.recovery_seconds = 0.3
	invalid.hit_interval = 0.0
	_check(not invalid.validation_errors().is_empty(), "Yoyo rejects a zero repeat interval")
