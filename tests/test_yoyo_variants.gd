extends "res://tests/test_weapons.gd"

const THUNDER = preload("res://resources/weapons/thunder_yoyo.tres")
const HIVE = preload("res://resources/weapons/hive_yoyo.tres")


func _run() -> void:
	for resource: SwarmYoyoDefinition in [THUNDER, HIVE]:
		_check(resource.validation_errors().is_empty(), "Variant validates")
		var item: WeaponData = load("res://resources/items/weapons/%s.tres" % resource.id)
		_check(item.weapon == resource and item.max_stack == 1, "Item links weapon")
		var scene: PackedScene = load(item.item_scene_path)
		var drop: Node = scene.instantiate()
		_check(drop is RigidBody2D, "Drop scene loads")
		drop.free()
		_fixture(resource)
		(_data as SwarmYoyoDefinition).proc_chance = 0.0
		var target := _target(Vector2(50, 0))
		await _sync_physics()
		var disabled := _start(Vector2(50, 0)) as SwarmYoyoAttack
		for index: int in 4:
			disabled._physics_process(0.34)
		_check(disabled._bees.is_empty() and disabled._strikes.is_empty(), "Zero chance never triggers")
		_check(target.current_health == 1000.0 - resource.damage * 4.0, "Zero chance preserves contact damage")

	_fixture(THUNDER)
	(_data as SwarmYoyoDefinition).proc_chance = 1.0
	var primary := _target(Vector2(50, 0), 2, 4, 2)
	var inside := _target(Vector2(50, 35), 2, 4, 2)
	var outside := _target(Vector2(50, 45))
	var friendly := _target(Vector2(50, 20), 1)
	var wrong_layer := _target(Vector2(50, 25), 2, 2)
	await _sync_physics()
	var attack := _start(Vector2(50, 0)) as SwarmYoyoAttack
	attack._physics_process(0.2)
	_check(primary.current_health == 970.0, "Lightning also damages the triggering target exactly once")
	_check(inside.current_health == 982.0, "Lightning hits targets inside the displayed disk once")
	_check(outside.current_health == 1000.0, "Lightning does not chain beyond its radius")
	_check(friendly.current_health == 1000.0 and wrong_layer.current_health == 1000.0, "AOE respects team and mask")
	_check(attack._strikes.size() == 1, "Guaranteed proc creates one visible strike without recursion")
	_check(attack._strikes[0]["position"] == Vector2(50, 0), "Strike is centered on the hit target")
	attack._physics_process(0.1)
	_check(inside.current_health == 982.0, "Fading disk does not apply repeated damage")
	_controller.set_aim(Vector2(-50, 0))
	attack._effect.proc_chance = 0.0
	attack._physics_process(0.3)
	_check(attack._strikes.is_empty(), "Lightning visual expires")

	_fixture(THUNDER)
	(_data as SwarmYoyoDefinition).proc_chance = 1.0
	primary = _target(Vector2(50, 0))
	primary.defense = 100.0
	await _sync_physics()
	attack = _start(Vector2(50, 0)) as SwarmYoyoAttack
	attack._physics_process(0.2)
	_check(attack._strikes.is_empty(), "Blocked contact cannot trigger lightning")

	_fixture(HIVE)
	(_data as SwarmYoyoDefinition).proc_chance = 1.0
	primary = _target(Vector2(50, 0))
	await _sync_physics()
	attack = _start(Vector2(50, 0)) as SwarmYoyoAttack
	attack._physics_process(0.2)
	_check(attack._bees.size() == 3, "Hive releases a burst of three bees")
	attack._physics_process(0.01)
	_check(primary.current_health == 990.0 and attack._bees.size() == 3, "Bees cannot instantly damage their spawn target")
	attack._advance_bees(0.2)
	_check(primary.current_health == 990.0, "Scatter phase cannot deal damage")
	var first_position: Vector2 = attack._bees[0]["position"]
	var second_position: Vector2 = attack._bees[1]["position"]
	_check(first_position.distance_to(second_position) > 20.0, "Burst visibly scatters in different directions")
	attack._advance_bees(1.2)
	_check(is_equal_approx(primary.current_health, 970.5), "All bees turn back, hit once and disappear")
	_check(attack._bees.is_empty(), "Bee hits cannot recursively spawn bees")
	attack._physics_process(0.34)
	_check(attack._bees.is_empty(), "Spawn cooldown limits bursts")
	attack._physics_process(0.34)
	_check(attack._bees.size() == 3, "Another eligible guaranteed hit releases a new burst")
	attack._spawn_bees(Vector2(50, 0))
	attack._spawn_bees(Vector2(50, 0))
	attack._spawn_bees(Vector2(50, 0))
	_check(attack._bees.size() == HIVE.bee_limit, "Bursts obey the total bee cap")
	primary.get_parent().position = Vector2(1000, 0)
	await _sync_physics()
	attack._advance_bees(3.0)
	_check(attack._bees.is_empty(), "Bees expire on long frames without a target")
	attack._spawn_bees(Vector2(50, 0))
	_controller.set_trigger_pressed(true)
	attack._physics_process(0.01)
	_controller.set_trigger_pressed(false)
	attack._physics_process(0.01)
	_check(attack._bees.is_empty(), "Release clears bees")
	_controller.cancel_attack()
	var health_before: float = primary.current_health
	attack._physics_process(1.0)
	_check(primary.current_health == health_before, "Cancelled variant cannot deal damage")
	var invalid := HIVE.duplicate(true) as SwarmYoyoDefinition
	invalid.proc_chance = 1.1
	_check(not invalid.validation_errors().is_empty(), "Invalid chance rejected")
	invalid.proc_chance = 0.5
	invalid.bee_lifetime = invalid.bee_scatter_seconds
	_check(not invalid.validation_errors().is_empty(), "Lifetime must allow homing after scatter")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_effects()
	_arena.free()
	await process_frame
	print("YOYO VARIANTS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _capture_effects() -> void:
	for data: SwarmYoyoDefinition in [THUNDER, HIVE]:
		_fixture(data)
		_arena.position = Vector2(220, 240)
		(_data as SwarmYoyoDefinition).proc_chance = 1.0
		for offset: Vector2 in [Vector2(50, 0), Vector2(50, 35), Vector2(50, 55)]:
			var target := _target(offset)
			var marker := Polygon2D.new()
			marker.polygon = PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)])
			marker.color = Color(0.8, 0.3, 0.3)
			target.get_parent().add_child(marker)
		await _sync_physics()
		var attack := _start(Vector2(50, 0)) as SwarmYoyoAttack
		attack._physics_process(0.2)
		if data == HIVE:
			attack._advance_bees(0.22)
			attack.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		var result: Error = screenshot.save_png("res://.godot/%s-preview.png" % data.id)
		_check(result == OK, "Effect screenshot saved")
