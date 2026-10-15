extends SceneTree

## 训练场试验场与「非战斗按 E 打开炼金台」：
## - 工坊里不再生成假人，按 E 打开完整炼金台并完全暂停；
## - 训练场交互点只负责确认前往试验场；
## - 试验场里有打不死、不会移动的假人 + DPS 计数器 + 返回按钮 + 无限材料。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## 模拟一次真实按键（按下 + 抬起），走 Input 映射而不是直接调内部函数。
func _press_key(keycode: Key) -> void:
	var pressed: InputEventKey = InputEventKey.new()
	pressed.physical_keycode = keycode
	pressed.pressed = true
	Input.parse_input_event(pressed)
	var released: InputEventKey = InputEventKey.new()
	released.physical_keycode = keycode
	Input.parse_input_event(released)


func _dummy_count(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child is TrainingDummy:
			count += 1
	return count


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_workshop_alchemy_menu()
	await _test_training_panel()
	await _test_arena()
	print("TRAINING ARENA: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 工坊：没有假人；按 E 打开完整炼金台并完全暂停；Esc 关闭并恢复。
func _test_workshop_alchemy_menu() -> void:
	var workshop: Node2D = (load("res://scenes/workshop/workshop.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(workshop)
	current_scene = workshop
	await process_frame
	await process_frame
	var player: PlayerCharacter = workshop.get_node("Player") as PlayerCharacter
	_check(_dummy_count(workshop) == 0, "工坊不再生成假人")
	var alchemy_hud: Node = workshop.get_node_or_null("WorkshopHud/Root/Alchemy")
	_check(alchemy_hud != null, "工坊挂上了随身炼金台 HUD")
	_check(alchemy_hud != null and alchemy_hud.has_method("bind"), "炼金台 HUD 提供 bind 接口")

	_press_key(KEY_E)
	await process_frame
	await process_frame
	_check(player.alchemy_station.is_menu_open(), "工坊按 E 打开完整炼金台")
	_check(paused, "打开炼金台时世界完全暂停")
	_check(alchemy_hud != null and alchemy_hud.is_in_group("alchemy_panel"), "炼金面板已显示")

	_press_key(KEY_ESCAPE)
	await process_frame
	await process_frame
	_check(not player.alchemy_station.is_menu_open(), "Esc 关闭炼金台")
	_check(not paused, "关闭炼金台后世界恢复运行")
	workshop.queue_free()
	await process_frame
	await process_frame


## 训练场交互点：只有说明 + 确认前往，点击后广播 travel_requested。
func _test_training_panel() -> void:
	var panel := TrainingGroundPanel.new()
	panel.setup(null)
	root.add_child(panel)
	var travels: Array = []
	panel.travel_requested.connect(func() -> void: travels.append(true))
	panel.open()
	_check(panel.content().get_child_count() == 2, "训练场面板：说明 + 确认前往")
	var button: Button = _find_button(panel.content())
	_check(button != null and button.text == "确认前往", "训练场面板有确认前往按钮")
	if button != null:
		button.pressed.emit()
	_check(travels.size() == 1, "确认前往广播 travel_requested")
	panel.close()
	panel.queue_free()
	await process_frame


## 试验场：打不死的固定假人 + DPS 计数器 + 返回 + 无限材料 + 按 E 开炼金台。
func _test_arena() -> void:
	# 用 Variant 接住场景根：训练场脚本引用了 SceneManager 自动加载单例，
	# 写成 TrainingArena 类型会让本测试在解析阶段就去编译它，那时单例还没注册。
	var arena: Variant = (load("res://scenes/workshop/training_arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	await process_frame
	var player: PlayerCharacter = arena.player
	var dummy: TrainingDummy = arena.dummy
	_check(dummy != null, "试验场里有假人")
	_check(dummy.immobile, "假人固定不动")
	_check(dummy.health.max_health >= 1000000000.0, "假人血量高到打不死")
	var dps: Label = dummy.get_node_or_null("DpsCounter") as Label
	_check(dps != null, "假人旁边有 DPS 计数器")
	_check(dps != null and dps.text.begins_with("DPS"), "DPS 计数器有文案")
	_check(player.weapon_controller.equipped_weapon.id == &"longsword", "试验场套用了出发配置的武器")

	# 连续打假人：血量在掉，但永远打不死。
	var start_position: Vector2 = dummy.global_position
	for _index: int in range(5):
		var hit := CombatHit.new()
		hit.damage = 1000000.0
		hit.knockback = Vector2(400.0, 0.0)
		hit.position = dummy.global_position
		dummy.health.receive_hit(hit)
	_check(dummy.health.is_alive(), "假人挨了 500 万伤害仍然活着")
	_check(dummy.health.current_health < dummy.health.max_health, "假人血量确实在掉")
	dummy._physics_process(0.5)
	await create_timer(0.2).timeout
	_check(dummy.global_position.is_equal_approx(start_position), "假人不吃击退、不会移动")
	_check(dps != null and dps.text != "DPS 0.0", "DPS 计数器记录到伤害")

	# 无限材料：点一下补固定数量。
	var material_id: int = MaterialCatalog.all_ids()[0]
	arena._on_grant(material_id)
	_check(player.alchemy_station.bag.count(material_id) == TrainingArena.GRANT_AMOUNT, "材料按钮补充固定数量")

	var back: Button = arena.get_node_or_null("ArenaHud/Root/BackButton") as Button
	_check(back != null and back.text == "返回工坊", "试验场有返回工坊按钮")
	_check(back != null and back.pressed.get_connections().size() == 1, "返回按钮已接线")

	# 试验场没有怪物：按 E 同样打开完整炼金台。
	_press_key(KEY_E)
	await process_frame
	await process_frame
	_check(player.alchemy_station.is_menu_open(), "试验场按 E 打开炼金台")
	_check(paused, "试验场打开炼金台时完全暂停")
	_press_key(KEY_ESCAPE)
	await process_frame
	await process_frame
	_check(not player.alchemy_station.is_menu_open(), "试验场 Esc 关闭炼金台")
	arena.queue_free()
	await process_frame
	await process_frame


func _find_button(parent: Node) -> Button:
	for row: Node in parent.get_children():
		if row is Button:
			return row as Button
		var found: Button = _find_button(row)
		if found != null:
			return found
	return null
