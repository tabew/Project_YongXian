extends SceneTree

## 炼金工坊单元测试：布局配置、灵感单例、永久升级购买、出发配置、各面板构建与交互。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_test_layout()
	_test_manager_pool()
	_test_manager_run()
	_test_alchemy_bridge()
	_test_departure_config()
	_test_save_round_trip()
	_test_panels()
	_test_interactable()
	print("WORKSHOP: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_layout() -> void:
	_check(WorkshopLayout.POINTS.size() == 9, "9 个交互点")
	var ids: Dictionary = {}
	for entry: Dictionary in WorkshopLayout.POINTS:
		var id: StringName = StringName(entry["id"])
		_check(not ids.has(id), "交互点 id 唯一：" + String(id))
		ids[id] = true
		_check(String(entry["name"]) != "", "交互点有名字：" + String(id))
		_check(String(entry["panel"]) != "", "交互点有面板：" + String(id))
		var position: Vector2 = entry["position"]
		_check(absf(position.x) < WorkshopLayout.ROOM_HALF.x and absf(position.y) < WorkshopLayout.ROOM_HALF.y,
			"交互点在房间内：" + String(id))
	var spawn: Vector2 = WorkshopLayout.SPAWN
	_check(absf(spawn.x) < WorkshopLayout.ROOM_HALF.x and absf(spawn.y) < WorkshopLayout.ROOM_HALF.y, "出生点在房间内")
	_check(WorkshopLayout.point_ids().size() == 9, "point_ids 数量一致")
	_check(WorkshopLayout.find_point(&"departure_gate").get("name", "") == "出发门", "能找到出发门")
	_check(WorkshopLayout.find_point(&"not_exist").is_empty(), "未知交互点返回空")
	_check(WorkshopLayout.placeholder_ids().size() == 4, "4 个只留接口的交互点")
	for id: StringName in [&"codex_table", &"relic_shelf", &"achievement_wall", &"shop"]:
		_check(WorkshopLayout.placeholder_ids().has(id), "占位交互点：" + String(id))
	for id: StringName in [&"alchemy_table", &"material_vault", &"difficulty_altar", &"departure_gate", &"training_ground"]:
		_check(not WorkshopLayout.placeholder_ids().has(id), "已实现交互点：" + String(id))


func _test_manager_pool() -> void:
	var manager := InspirationManager.new()
	root.add_child(manager)
	var purchased: Array = []
	# GDScript 的 lambda 按值捕获局部变量，所以用数组累计。
	var permanent_changes: Array = []
	manager.upgrade_purchased.connect(func(id: StringName, level: int) -> void: purchased.append([id, level]))
	manager.permanent_changed.connect(func() -> void: permanent_changes.append(true))

	manager.add_permanent_inspiration(-5)
	_check(manager.state.inspiration == 0, "负数不增加灵感")
	manager.add_permanent_inspiration(1000)
	_check(manager.state.inspiration == 1000, "永久灵感池增加")
	_check(permanent_changes.size() == 1, "广播一次变化")

	_check(manager.purchase_upgrade(&"bag_capacity"), "购买成功")
	_check(manager.state.inspiration == 700, "扣除灵感")
	_check(purchased.size() == 1 and purchased[0][1] == 1, "广播购买事件")
	_check(not manager.purchase_upgrade(&"not_exist"), "未知升级购买失败")

	var modifiers: Dictionary = manager.get_permanent_modifiers()
	for key: StringName in [&"material_slots_plus", &"bag_capacity_plus", &"stack_multiplier", &"base_duration_plus",
			&"burst_ratio_plus", &"heat_cooldown_multiplier", &"heat_max_plus", &"adsorb_radius_plus",
			&"reaction_bonus", &"overload_loss_reduction", &"overload_disable_reduction", &"preset_slots_plus",
			&"retention_ratio", &"element_levels"]:
		_check(modifiers.has(key), "修正表包含：" + String(key))
	_check(int(modifiers[&"bag_capacity_plus"]) == 2, "背包 +2 生效")
	_check(is_equal_approx(float(modifiers[&"stack_multiplier"]), 1.0), "未购买堆叠时倍率为 1")
	manager.state.add_inspiration(10000)
	manager.purchase_upgrade(&"element_fire")
	manager.purchase_upgrade(&"stack_bonus")
	modifiers = manager.get_permanent_modifiers()
	_check(int(modifiers[&"element_levels"].get(&"fire", 0)) == 1, "元素等级进入修正表")
	_check(is_equal_approx(float(modifiers[&"stack_multiplier"]), 1.2), "堆叠倍率 1.2")


func _test_manager_run() -> void:
	var manager := InspirationManager.new()
	root.add_child(manager)
	var started: Array = []
	manager.run_started.connect(func(tier: int) -> void: started.append(tier))

	manager.start_run()
	_check(manager.in_run, "开局标记")
	_check(started.size() == 1, "广播开局")

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var dropped: int = manager.drop_inspiration(Vector2.ZERO, 20, InspirationRules.Source.ELITE)
	_check(dropped == 20, "掉落记账")
	_check(manager.run.in_flight == 20 and manager.run.gained == 0, "掉落先进飞行中")
	_check(manager.collect_inspiration(20) == 20, "飞入计入")
	_check(manager.run.gained == 20, "已获得 20")
	_check(manager.roll_inspiration(Vector2.ZERO, InspirationRules.Source.REGION_BOSS, rng) >= 50, "Boss 必掉")

	var fail: Dictionary = manager.fail_run()
	_check(not manager.in_run, "死亡后离开局内")
	_check(int(fail["kept"]) == 0, "未购买留存时保留 0")
	_check(int(fail["lost"]) == 20, "损失全部")
	_check(manager.state.inspiration == 0, "死亡不产生永久灵感")

	manager.state.add_inspiration(100000)
	for index: int in 3:
		manager.purchase_upgrade(&"retention")
	manager.start_run()
	manager.drop_inspiration(Vector2.ZERO, 100, InspirationRules.Source.NORMAL)
	manager.collect_inspiration(100)
	var fail_two: Dictionary = manager.fail_run()
	_check(int(fail_two["kept"]) == 15, "留存 III 保留 15%")
	_check(manager.state.inspiration == 100000 - 1700 + 15, "保留的灵感进永久池")

	manager.start_run()
	manager.drop_inspiration(Vector2.ZERO, 50, InspirationRules.Source.NORMAL)
	manager.collect_inspiration(50)
	var clears_before: int = manager.state.clears
	var settle: Dictionary = manager.finish_run({0: 2}, 10)
	_check(manager.state.clears == clears_before + 1, "通关次数 +1")
	_check(int(settle["final"]) == int(round((50.0 + 100.0 + 4.0 + 10.0) * 1.0)), "通关结算公式")
	_check(manager.state.inspiration == 100000 - 1700 + 15 + int(settle["final"]), "结算进永久池")
	_check(not manager.in_run, "通关后离开局内")


func _test_alchemy_bridge() -> void:
	var manager := InspirationManager.new()
	root.add_child(manager)
	var station := AlchemyStation.new()
	root.add_child(station)
	station.setup()
	manager.state.add_inspiration(100000)

	manager.purchase_upgrade(&"material_slots")
	manager.purchase_upgrade(&"bag_capacity")
	manager.purchase_upgrade(&"preset_slots")
	manager.purchase_upgrade(&"heat_cooldown")
	manager.purchase_upgrade(&"adsorb_radius")
	var applied: int = manager.apply_to_alchemy_station(station)
	_check(applied == 5, "5 项映射到炼金升级")
	_check(station.progression.slot_plus() == 1, "素材槽 +1")
	_check(station.progression.bag_plus() == 2, "背包 +2")
	_check(station.progression.preset_plus() == 1, "预设 +1")
	_check(station.progression.heat_cooldown_multiplier() > 1.0, "热量冷却提升")
	_check(station.progression.adsorb_tiles_plus() >= 1.0, "吸附范围提升")
	_check(manager.apply_to_alchemy_station(null) == 0, "空节点安全返回")
	_check(manager.apply_to_alchemy_station(station) == 5, "重复应用不报错")
	station.queue_free()


func _test_departure_config() -> void:
	var manager := InspirationManager.new()
	root.add_child(manager)
	_check(manager.selected_weapon_id == &"longsword", "默认武器是剑")
	_check(manager.material_slot_capacity == 1, "初始携带 1 格")
	manager.set_weapon(&"yoyo")
	_check(manager.selected_weapon_id == &"yoyo", "选择武器")

	_check(manager.set_carried_materials(PackedInt32Array([1001])), "携带 1 种材料")
	_check(not manager.set_carried_materials(PackedInt32Array([1001, 1002])), "超出格数被拒绝")
	_check(not manager.set_carried_materials(PackedInt32Array([999999])), "未知材料被拒绝")
	manager.material_slot_capacity = 3
	_check(manager.set_carried_materials(PackedInt32Array([1001, 1002, 1003])), "解锁后可携带 3 种")

	_check(not manager.set_difficulty(1), "0 次通关不解锁炼金师")
	_check(manager.set_difficulty(0), "学徒可选")
	manager.state.register_clear()
	_check(manager.set_difficulty(1), "通关一次解锁炼金师")
	_check(not manager.set_difficulty(2), "大师仍未解锁")
	_check(manager.difficulty_tier == 1, "难度已切换")


func _test_save_round_trip() -> void:
	var manager := InspirationManager.new()
	root.add_child(manager)
	manager.state.add_inspiration(5000)
	manager.purchase_upgrade(&"preset_slots")
	manager.set_weapon(&"yoyo")
	manager.set_carried_materials(PackedInt32Array([1001]))
	manager.state.register_clear()
	manager.difficulty_tier = 1
	manager.material_slot_capacity = 2

	var data: Dictionary = manager.to_dict()
	var restored := InspirationManager.new()
	root.add_child(restored)
	restored.from_dict(data)
	_check(restored.state.inspiration == manager.state.inspiration, "存档保留永久灵感")
	_check(restored.state.level_of(&"preset_slots") == 1, "存档保留升级等级")
	_check(restored.selected_weapon_id == &"yoyo", "存档保留武器")
	_check(restored.carried_material_ids.size() == 1 and restored.carried_material_ids[0] == 1001, "存档保留携带材料")
	_check(restored.difficulty_tier == 1, "存档保留难度")
	_check(restored.material_slot_capacity == 2, "存档保留携带格数")


func _test_panels() -> void:
	var manager := InspirationManager.new()
	root.add_child(manager)
	manager.add_permanent_inspiration(5000)

	var upgrade := UpgradePanel.new()
	upgrade.setup(manager)
	root.add_child(upgrade)
	upgrade.open()
	_check(upgrade.is_open(), "炼金台面板可打开")
	_check(upgrade.content().get_child_count() == PermanentUpgradeCatalog.all().size(), "炼金台列出全部升级")
	var first_button: Button = _first_button(upgrade.content())
	_check(first_button != null, "炼金台有购买按钮")
	first_button.pressed.emit()
	_check(manager.state.level_of(&"material_slots") == 1, "点击按钮完成购买")
	_check(upgrade.content().get_child_count() == PermanentUpgradeCatalog.all().size(), "购买后面板刷新")
	upgrade.close()
	_check(not upgrade.is_open(), "面板可关闭")

	var vault := MaterialVaultPanel.new()
	vault.setup(manager)
	root.add_child(vault)
	vault.open()
	_check(vault.content().get_child_count() == MaterialCatalog.all_ids().size(), "材料库列出全部材料")
	var vault_button: Button = _first_button(vault.content())
	vault_button.pressed.emit()
	_check(manager.carried_material_ids.size() == 1, "材料库切换携带")
	vault_button = _first_button(vault.content())
	vault_button.pressed.emit()
	_check(manager.carried_material_ids.is_empty(), "再次点击取消携带")

	var altar := DifficultyAltarPanel.new()
	altar.setup(manager)
	root.add_child(altar)
	altar.open()
	_check(altar.content().get_child_count() == DifficultyTier.COUNT + 1, "难度祭坛列出 3 档 + 修饰占位")

	var departure := DepartureGatePanel.new()
	departure.setup(manager)
	departure.weapon_ids = [&"longsword", &"yoyo"]
	root.add_child(departure)
	departure.open()
	_check(departure.content().get_child_count() >= 6, "出发门列出四段内容")
	var started: Array = []
	departure.start_run_requested.connect(func() -> void: started.append(true))
	var start_button: Button = _last_button(departure.content())
	start_button.pressed.emit()
	_check(started.size() == 1, "出发门可触发开始")

	var training := TrainingGroundPanel.new()
	training.setup(manager)
	root.add_child(training)
	training.open()
	_check(training.content().get_child_count() == MaterialCatalog.all_ids().size() + 1, "训练场列出全部材料 + 提示")
	_check(training.content().get_child(1).get_child(1).disabled, "未注入主角时补充按钮禁用")

	var placeholder := PlaceholderPanel.new()
	placeholder.point_name = "图鉴台"
	placeholder.planned = "词条 / 反应收集进度"
	placeholder.setup(manager)
	root.add_child(placeholder)
	placeholder.open()
	_check(placeholder.content().get_child_count() == 1, "占位面板有说明")


func _test_interactable() -> void:
	var point := WorkshopInteractable.new()
	point.id = &"alchemy_table"
	point.display_name = "炼金台"
	point.panel_id = &"upgrade"
	root.add_child(point)
	point.global_position = Vector2.ZERO
	_check(point.can_interact_from(Vector2(10.0, 0.0)), "半径内可交互")
	_check(not point.can_interact_from(Vector2(500.0, 0.0)), "半径外不可交互")
	_check(not point.is_highlighted(), "默认未高亮")
	point.set_highlighted(true)
	_check(point.is_highlighted(), "可以高亮")
	var events: Array = []
	point.interacted.connect(func(id: StringName) -> void: events.append(id))
	point.interact()
	_check(events.size() == 1 and events[0] == &"alchemy_table", "触发交互信号")
	point.queue_free()


func _first_button(parent: Node) -> Button:
	return _find_button(parent, false)


func _last_button(parent: Node) -> Button:
	return _find_button(parent, true)


func _find_button(parent: Node, from_end: bool) -> Button:
	var children: Array[Node] = parent.get_children()
	var ordered: Array[Node] = children.duplicate()
	if from_end:
		ordered.reverse()
	for row: Node in ordered:
		if row is Button:
			return row
		var found: Button = _find_button(row, from_end)
		if found != null:
			return found
	return null
