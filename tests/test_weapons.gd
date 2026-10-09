extends SceneTree

const LONGSWORD: SwingWeaponDefinition = preload("res://resources/weapons/longsword.tres")
const LONG_STAFF: DepthStrikeWeaponDefinition = preload("res://resources/weapons/long_staff.tres")
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
	var attack: WeaponAttack = _start()
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

	await _test_long_staff()

	_arena.free()
	await process_frame
	print("WEAPON TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_weapon_templates() -> void:
	var templates: Array[WeaponDefinition] = [
		load("res://resources/weapons/templates/swing_weapon_template.tres") as WeaponDefinition,
		load("res://resources/weapons/templates/staff_weapon_template.tres") as WeaponDefinition,
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
		_check((attack is SwingAttack) if is_sword else (attack is DepthStrikeAttack), "Template instantiates its matching attack behavior")
		attack._physics_process(1.0)
		_check(front.current_health == front.max_health - _data.damage, "Template copy deals its edited damage exactly once")
		_check(received.size() == 1 and received[0].weapon_id == _data.id, "Copied weapon reports its new ID on hit")
		_check((wide.current_health < wide.max_health) == is_sword, "Templates retain distinct sword fan and staff fan ranges")
		_check(not _controller.is_attacking(), "Template attack completes normally")
		_check(template.id == original_id and template.damage == original_damage, "Editing and attacking with a copy leaves its template unchanged")
		_check(sibling.id == original_id and sibling.damage == original_damage, "Other copies retain their independent values")


func _test_long_staff() -> void:
	_check(LONG_STAFF.validation_errors().is_empty(), "Long staff configuration is valid")
	for direction_index: int in range(8):
		_fixture(LONG_STAFF)
		var aim: Vector2 = Vector2.from_angle(float(direction_index) * TAU / 8.0)
		var front: HealthComponent = _target(aim * 35.0, 2, 4, 2)
		var behind: HealthComponent = _target(-aim * 24.0)
		var side: HealthComponent = _target(aim.rotated(deg_to_rad(45.0)) * 30.0)
		var fan_left: HealthComponent = _target(aim.rotated(deg_to_rad(-15.0)) * 28.0)
		var fan_right: HealthComponent = _target(aim.rotated(deg_to_rad(15.0)) * 28.0)
		var far: HealthComponent = _target(aim * 60.0)
		await _sync_physics()
		var attack: WeaponAttack = _start(aim)
		attack._physics_process(0.1)
		_check(front.current_health == front.max_health, "Staff windup cannot hit")
		_controller.set_aim(-aim)
		attack._physics_process(1.0)
		_check(front.current_health == front.max_health - LONG_STAFF.damage, "Depth stroke samples its mid-stroke reach and hits once in direction %d" % direction_index)
		_check(behind.current_health == behind.max_health, "Staff keeps selected direction when cursor moves")
		_check(side.current_health == side.max_health, "Staff misses targets outside the small fan")
		_check(fan_left.current_health == 980.0 and fan_right.current_health == 980.0, "Staff swing hits both sides of its small fan")
		_check(far.current_health == far.max_health, "Staff does not hit beyond its reach")

	_fixture(LONG_STAFF)
	(_data as DepthStrikeWeaponDefinition).reverse_strike = true
	var front: HealthComponent = _target(Vector2(35, 0))
	await _sync_physics()
	var attack: WeaponAttack = _start()
	_check(attack is DepthStrikeAttack, "Staff uses its own depth behavior, not the sword fan")
	attack._physics_process(1.0)
	_check(front.current_health == 980.0, "Reversing depth direction preserves forward aim and reach")

	_fixture(LONG_STAFF)
	front = _target(Vector2(30, 0))
	await _sync_physics()
	attack = _start()
	attack._physics_process(_data.windup_seconds + _data.active_seconds)
	_check(front.current_health == 980.0, "Staff active window deals damage")
	var recovery_target: HealthComponent = _target(Vector2(20, 0))
	await _sync_physics()
	attack._physics_process(_data.recovery_seconds)
	_check(recovery_target.current_health == 1000.0, "Staff returning from depth during recovery cannot hit")

	_fixture(LONG_STAFF)
	front = _target(Vector2(50, 0))
	await _sync_physics()
	attack = _start()
	attack._physics_process(_data.windup_seconds)
	_actor.position.x = 60.0
	attack._physics_process(_data.active_seconds)
	_check(front.current_health == 980.0, "Depth hit sweep includes actor translation")

	_fixture(LONG_STAFF)
	var swing: DepthStrikeAttack = _start() as DepthStrikeAttack
	swing._physics_process(_data.windup_seconds)
	var start_points: PackedVector2Array = swing.shaft.polygon
	var start_axis: Vector2 = (start_points[1] + start_points[2] - start_points[0] - start_points[3]) * 0.5
	var start_brightness: float = swing.shaft.color.r
	swing._physics_process(_data.active_seconds)
	var end_points: PackedVector2Array = swing.shaft.polygon
	var end_axis: Vector2 = (end_points[1] + end_points[2] - end_points[0] - end_points[3]) * 0.5
	_check(end_axis.length() > start_axis.length() * 1.3, "Staff grows visibly from far to near during the swing")
	_check(swing.shaft.color.r > start_brightness, "Staff brightens as it approaches the viewer")
	_check(is_equal_approx(absf(rad_to_deg(start_axis.angle_to(end_axis))), LONG_STAFF.arc_degrees), "Visible staff rotates through the configured small fan")

	var invalid: DepthStrikeWeaponDefinition = LONG_STAFF.duplicate(true) as DepthStrikeWeaponDefinition
	invalid.hit_width = 0.0
	_check(not invalid.validation_errors().is_empty(), "Staff rejects zero-width hit geometry")
	invalid.hit_width = 4.0
	invalid.near_pitch_degrees = 90.0
	_check(not invalid.validation_errors().is_empty(), "Staff rejects degenerate depth projection")
	invalid.near_pitch_degrees = LONG_STAFF.near_pitch_degrees
	invalid.arc_degrees = 100.0
	_check(not invalid.validation_errors().is_empty(), "Staff rejects an oversized fan")
