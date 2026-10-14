extends SceneTree

## 物品栏选中与使用的验收：
## 选中只改状态不动物品、左键点格子不触发使用、use() 的返回值决定扣多少、
## 武器走武器系统装备且不消耗、物品用光后选中自动清掉。
##
## 运行：godot --headless --path . --script res://tools/test_handy_selection_and_use.gd

const STUB_ITEM_SCRIPT: GDScript = preload("res://tests/fixtures/test_use_item.gd")

## 不与项目里的正式物品 id 冲突，也别用 300 以上：
## 注册表把 id >= POTION_ID_STRAT(300) 一律当成药水模板
const STUB_ONCE_ID: int = 210
const STUB_OVER_ID: int = 211
const STUB_FREE_ID: int = 212

const LONGSWORD_ITEM_ID: int = 200

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## 造一个只用于测试的物品模板，登记进注册表后返回它。
## 用脚本资源 .new() 而不是全局类名：新加的 class_name 还没进编辑器导入缓存时也能跑
func _register_stub(item_list: Node, item_id: int, consume_amount: int) -> ItemData:
	var item: ItemData = STUB_ITEM_SCRIPT.new() as ItemData
	item.id = item_id
	item.name = "测试道具%d" % item_id
	item.max_stack = 99
	item.set("consume_amount", consume_amount)
	item_list.templates.append(item)
	item_list.call("_build_table")
	# 比同一份实例要用 is_same：Resource 之间用 == 比的是内容
	_check(is_same(item_list.get_template(item_id), item), "测试道具登记进注册表 id=%d" % item_id)
	return item


## 塞一格物品栏并清掉其余格子，保证测试从干净状态开始
func _fill(inventory: Inventory, pos: int, item_id: int, num: int) -> void:
	var count: int = inventory.handy_items_pos.size()
	for slot: int in range(count + 1):
		inventory.clear_handy_slot(slot)
	inventory.add_handy_slot(pos, item_id, num)
	inventory.select_handy_slot(-1)


func _mouse_event(button: int) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _key_event(keycode: int) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _attack_event() -> InputEventMouseButton:
	return _mouse_event(MOUSE_BUTTON_LEFT)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 18473)
	var scene: PackedScene = load("res://scenes/game/game_world.tscn") as PackedScene
	var game: Node2D = scene.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	var player: PlayerCharacter = game.get_node("Player") as PlayerCharacter
	player.set_physics_process(false)
	game.get_node("MonsterSpawner").process_mode = Node.PROCESS_MODE_DISABLED

	var hotbar: Control = game.get_node("GameHUD/BottomBagUi")
	var inventory: Inventory = player.inventory
	var controller: WeaponController = player.weapon_controller
	var items: Node = root.get_node("ItemListGlobal")

	var once: ItemData = _register_stub(items, STUB_ONCE_ID, 2)
	var over: ItemData = _register_stub(items, STUB_OVER_ID, 99)
	var freebie: ItemData = _register_stub(items, STUB_FREE_ID, 0)

	_test_selection(inventory, hotbar)
	_test_use_consumption(inventory, once, over, freebie)
	_test_weapon(inventory, items, controller, player)
	_test_input(hotbar, inventory)
	await _test_drag_guard(hotbar, inventory)

	game.queue_free()
	await process_frame
	await process_frame
	print("HANDY_SELECTION_AND_USE: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 选中状态本身：位置校验、只看格子不看内容、整堆交换后不漂移
func _test_selection(inventory: Inventory, hotbar: Control) -> void:
	# 起始选中写在 resources/inventory/inventory.tres 里，开局就有武器可用
	_check(inventory.get_selected_handy() == 0, "开局选中第1格（配置里的起始选中）")
	_check(hotbar.item_buttons[0].is_selected, "开局第1格就有描边")

	inventory.select_handy_slot(-1)
	_check(inventory.get_selected_handy() == -1, "可以取消选中")
	_check(hotbar.item_buttons[0].is_selected == false, "取消选中后描边熄灭")

	_check(inventory.select_handy_slot(2), "可以选中第3格")
	_check(inventory.get_selected_handy() == 2, "选中位置记为第3格")
	_check(hotbar.item_buttons[2].is_selected, "选中格子出现描边")
	_check(not hotbar.item_buttons[0].is_selected, "未选中格子没有描边")

	_check(not inventory.select_handy_slot(2), "重复选中同一格返回false")
	_check(not inventory.select_handy_slot(Inventory.HANDY_SLOT_COUNT), "越界位置被拒绝")
	_check(not inventory.select_handy_slot(-2), "小于-1的位置被拒绝")
	_check(inventory.get_selected_handy() == 2, "被拒绝的选中不改变当前选中")

	# 选中空格是允许的，选中状态只认格子
	_fill(inventory, 0, STUB_ONCE_ID, 3)
	_check(inventory.select_handy_slot(5), "可以选中空格子")
	_check(inventory.get_selected_item_id() == -1, "选中空格时物品id为-1")
	_check(inventory.get_selected_count() == 0, "选中空格时数量为0")

	# 整堆交换改的是格子内容，选中格不变
	inventory.select_handy_slot(0)
	inventory.add_handy_slot(1, STUB_FREE_ID, 5)
	inventory.swap_handy_slot(0, 1, STUB_ONCE_ID, 3)
	_check(inventory.get_selected_handy() == 0, "整堆交换后选中仍指原来那一格")
	_check(inventory.get_selected_item_id() == STUB_FREE_ID, "交换后选中格读到的是换进来的物品")
	_check(inventory.get_handy_slot_count(0) > 0 and inventory.get_handy_slot_count(1) > 0, "两格都放着东西")

	# 选中的格子被清空就自动取消选中
	inventory.clear_handy_slot(0)
	_check(inventory.get_selected_handy() == -1, "选中格被清空后自动取消选中")
	_check(hotbar.item_buttons[0].is_selected == false, "取消选中后描边熄灭")


## use() 的返回值决定扣多少，扣数只由 Inventory 执行
func _test_use_consumption(inventory: Inventory, once: ItemData, over: ItemData, freebie: ItemData) -> void:
	inventory.select_handy_slot(-1)
	_check(inventory.get_selected_handy() < 0 and inventory.use_handy_slot(null) == 0, "没有选中时使用返回0")

	# _fill 会取消选中，这里先确认它真的是没选中的状态
	_fill(inventory, 3, STUB_ONCE_ID, 5)
	_check(inventory.use_handy_slot(null) == 0, "选中空格时使用返回0")
	_check(inventory.get_handy_slot_count(3) == 5, "选中空格使用后其它格子数量不变")

	# 返回2 -> 扣2
	inventory.select_handy_slot(3)
	_check(inventory.use_handy_slot(null) == once.use(null), "使用返回物品给的消耗值")
	_check(inventory.get_handy_slot_count(3) == 3, "按返回值扣掉2份")
	_check(inventory.get_selected_handy() == 3, "还有剩余时保持选中")

	# 返回99 -> 最多扣到清格
	_fill(inventory, 4, STUB_OVER_ID, 3)
	inventory.select_handy_slot(4)
	_check(inventory.use_handy_slot(null) == 99, "使用返回超量消耗值")
	_check(inventory.get_handy_slot_count(4) == 0, "超量消耗最多把本格扣空")
	_check(inventory.handy_items_pos.has(4) == false, "扣空的格子被清掉")
	_check(inventory.get_selected_handy() == -1, "本格用光后取消选中")

	# 返回0 -> 一点都不扣
	_fill(inventory, 5, STUB_FREE_ID, 4)
	inventory.select_handy_slot(5)
	_check(inventory.use_handy_slot(null) == 0, "不消耗物品返回0")
	_check(inventory.get_handy_slot_count(5) == 4, "返回0时数量不变")
	_check(inventory.get_selected_handy() == 5, "返回0时保持选中")
	_check(freebie.weapon_definition == null, "普通道具没有武器引用")


## 武器由 use() 内部转给武器系统：装备成功、不消耗；玩家侧没有别的装备入口
func _test_weapon(inventory: Inventory, items: Node, controller: WeaponController, player: PlayerCharacter) -> void:
	var sword_item: ItemData = items.get_template(LONGSWORD_ITEM_ID)

	_check(sword_item != null, "长剑物品模板存在")
	_check(sword_item.weapon_definition != null, "长剑物品挂上了武器数据")
	_check(sword_item.weapon_definition.id == &"longsword", "挂的是长剑武器数据")

	# 开局空手：starting_weapon 与 weapon_loadout 都已移除
	controller.equip(null)
	_check(controller.equipped_weapon == null, "控制器可以处于空手状态")
	_check(not player.has_method("equip_next_weapon"), "玩家侧没有直接换武器的入口")
	_check(not player.has_method("_ready_equip"), "玩家侧没有开局自动装备")

	controller.equip(load("res://resources/weapons/long_staff.tres") as WeaponDefinition)
	_fill(inventory, 6, LONGSWORD_ITEM_ID, 1)
	inventory.select_handy_slot(6)

	var changed: Array[WeaponDefinition] = []
	controller.weapon_changed.connect(func(weapon: WeaponDefinition) -> void: changed.append(weapon))

	_check(inventory.use_handy_slot(player) == 0, "使用武器不消耗")
	_check(controller.equipped_weapon.id == &"longsword", "使用武器后装备了对应武器")
	_check(inventory.get_handy_slot_count(6) == 1, "武器还在物品栏里")
	_check(changed.size() == 1, "装备武器发出了 weapon_changed")

	# 选中的是空格时使用不会误用别的格子
	inventory.select_handy_slot(7)
	_check(inventory.use_handy_slot(player) == 0, "选中空格时不会用到别的格子的武器")
	_check(controller.equipped_weapon.id == &"longsword", "选中空格使用后装备不变")
	_check(not player.has_selected_weapon(), "选中空格时没有选中武器")
	_check(player.get_selected_weapon() == null, "选中空格时取不到武器数据")

	# 物品栏没选中武器时左键不挥击
	_fill(inventory, 8, STUB_FREE_ID, 3)
	inventory.select_handy_slot(8)
	_check(not player.has_selected_weapon(), "选中材料时没有选中武器")
	_check(player.get_selected_weapon() == null, "选中材料时取不到武器数据")

	# 玩家左键的分流：没选中武器时不该把这一下按下交给武器控制器。
	# 控制器自己的物理帧被测试关掉了，所以这里手动补两帧看它有没有真的起手：
	# 只有按下被放行（走 set_trigger_pressed）时，下一帧才会消费出一次攻击
	controller.set_trigger_pressed(false)
	controller._physics_process(1.0)
	var blocked_starts: Array[WeaponDefinition] = []
	controller.attack_started.connect(func(weapon: WeaponDefinition) -> void: blocked_starts.append(weapon))
	player._unhandled_input(_attack_event())
	controller._physics_process(1.0)
	controller._physics_process(1.0)
	_check(blocked_starts.is_empty(), "没选中武器时左键不起手攻击")
	_check(not controller.is_attacking(), "没选中武器时不会挥击")

	# 选中武器格之后就恢复攻击（前面 _fill 已经把武器格清掉了，这里放回去）
	_fill(inventory, 6, LONGSWORD_ITEM_ID, 1)
	inventory.select_handy_slot(6)
	_check(player.has_selected_weapon(), "选中武器格时算选中武器")
	_check(player.get_selected_weapon() != null and player.get_selected_weapon().id == &"longsword", "选中武器格取到对应武器数据")

	var starts: Array[WeaponDefinition] = []
	controller.attack_started.connect(func(weapon: WeaponDefinition) -> void: starts.append(weapon))
	controller.set_trigger_pressed(false)
	player._unhandled_input(_attack_event())
	controller._physics_process(1.0)
	_check(starts.size() == 1, "选中武器格后左键恢复起手攻击")
	_check(controller.is_attacking(), "选中武器格后立刻挥击")
	controller.cancel_attack()
	controller.set_trigger_pressed(false)


## 输入：数字键与滚轮换选中（空格也算一格），点格子只选中不使用
func _test_input(hotbar: Control, inventory: Inventory) -> void:
	_fill(inventory, 0, STUB_ONCE_ID, 2)
	inventory.add_handy_slot(4, STUB_FREE_ID, 1)

	hotbar._input(_key_event(KEY_3))
	_check(inventory.get_selected_handy() == 2, "数字键3选中第3格")

	hotbar._input(_key_event(KEY_1))
	_check(inventory.get_selected_handy() == 0, "数字键1选中第1格")

	# 滚轮一格一格走，空格也停
	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_DOWN))
	_check(inventory.get_selected_handy() == 1, "滚轮向后选中相邻的第2格（空格）")
	_check(inventory.get_selected_item_id() == -1, "滚轮可以停在空格上")

	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_DOWN))
	_check(inventory.get_selected_handy() == 2, "滚轮继续向后走一格")
	_check(inventory.get_selected_item_id() == -1, "第3格也是空格，照样被选中")

	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_UP))
	_check(inventory.get_selected_handy() == 1, "滚轮反向走回第2格")

	# 从最后一格向后绕回第一格
	inventory.select_handy_slot(Inventory.HANDY_SLOT_COUNT - 1)
	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_DOWN))
	_check(inventory.get_selected_handy() == 0, "滚轮从最后一格绕回第1格")

	# 没有选中时向后落在第1格，向前落在最后一格
	inventory.select_handy_slot(-1)
	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_DOWN))
	_check(inventory.get_selected_handy() == 0, "没有选中时滚轮向后选中第1格")

	inventory.select_handy_slot(-1)
	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_UP))
	_check(inventory.get_selected_handy() == Inventory.HANDY_SLOT_COUNT - 1, "没有选中时滚轮向前选中最后一格")

	# 左键点格子只切换选中，绝不触发使用
	inventory.select_handy_slot(0)
	var filled_before: int = inventory.get_handy_slot_count(0)
	hotbar.item_buttons[4]._on_gui_input(_mouse_event(MOUSE_BUTTON_LEFT))
	_check(inventory.get_selected_handy() == 4, "左键点格子切换选中")
	_check(inventory.get_handy_slot_count(0) == filled_before, "左键点格子不使用、不扣数量")

	# 右键点格子：先切选中再使用
	var used_count: int = inventory.get_handy_slot_count(4)
	hotbar.item_buttons[4]._on_gui_input(_mouse_event(MOUSE_BUTTON_RIGHT))
	_check(inventory.get_selected_handy() == 4, "右键点格子仍选中本格")
	_check(inventory.get_handy_slot_count(4) == used_count, "右键使用的是不消耗的测试道具")


## 拖拽换位时不抢滚轮和数字键，免得和 Q/E 旋转打架
func _test_drag_guard(hotbar: Control, inventory: Inventory) -> void:
	# 预览控件由拖拽系统自己挂到光标上，这里不要先进场景树
	var preview: Control = Control.new()
	hotbar.item_buttons[0].force_drag({"item_id": STUB_ONCE_ID, "count": 1}, preview)
	_check(root.gui_is_dragging(), "测试拖拽已开始")
	_check(not hotbar._can_operate(), "拖拽时物品栏输入被挡住")
	var selected_before_drag: int = inventory.get_selected_handy()
	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_DOWN))
	hotbar._input(_key_event(KEY_2))
	_check(inventory.get_selected_handy() == selected_before_drag, "拖拽时滚轮和数字键不改变选中")
	root.gui_cancel_drag()
	await process_frame
	_check(not root.gui_is_dragging(), "测试拖拽已结束")
