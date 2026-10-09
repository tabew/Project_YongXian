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
	_check(controller.equipped_weapon.id == &"longsword", "Q cycles back to the sword")
	_check(not controller.is_attacking(), "Switching from staff cancels the active swing")
	await create_timer(0.7).timeout
	_check(not controller.is_attacking(), "Switching while held requires a fresh mouse press")
	_mouse(false)
	await _cycle_weapon()
	var full_loadout: Array[WeaponDefinition] = player.weapon_loadout
	player.weapon_loadout = []
	_check(not player.equip_next_weapon(), "An empty loadout leaves equipment intact")
	player.weapon_loadout = [null, controller.equipped_weapon]
	_check(not player.equip_next_weapon(), "Null and current entries cannot reset an attack")
	player.weapon_loadout = full_loadout

	var template_copies: Array[WeaponDefinition] = [
		(load("res://resources/weapons/templates/swing_weapon_template.tres") as WeaponDefinition).duplicate(true) as WeaponDefinition,
		(load("res://resources/weapons/templates/staff_weapon_template.tres") as WeaponDefinition).duplicate(true) as WeaponDefinition,
	]
	player.weapon_loadout = full_loadout.duplicate()
	for index: int in range(template_copies.size()):
		var copy: WeaponDefinition = template_copies[index]
		copy.id = StringName("loadout_copy_%d" % index)
		copy.display_name = "Template copy %d" % index
		player.weapon_loadout.append(copy)
	for copy: WeaponDefinition in template_copies:
		await _cycle_weapon()
		_check(controller.equipped_weapon == copy, "Template copy added to loadout is reachable with Q")
		_check(weapon_label.text.contains(copy.display_name), "Template copy name appears in the HUD")
		_check((world.get_node("GameHUD/HUD/WeaponIcon") as TextureRect).texture == copy.icon, "Template copy icon appears in the HUD")
	await _cycle_weapon()
	_check(controller.equipped_weapon == full_loadout[0], "Extended loadout cycles back to the original sword")
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
	world.queue_free()
	await process_frame
	await process_frame
	print("COMBAT INTEGRATION: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
