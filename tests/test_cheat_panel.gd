extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _capture: bool = false
var _panel: CheatPanel


func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _tap(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _search(text: String) -> void:
	_panel._search.text = text
	_panel._search.text_changed.emit(text)


func _row_count() -> int:
	return _panel._list.get_root().get_child_count()


func _layout_checks() -> void:
	await process_frame
	await process_frame
	var bounds: Rect2 = _panel._panel.get_global_rect()
	_check(_panel.get_viewport_rect().encloses(bounds), "Debug window fits the viewport")
	for control: Control in [_panel._search, _panel._filter, _panel._list, _panel._details, _panel._amount, _panel._apply, _panel._remove, _panel._bulk, _panel._status]:
		if control.is_visible_in_tree():
			_check(bounds.encloses(control.get_global_rect()), "%s stays inside the window" % control.get_class())
	_check(_panel._list.get_global_rect().end.y <= _panel._details.get_global_rect().position.y, "Details never overlap the list")


func _screenshot(filename: String) -> void:
	if not _capture or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory: String = ProjectSettings.globalize_path("res://.godot/cheat-preview")
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Preview directory is writable")
	var frame: Image = root.get_texture().get_image()
	_check(frame != null and not frame.is_empty(), "Debug panel renders a nonempty frame")
	_check(frame.save_png(directory.path_join(filename)) == OK, "Debug preview saved")


func _run() -> void:
	Engine.max_fps = 90
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").call("start_new_world", 20261008)
	var world: Node2D = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	await process_frame
	await process_frame
	_panel = world.get_node("GameHUD/CheatPanel") as CheatPanel
	var progress: Node = root.get_node("RunProgress")
	var registry: Node = root.get_node("ItemListGlobal")
	var inventory: Inventory = world.player.inventory
	var controller: WeaponController = world.player.weapon_controller
	var upgrades: UpgradePanel = world.get_node("GameHUD/UpgradePanel") as UpgradePanel
	var manager: UpgradeManager = world.get_node("GameHUD/UpgradeManager") as UpgradeManager
	_check(_panel != null and not _panel.visible, "Debug panel starts closed")
	_check(InputMap.event_is_action(_key_event(KEY_F1), "debug_items"), "F1 is bound to supplies")
	_check(InputMap.event_is_action(_key_event(KEY_F2), "debug_buffs"), "F2 is bound to buffs")
	inventory.select_handy_slot(1)
	controller.set_trigger_pressed(true)
	controller._physics_process(0.01)
	_check(controller.is_attacking(), "Attack is running before the debug window opens")
	await _tap(KEY_F1)
	_check(_panel.visible and _panel.mode == CheatPanel.Mode.ITEMS and paused, "F1 opens supplies and pauses combat")
	_check(not controller.is_attacking() and not controller.is_trigger_held(), "Opening debug cancels held attacks")
	_check(world.player.is_ui_blocking(), "Player world actions are blocked by the debug panel")
	_check(_row_count() == registry.table.size() + registry.runtime_instances.size(), "All registered supplies are listed")
	var material_before: int = inventory.get_count(2)
	_search("石头")
	_check(_row_count() == 1 and _panel._selected_item == 2, "Supply search selects the matching item")
	_panel._amount.get_line_edit().text = "17"
	_panel._apply.pressed.emit()
	_check(inventory.get_count(2) == material_before + 17, "Acquire command grants the requested quantity")
	_check(inventory.get_item_data[2] == registry.get_template(2), "Granted materials use the registry definition")
	_check(_panel.grant_item(999999, 1) == 0 and _panel.grant_item(2, 0) == 0, "Invalid IDs and quantities cannot create phantom supplies")
	_search("long_missing_item")
	_check(_row_count() == 0 and _panel._apply.disabled, "Empty search disables acquisition")
	_search("长枪")
	var spear_before: int = inventory.get_count(201)
	_panel._apply.pressed.emit()
	_check(inventory.get_count(201) == spear_before + 1, "Weapon acquisition reaches the real backpack")
	_check(_panel._amount.max_value == 1, "Nonstacking weapons grant one at a time")
	await _layout_checks()
	await _screenshot("supplies-desktop.png")
	var potion_ids: Array = registry.runtime_instances.keys()
	_check(_panel.grant_item(300, 1) == 1 and _panel.grant_item(300, 1) == 1, "Potion template creates two usable bottles")
	var created: Array[PotionData] = []
	for id: int in registry.runtime_instances:
		if not potion_ids.has(id):
			created.append(registry.runtime_instances[id] as PotionData)
	_check(created.size() == 2 and created[0].id != created[1].id, "Each granted potion has a unique runtime ID")
	_check(created[0].alchemical_attribute[0] != created[1].alchemical_attribute[0], "Potion attributes are not shared between bottles")
	_check(inventory.get_count(created[0].id) == 1 and inventory.get_item_data[created[0].id] == created[0], "Backpack resolves the generated bottle")
	created[0].alchemical_attribute[0].level = 2
	_check(_panel.grant_item(created[0].id, 1) == 1, "Existing runtime potions can also be acquired")
	var cloned: PotionData = registry.runtime_instances[inventory.has_items.back()] as PotionData
	_check(cloned.alchemical_attribute[0].level == 2 and created[1].alchemical_attribute[0].level == 0, "Potion copies preserve runtime levels without mutating other bottles")
	_search("石头")
	_panel._amount.get_line_edit().text = "9"
	var counts: Dictionary = inventory.items.duplicate()
	_panel._bulk.pressed.emit()
	for item: ItemData in registry.table.values():
		var expected: int = int(counts.get(item.id, 0))
		if not item is WeaponData and not item is PotionData:
			expected += mini(9, item.max_stack)
		_check(inventory.get_count(item.id) == expected, "Bulk supplies preserve weapons and potions: %d" % item.id)

	await _tap(KEY_F2)
	_check(_panel.visible and _panel.mode == CheatPanel.Mode.BUFFS and paused, "F2 switches from supplies to buffs while paused")
	_check(_row_count() == UpgradePool.catalog().size(), "Every upgrade is available, independent of equipped weapon")
	progress.pending_choices = 2
	var level_before: int = progress.level
	var experience_before: float = progress.experience
	var pity_before: int = progress.rolls_since_rare
	_search("spear_flurry")
	_panel._amount.value = 1
	_panel._apply.pressed.emit()
	_check(progress.stacks_of(&"spear_flurry") == 1, "Buff apply grants the selected upgrade")
	_check((controller.equipped_weapon as SpearWeaponDefinition).thrust_count == 2, "Spear upgrade immediately rebuilds the actual equipped weapon")
	_check(progress.pending_choices == 2 and progress.level == level_before and progress.experience == experience_before and progress.rolls_since_rare == pity_before, "Debug buffs do not spend choices, experience, levels or pity")
	_check(progress.debug_set_card_stacks(&"sharp", 3), "General buff stacks can be set directly")
	_check(is_equal_approx(controller.equipped_weapon.damage * world.player.outgoing_damage_multiplier(null), 22.0 * 0.8 * 1.36), "General and spear buffs combine in actual outgoing damage")
	_check(not progress.debug_set_card_stacks(&"sharp", 6) and not progress.debug_set_card_stacks(&"sharp", -1) and not progress.debug_set_card_stacks(&"missing", 1), "Invalid debug buffs are rejected")
	_check(progress.stacks_of(&"sharp") == 3, "Rejected edits leave existing stacks intact")
	progress.debug_set_card_stacks(&"thunder_contract", 1)
	progress.debug_set_card_stacks(&"thunder_core", 1)
	_check(progress.stacks_of(&"thunder_contract") == 0 and progress.stacks_of(&"thunder_core") == 1, "Exclusive ultimate switches replace the previous selection")
	_check(not progress.take_card(&"thunder_beacon"), "Normal upgrade rules still enforce exclusivity")
	_search("spear_flurry")
	await _layout_checks()
	await _screenshot("buffs-desktop.png")
	root.size = Vector2i(960, 540)
	await _layout_checks()
	await _screenshot("buffs-compact.png")
	_panel._remove.pressed.emit()
	_check(progress.stacks_of(&"spear_flurry") == 0 and (controller.equipped_weapon as SpearWeaponDefinition).thrust_count == 1, "Removing a buff restores the base attack sequence")
	_panel._bulk.pressed.emit()
	_check(progress.cards_taken.is_empty() and progress.pending_choices == 2 and progress.level == level_before, "Clear buffs preserves normal progression")
	_check(is_equal_approx(controller.equipped_weapon.damage, 22.0), "Clearing buffs restores base weapon damage")
	await _tap(KEY_ESCAPE)
	_check(not _panel.visible and not paused, "Escape closes debug and resumes combat")
	await _tap(KEY_F1)
	await _tap(KEY_F1)
	_check(not _panel.visible and not paused, "Pressing the same function key closes its panel")
	_check(not controller.is_attacking(), "Closing debug never resumes a held attack")

	progress.pending_choices = 0
	progress.add_experience(progress.experience_required())
	await process_frame
	_check(upgrades.visible and paused and progress.pending_choices == 1, "Normal level-up still opens a choice panel")
	await _tap(KEY_F2)
	await _tap(KEY_1)
	_check(progress.pending_choices == 1 and upgrades.visible, "Debug keyboard input never selects an underlying upgrade")
	for card: UpgradeCard in upgrades._cards.duplicate():
		progress.debug_set_card_stacks(card.id, card.max_stacks)
	pity_before = progress.rolls_since_rare
	await _tap(KEY_F2)
	await process_frame
	_check(not _panel.visible and upgrades.visible and paused and progress.pending_choices == 1, "Closing debug preserves the underlying upgrade pause and choice")
	_check(progress.rolls_since_rare == pity_before, "Refreshing debug-modified choices preserves normal pity")
	for card: UpgradeCard in upgrades._cards:
		_check(UpgradePool.can_take(card, progress.cards_taken), "Underlying upgrade options refresh after debug edits")
	manager._on_card_chosen(upgrades._cards[0].id)
	_check(progress.pending_choices == 0 and not paused and not upgrades.visible, "Normal selection resumes after leaving debug")
	progress.reset()
	_check(progress.cards_taken.is_empty(), "New run reset clears debug buffs")
	await _tap(KEY_F1)
	world.queue_free()
	await process_frame
	await process_frame
	_check(not paused, "Removing an open debug window releases its pause")
	print("CHEAT PANEL: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	return event
