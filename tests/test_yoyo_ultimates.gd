extends "res://tests/test_yoyo_variants.gd"


func _setup_ultimate(base: SwarmYoyoDefinition, mode: int) -> void:
	var modified := base.duplicate(true) as SwarmYoyoDefinition
	modified.proc_chance = 1.0
	modified.apply_ultimate(mode)
	_fixture(modified)


func _run() -> void:
	var progress: Node = root.get_node("RunProgress")
	progress.reset()
	for id: StringName in [&"thunder_contract", &"thunder_core", &"thunder_beacon", &"hive_bomb", &"hive_migration"]:
		progress.reset()
		var card: UpgradeCard = UpgradePool.get_card(id)
		_check(card.rarity == UpgradeCard.Rarity.RARE and card.max_stacks == 1, "Ultimate is rare and single-stack")
		_check(progress.take_card(id), "Ultimate can be selected")
		for other: UpgradeCard in UpgradePool.candidates(progress.cards_taken, card.weapon_id, 1.0):
			_check(other.exclusive_group != card.exclusive_group, "Chosen group disappears from candidates")
		var built: WeaponDefinition = progress.build_weapon(THUNDER if card.weapon_id == &"thunder_yoyo" else HIVE)
		_check(built.validation_errors().is_empty(), "Ultimate weapon remains valid")
		_check((built.duplicate(true) as SwarmYoyoDefinition).ultimate != 0, "Ultimate survives attack snapshot")
	progress.reset()
	_check(progress.take_card(&"thunder_contract"), "Contract selected")
	_check(not progress.take_card(&"thunder_core") and not progress.take_card(&"thunder_beacon"), "Direct take cannot bypass mutual exclusion")
	_check(progress.take_card(&"hive_bomb"), "Other weapon has an independent ultimate slot")
	_check(not progress.take_card(&"hive_migration"), "Hive alternatives are exclusive")
	progress.reset()
	_check(progress.take_card(&"thunder_core"), "New run clears exclusive selection")
	progress.reset()

	_setup_ultimate(THUNDER, SwarmYoyoDefinition.Ultimate.CONTRACT)
	var primary := _target(Vector2(50, 0))
	await _sync_physics()
	var attack := _start(Vector2(50, 0)) as SwarmYoyoAttack
	attack._physics_process(0.2)
	_check(is_equal_approx(primary.current_health, 977.2), "Contract keeps 18 lightning damage with 4.8 contact damage")
	attack._physics_process(0.34)
	_check(is_equal_approx(primary.current_health, 977.2), "Contract slows repeat contacts")

	_setup_ultimate(THUNDER, SwarmYoyoDefinition.Ultimate.CORE)
	primary = _target(Vector2(50, 0))
	var edge := _target(Vector2(50, 55))
	await _sync_physics()
	attack = _start(Vector2(50, 0)) as SwarmYoyoAttack
	attack._physics_process(0.2)
	_check(primary.current_health == 988.0 and edge.current_health == 1000.0, "Core telegraphs before damage")
	_check(attack._storms.size() == 1 and attack._effect.effect_range == 60.0, "Core warning matches expanded radius")
	attack._physics_process(0.61)
	_check(edge.current_health == 955.0, "Core delayed strike deals 2.5 times damage")
	_check(attack._storms.is_empty() and not attack._storm_available(), "Core cooldown prevents another strike")

	_setup_ultimate(THUNDER, SwarmYoyoDefinition.Ultimate.BEACON)
	primary = _target(Vector2(50, 0))
	edge = _target(Vector2(50, 35))
	await _sync_physics()
	attack = _start(Vector2(50, 0)) as SwarmYoyoAttack
	attack._physics_process(0.2)
	attack._effect.proc_chance = 0.0
	attack._physics_process(0.51)
	_check(edge.current_health == 982.0, "Beacon first strike waits half a second")
	attack._complete()
	attack._physics_process(1.4)
	_check(edge.current_health == 946.0 and attack._storms.is_empty(), "Beacon completes exactly three strikes after return")

	_setup_ultimate(HIVE, SwarmYoyoDefinition.Ultimate.BOMB)
	primary = _target(Vector2(50, 0))
	await _sync_physics()
	attack = _start(Vector2(50, 0)) as SwarmYoyoAttack
	_controller.set_trigger_pressed(true)
	attack._physics_process(1.1)
	_check(attack._bees.is_empty(), "Bomb disables contact spawning")
	_controller.set_trigger_pressed(false)
	attack._physics_process(0.01)
	_check(attack._bees.size() == 8, "Charged release bursts eight bees")
	var origin: Vector2 = attack._bees[0]["position"]
	_check(origin.is_equal_approx(Vector2(50, 0)), "Bomb bursts at return origin")
	attack._physics_process(0.1)
	_check(attack._flight_done and not _controller.is_attacking() and attack._bees.size() == 8, "Returning ball leaves its bees alive")
	_controller.equip(THUNDER)
	_check(attack.is_queued_for_deletion(), "Switching weapons clears lingering effects")

	_setup_ultimate(HIVE, SwarmYoyoDefinition.Ultimate.BOMB)
	attack = _start(Vector2(50, 0)) as SwarmYoyoAttack
	_controller.set_trigger_pressed(true)
	attack._physics_process(0.2)
	_controller.set_trigger_pressed(false)
	attack._physics_process(0.01)
	_check(attack._bees.is_empty(), "Short taps cannot release a bomb")

	_setup_ultimate(HIVE, SwarmYoyoDefinition.Ultimate.MIGRATION)
	primary = _target(Vector2(50, 0))
	await _sync_physics()
	attack = _start(Vector2(50, 0)) as SwarmYoyoAttack
	attack._physics_process(0.2)
	_check(primary.current_health == 994.0, "Migration reduces only contact damage")
	attack._advance_bees(1.3)
	var before: float = primary.current_health
	_check(attack._bees.size() == 3 and before < 974.5, "Migrating bees survive and bite repeatedly")
	attack._advance_bees(0.01)
	_check(primary.current_health == before, "Bites have a cooldown")
	attack._complete()
	attack._physics_process(0.8)
	_check(primary.current_health < before and attack._bees.size() == 3, "Migration keeps biting after ball return")
	attack._physics_process(5.0)
	_check(attack._bees.is_empty(), "Migrating bees expire")
	_check(THUNDER.damage == 12.0 and HIVE.damage == 10.0, "Ultimate modifications preserve source resources")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_ultimates()
	_arena.free()
	await process_frame
	print("YOYO ULTIMATES: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _capture_ultimates() -> void:
	for mode: int in [SwarmYoyoDefinition.Ultimate.CORE, SwarmYoyoDefinition.Ultimate.BOMB]:
		_setup_ultimate(THUNDER if mode == SwarmYoyoDefinition.Ultimate.CORE else HIVE, mode)
		_arena.position = Vector2(400, 400)
		_target(Vector2(50, 0))
		await _sync_physics()
		var attack := _start(Vector2(50, 0)) as SwarmYoyoAttack
		_controller.set_trigger_pressed(true)
		attack._physics_process(0.2 if mode == SwarmYoyoDefinition.Ultimate.CORE else 1.1)
		if mode == SwarmYoyoDefinition.Ultimate.BOMB:
			_controller.set_trigger_pressed(false)
			attack._physics_process(0.01)
			attack._advance_bees(0.22)
			attack.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png("res://.godot/yoyo-ultimate-%d.png" % mode) == OK, "Ultimate screenshot saved")
