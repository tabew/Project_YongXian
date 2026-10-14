extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _capture: bool = false


func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _mouse(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2(640, 360)
	Input.parse_input_event(event)


func _dummy_in(world: Node) -> TrainingDummy:
	for child: Node in world.get_children():
		if child is TrainingDummy:
			return child as TrainingDummy
	return null


func _cycle_weapon(echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_Q
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.physical_keycode = KEY_Q
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _screenshot(filename: String) -> void:
	if not _capture or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory: String = ProjectSettings.globalize_path("res://.godot/combat-preview")
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	_check(error == OK, "Screenshot directory is writable")
	var frame: Image = root.get_texture().get_image()
	_check(frame != null and not frame.is_empty(), "Rendered viewport is nonempty")
	_check(frame.save_png(directory.path_join(filename)) == OK, "Screenshot saved")


func _capture_depth_poses(controller: WeaponController, reverse: bool) -> void:
	if not _capture or DisplayServer.get_name() == "headless":
		return
	var original: WeaponDefinition = controller.equipped_weapon
	var data: DepthStrikeWeaponDefinition = original.duplicate(true) as DepthStrikeWeaponDefinition
	data.reverse_strike = reverse
	controller.equip(data)
	controller.try_attack()
	var attack: DepthStrikeAttack
	for child: Node in controller.get_children():
		if child is DepthStrikeAttack and not child.is_queued_for_deletion():
			attack = child as DepthStrikeAttack
	attack.set_physics_process(false)
	var prefix: String = "staff_reverse" if reverse else "staff_depth"
	for phase: int in range(3):
		var time: float = data.windup_seconds + data.active_seconds * float(phase) * 0.5
		attack._physics_process(time - attack.elapsed)
		await _screenshot("%s_%d.png" % [prefix, phase])
	controller.equip(original)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 20261008)
	var scene: PackedScene = load("res://scenes/game/game_world.tscn") as PackedScene
	var world: Node2D = scene.instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	var player: PlayerCharacter = world.get_node("Player") as PlayerCharacter
	var controller: WeaponController = player.weapon_controller
	player.set_physics_process(false)
	(player.get_node("Camera2D") as Camera2D).position_smoothing_enabled = false
	var dummy: TrainingDummy = _dummy_in(world)
	_check(dummy != null, "World spawns a reachable training target")
	_check(controller.equipped_weapon.id == &"longsword", "Player starts with longsword")
	var weapon_label: Label = world.get_node("GameHUD/HUD/WeaponLabel") as Label
	_check(weapon_label.text.contains(controller.equipped_weapon.display_name), "HUD shows equipped weapon")
	await create_timer(0.8).timeout
	controller.set_aim(dummy.global_position - player.global_position)
	await _screenshot("idle.png")
	_mouse(true)
	await create_timer(0.17).timeout
	_check(controller.is_attacking(), "Mouse press reaches player attack input")
	await _screenshot("swing.png")
	_mouse(false)
	await create_timer(0.5).timeout
	_check(dummy.health.current_health < dummy.health.max_health, "Player sword damages world target")
	_check(not controller.is_attacking(), "Mouse release stops held attacks")

	await _cycle_weapon()
	_check(controller.equipped_weapon.id == &"long_staff", "Q equips the staff from the player loadout")
	_check(weapon_label.text.contains(controller.equipped_weapon.display_name), "HUD updates to the staff")
	await _cycle_weapon(true)
	_check(controller.equipped_weapon.id == &"long_staff", "Key repeat does not cycle repeatedly")
	var health_before_staff: float = dummy.health.current_health
	# The resized staff requires close range rather than the old 74-pixel reach.
	player.global_position = dummy.global_position - controller.aim_direction * 30.0
	controller.set_aim(dummy.global_position - player.global_position)
	_mouse(true)
	await create_timer(0.25).timeout
	_check(controller.is_attacking(), "Staff responds to mouse attack input")
	await _screenshot("long_staff_swing.png")
	_mouse(false)
	await create_timer(0.6).timeout
	_check(dummy.health.current_health < health_before_staff, "Staff damages the world target")
	await _capture_depth_poses(controller, false)
	await _capture_depth_poses(controller, true)
	_mouse(true)
	await create_timer(0.04).timeout
	await _cycle_weapon()
	_check(controller.equipped_weapon.id == &"yoyo", "Q equips the yoyo from the player loadout")
	_check(not controller.is_attacking(), "Switching from staff cancels the active swing")
	await create_timer(0.7).timeout
	_check(not controller.is_attacking(), "Switching while held requires a fresh mouse press")
	_mouse(false)

	# 溜溜球：按住时球停在绳长上限持续命中，松手后立刻收回。
	var yoyo_hits: Array[CombatHit] = []
	var count_yoyo_hit: Callable = func(hit: CombatHit, _amount: float) -> void: yoyo_hits.append(hit)
	dummy.health.damaged.connect(count_yoyo_hit)
	player.global_position = dummy.global_position - controller.aim_direction * 40.0
	controller.set_aim(dummy.global_position - player.global_position)
	_mouse(true)
	await create_timer(0.4).timeout
	_check(controller.is_attacking(), "Yoyo responds to mouse attack input")
	_check(not yoyo_hits.is_empty(), "Thrown yoyo damages the world target")
	await create_timer(0.8).timeout
	_check(controller.is_attacking(), "Holding the mouse keeps the yoyo out on its rope")
	await _screenshot("yoyo_throw.png")
	_mouse(false)
	await create_timer(0.4).timeout
	_check(not controller.is_attacking(), "Releasing the mouse reels the yoyo back")
	_check(yoyo_hits.size() >= 2, "A held yoyo lands repeated hits on the world target")
	dummy.health.damaged.disconnect(count_yoyo_hit)

	# 武器扩展后 loadout 变长：按「走完一圈并回到起点」验证轮换，不写死武器数量。
	var full_loadout: Array[WeaponDefinition] = player.weapon_loadout
	_check(full_loadout.size() >= 3, "Player loadout holds the sword, the staff, the yoyo and the extended weapons")
	var kept_ids: Array[StringName] = []
	for entry: WeaponDefinition in full_loadout:
		if entry != null:
			kept_ids.append(entry.id)
	for required_id: StringName in [&"longsword", &"long_staff", &"yoyo"]:
		_check(kept_ids.has(required_id), "Player loadout keeps %s" % required_id)
	var start_index: int = full_loadout.find(controller.equipped_weapon)
	_check(start_index >= 0, "Current weapon is part of the loadout")
	for step: int in range(1, full_loadout.size()):
		await _cycle_weapon()
		_check(controller.equipped_weapon == full_loadout[(start_index + step) % full_loadout.size()],
			"Q walks the whole loadout in order")
	await _cycle_weapon()
	_check(controller.equipped_weapon == full_loadout[start_index], "Q cycles back to the starting weapon")
	player.weapon_loadout = []
	_check(not player.equip_next_weapon(), "An empty loadout leaves equipment intact")
	player.weapon_loadout = [null, controller.equipped_weapon]
	_check(not player.equip_next_weapon(), "Null and current entries cannot reset an attack")
	player.weapon_loadout = full_loadout

	var template_copies: Array[WeaponDefinition] = [
		(load("res://resources/weapons/templates/swing_weapon_template.tres") as WeaponDefinition).duplicate(true) as WeaponDefinition,
		(load("res://resources/weapons/templates/staff_weapon_template.tres") as WeaponDefinition).duplicate(true) as WeaponDefinition,
		(load("res://resources/weapons/templates/yoyo_weapon_template.tres") as WeaponDefinition).duplicate(true) as WeaponDefinition,
	]
	player.weapon_loadout = full_loadout.duplicate()
	for index: int in range(template_copies.size()):
		var copy: WeaponDefinition = template_copies[index]
		copy.id = StringName("loadout_copy_%d" % index)
		copy.display_name = "Template copy %d" % index
		player.weapon_loadout.append(copy)
	# 副本追加在列表末尾：先走到第一个副本，再逐个验证三个副本都能被 Q 选中。
	var extended_loadout: Array[WeaponDefinition] = player.weapon_loadout
	var copy_start: int = extended_loadout.find(template_copies[0])
	_check(copy_start > 0, "Template copies are appended after the original loadout")
	var current_index: int = extended_loadout.find(controller.equipped_weapon)
	var steps_to_first_copy: int = posmod(copy_start - current_index, extended_loadout.size())
	for _step: int in range(steps_to_first_copy):
		await _cycle_weapon()
	for copy: WeaponDefinition in template_copies:
		_check(controller.equipped_weapon == copy, "Template copy added to loadout is reachable with Q")
		_check(weapon_label.text.contains(copy.display_name), "Template copy name appears in the HUD")
		_check((world.get_node("GameHUD/HUD/WeaponIcon") as TextureRect).texture == copy.icon, "Template copy icon appears in the HUD")
		await _cycle_weapon()
	_check(controller.equipped_weapon == extended_loadout[0], "Extended loadout cycles back to the original sword")
	player.weapon_loadout = full_loadout

	var blocker: Control = Control.new()
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	world.get_node("GameHUD/HUD").add_child(blocker)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	_check(blocker.get_global_rect().has_point(Vector2(640, 360)), "UI blocker covers the test cursor")
	_mouse(true)
	await create_timer(0.04).timeout
	_check(not controller.is_attacking(), "UI-consumed press does not start combat")
	_mouse(false)
	blocker.queue_free()
	await process_frame

	_mouse(true)
	await create_timer(0.04).timeout
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not controller.is_attacking(), "Losing application focus cancels combat")
	_mouse(false)
	await create_timer(0.55).timeout
	_check(not controller.is_attacking(), "Focus cancellation clears automatic repeat")

	controller.set_trigger_pressed(true)
	await physics_frame
	await physics_frame
	world.call("build_world", 20261009)
	_check(not controller.is_attacking(), "World regeneration cancels combat")
	dummy = _dummy_in(world)
	_check(dummy != null and dummy.health.current_health == dummy.health.max_health, "New world receives a fresh target")
	var target_count: int = 0
	for child: Node in world.get_children():
		if child is TrainingDummy:
			target_count += 1
	_check(target_count == 1, "Regeneration does not accumulate training targets")
	_check(controller.weapon_changed.get_connections().size() == 1, "Rebinding HUD does not duplicate weapon subscriptions")

	if _capture and DisplayServer.get_name() != "headless":
		root.size = Vector2i(960, 540)
		await create_timer(0.5).timeout
		await _screenshot("compact.png")
	world.set("spawn_training_dummy", false)
	world.call("build_world", 20261010)
	_check(_dummy_in(world) == null, "Training target is optional")

	# 炼金升级 / 遗物接线：暴击率注入武器，炼金瞬间给无敌。
	player.alchemy_station.add_relic(&"crit_eye")
	player.alchemy_station.add_upgrade(&"brew_invuln")
	player._physics_process(0.0)
	_check(is_equal_approx(controller.critical_chance_bonus, 0.15), "暴击之眼注入武器控制器")
	player.alchemy_station.combo_activated.emit(player.alchemy_station.active_combo())
	_check(is_equal_approx(player.invulnerable_remaining, 0.30), "炼金瞬间获得 0.3 秒无敌")
	var health_before_invuln: int = player.health
	player.take_damage(5)
	_check(player.health == health_before_invuln, "无敌期间免疫伤害")
	player.invulnerable_remaining = 0.0
	player.take_damage(5)
	_check(player.health == health_before_invuln - 5, "无敌结束后恢复受伤")

	world.queue_free()
	await process_frame
	await process_frame
	print("COMBAT INTEGRATION: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
