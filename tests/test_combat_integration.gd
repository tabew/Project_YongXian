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

func _use_hotbar_slot(player: PlayerCharacter, pos: int) -> void:
	# select_handy_slot() 在"选中的还是同一格"时直接返回 false、不发信号，
	# 装备是靠 handy_selection_changed 触发的，所以先挪开再选回来，保证一定会触发
	player.inventory.handy_selected = -1
	player.inventory.select_handy_slot(pos)
	player.inventory.use_handy_slot()
	await process_frame
	await process_frame


## 临时把一个物品模板登记进注册表，并先放进背包再放进快捷栏。
## 先 add_item 是必须的：handy_item_changed() 只从 inventory.get_item_data 里取模板
func _put_hotbar_item(inventory: Inventory, item_list: Node, pos: int, item: ItemData) -> void:
	item_list.templates.append(item)
	item_list.call("_build_table")
	inventory.clear_handy_slot(pos)
	inventory.add_item(item.id, 1)
	inventory.add_handy_slot(pos, item.id, 1)


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
	# ==========================================================================
	# ↓↓↓↓ 改动：武器不再自带，开局空手，装备一律走物品栏 ↓↓↓↓
	var inventory: Inventory = player.inventory
	var weapon_label: Label = world.get_node("GameHUD/HUD/WeaponLabel") as Label
	# 当前实现是"选中即装备"：起始选中是第1格（长剑），所以开局手里就是长剑
	_check(controller.equipped_weapon != null and controller.equipped_weapon.id == &"longsword", "Player starts with the longsword equipped from the hotbar")
	_check(not player.has_method("equip_next_weapon"), "Player exposes no direct weapon switch")
	_check(inventory.get_handy_slot_id(0) == 200, "Starting hotbar slot 1 holds the longsword")
	_check(inventory.get_handy_slot_id(1) == 201, "Starting hotbar slot 2 holds the staff")
	_check(weapon_label.text.contains(controller.equipped_weapon.display_name), "HUD shows the equipped weapon")

	# 走到长棍格：选中即装备（装备不再靠"用一次"）
	await _use_hotbar_slot(player, 1)
	_check(controller.equipped_weapon != null and controller.equipped_weapon.id == &"long_staff", "Selecting the next hotbar slot equips the staff")
	# ↑↑↑↑ 改动：用物品栏装备 ↑↑↑↑
	# ==========================================================================
	# 切回长剑，后面的用例按长剑节奏来
	await _use_hotbar_slot(player, 0)
	_check(controller.equipped_weapon != null and controller.equipped_weapon.id == &"longsword", "Selecting slot 1 equips the longsword again")

	# 溜溜球也按同一套接入物品栏：临时登记一个武器物品放进第 3 格，用完再收回去
	var yoyo_item_id: int = 202
	var yoyo_item: WeaponData = WeaponData.new()
	yoyo_item.id = yoyo_item_id
	yoyo_item.name = "测试溜溜球"
	yoyo_item.max_stack = 1
	yoyo_item.weapon = load("res://resources/weapons/yoyo.tres") as WeaponDefinition
	_put_hotbar_item(inventory, root.get_node("ItemListGlobal"), 2, yoyo_item)

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

	# ==========================================================================
	# ↓↓↓↓ 改动：长棍同样从物品栏第2格装上 ↓↓↓↓
	await _use_hotbar_slot(player, 1)
	_check(controller.equipped_weapon.id == &"long_staff", "Using the next hotbar slot equips the staff")
	_check(weapon_label.text.contains(controller.equipped_weapon.display_name), "HUD updates to the staff")
	# ↑↑↑↑ 改动：用物品栏装备长棍 ↑↑↑↑
	# ==========================================================================
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
	await _use_hotbar_slot(player, 0)
	_check(controller.equipped_weapon.id == &"longsword", "Switching through the hotbar goes back to the sword")
	_check(not controller.is_attacking(), "Switching from staff cancels the active swing")
	await create_timer(0.7).timeout
	_check(not controller.is_attacking(), "Switching while held requires a fresh mouse press")
	_mouse(false)

	# ==========================================================================
	# ↓↓↓↓ 改动：溜溜球的用例改成从物品栏第3格装备（协作者新增的机制保留） ↓↓↓↓
	await _use_hotbar_slot(player, 2)
	_check(controller.equipped_weapon != null and controller.equipped_weapon.id == &"yoyo", "Using the yoyo hotbar slot equips the yoyo")
	_check(weapon_label.text.contains(controller.equipped_weapon.display_name), "HUD updates to the yoyo")

	# 溜溜球：按住时球停在绳长上限持续命中，松手后立刻收回
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
	# ↑↑↑↑ 改动：溜溜球用例（结束）↑↑↑↑
	# ==========================================================================

	var template_copies: Array[WeaponDefinition] = [
		(load("res://resources/weapons/templates/swing_weapon_template.tres") as WeaponDefinition).duplicate(true) as WeaponDefinition,
		(load("res://resources/weapons/templates/staff_weapon_template.tres") as WeaponDefinition).duplicate(true) as WeaponDefinition,
	]
	for index: int in range(template_copies.size()):
		var copy: WeaponDefinition = template_copies[index]
		copy.id = StringName("loadout_copy_%d" % index)
		copy.display_name = "Template copy %d" % index
	var item_list: Node = root.get_node("ItemListGlobal")
	var item_ids: Array[int] = [230, 231]
	for index: int in range(template_copies.size()):
		var copy_item: WeaponData = WeaponData.new()
		copy_item.id = item_ids[index]
		copy_item.name = template_copies[index].display_name
		copy_item.max_stack = 1
		copy_item.weapon = template_copies[index]
		_put_hotbar_item(inventory, item_list, 2 + index, copy_item)
	for index: int in range(template_copies.size()):
		var copy: WeaponDefinition = template_copies[index]
		await _use_hotbar_slot(player, 2 + index)
		_check(controller.equipped_weapon == copy, "Template copy added as an item is reachable through the backpack")
		_check(weapon_label.text.contains(copy.display_name), "Template copy name appears in the HUD")
		_check((world.get_node("GameHUD/HUD/WeaponIcon") as TextureRect).texture == copy.icon, "Template copy icon appears in the HUD")
	await _use_hotbar_slot(player, 0)
	_check(controller.equipped_weapon != null and controller.equipped_weapon.id == &"longsword", "Hotbar slot 1 still equips the original sword")
	# 测试注入的物品和格子都收回去，后面的用例继续用干净的开局背包
	inventory.clear_handy_slot(2)
	item_list.templates.erase(item_list.get_template(yoyo_item_id))
	for index: int in range(template_copies.size()):
		inventory.clear_handy_slot(2 + index)
		item_list.templates.erase(item_list.get_template(item_ids[index]))
	item_list.call("_build_table")

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
