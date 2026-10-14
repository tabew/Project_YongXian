extends SceneTree

## 通关结算单元测试：面板展示与确认信号，以及 Boss 房清空 → 贤者之石结算 → 回工坊接线。
##
## godot --headless --path . --script res://tests/test_run_settlement.gd

const WORLD_SCENE: String = "res://scenes/game/game_world.tscn"

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
	_test_panel()
	await _test_boss_settlement()
	print("RUN SETTLEMENT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_panel() -> void:
	var panel := RunSettlementPanel.new()
	root.add_child(panel)
	_check(not panel.is_showing(), "面板初始隐藏")
	var results: Array = []
	panel.confirmed.connect(func() -> void: results.append(true))
	panel.show_result({
		"run": 40, "sage_stone": 100, "materials": 26, "performance": 0,
		"base": 166, "difficulty": 1.2, "codex_bonus": 0.05, "final": 209,
	})
	_check(panel.is_showing(), "展示后可见")
	_check(paused, "结算时世界暂停")
	_check(panel.final_value() == 209, "最终灵感来自结算结果")
	_check(panel.row_count() >= 7, "明细行齐全：%d" % panel.row_count())
	var confirm: Button = panel.get_node_or_null("Root/Column/Confirm") as Button
	_check(confirm != null, "有确认按钮")
	if confirm != null:
		confirm.pressed.emit()
	_check(results.size() == 1, "确认广播一次")
	_check(not panel.is_showing(), "确认后收起")
	_check(not paused, "确认后恢复世界")
	panel.queue_free()


## 世界层：清空 Boss 房触发结算，最终灵感进永久池；结算只跑一次。
func _test_boss_settlement() -> void:
	var manager: Node = root.get_node_or_null("/root/Inspiration")
	_check(manager != null, "灵感单例已注册")
	var scene: PackedScene = load(WORLD_SCENE) as PackedScene
	_check(scene != null, "局内场景可加载")
	if manager == null or scene == null:
		return
	var world: Node2D = scene.instantiate() as Node2D
	root.add_child(world)
	await process_frame
	await process_frame

	var generator: WorldGenerator = world.get("_generator")
	_check(generator != null, "世界生成器已建立")
	var boss_id: int = -1
	if generator != null and generator.run != null:
		for ids: PackedInt32Array in generator.run.floors:
			for node_id: int in ids:
				var room: RoomData = generator.run.room_data(node_id)
				if room != null and room.kind == RoomKind.Kind.BOSS:
					boss_id = node_id
	_check(boss_id >= 0, "本层存在 Boss 房")
	if boss_id < 0:
		return

	world.call("_enter_map", boss_id, 0, -1, true)
	await process_frame
	# 直接清空 Boss 房，触发通关结算。
	for attempt: int in 8:
		# 不静态引用 GameWorld：--script 模式下自动加载单例在编译期还不存在。
		for monster: Node in get_nodes_in_group("monsters"):
			if monster.has_method("kill"):
				monster.call("kill")
		await process_frame
	world.call("_update_room_clear")
	await process_frame

	var settlement: RunSettlementPanel = world.get("settlement")
	_check(settlement != null, "结算面板已挂到世界")
	if settlement == null:
		return
	_check(bool(world.get("_run_finished")), "Boss 房清空即通关")
	_check(settlement.is_showing(), "通关弹出结算面板")
	_check(manager.get("in_run") == false, "结算后离开局内")
	_check(int(manager.state.inspiration) > 0, "最终灵感进永久池")
	_check(settlement.confirmed.is_connected(Callable(world, "_on_settlement_confirmed")), "确认接线到回工坊")

	# 结算只跑一次：重复触发不改变结果。
	var final_before: int = settlement.final_value()
	var pool_before: int = int(manager.state.inspiration)
	world.call("_finish_run")
	_check(settlement.final_value() == final_before, "重复触发不重算")
	_check(int(manager.state.inspiration) == pool_before, "重复触发不重复入账")
	settlement.hide_panel()
