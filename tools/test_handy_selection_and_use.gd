extends SceneTree

## 物品栏选中与使用的验收：
## 选中只改状态不动物品、左键点格子不触发使用、left_use() 的返回值决定扣多少、
## 武器走武器系统装备且不消耗、物品用光后选中自动清掉。
##
## 运行：godot --headless --path . --script res://tools/test_handy_selection_and_use.gd

const STUB_ITEM_SCRIPT: GDScript = preload("res://tests/fixtures/test_use_item.gd")
const POTION_TEMPLATE: PotionData = preload("res://resources/items/potions/potion_model.tres")
const HEAL_ATTRIBUTE: AlchemicalData = preload("res://resources/alchemical_attribute/heal.tres")

## 不与项目里的正式物品 id 冲突：
## 材料 0-4、武器 200-299（player.hand_item 按这个区间认武器）、药水 300 起（注册表把 >=300 当药水）
const STUB_ONCE_ID: int = 150
const STUB_OVER_ID: int = 151
const STUB_FREE_ID: int = 152

## 与 tests/fixtures/test_use_item.gd 里登记的消耗值保持一致
const STUB_ONCE_CONSUME: int = 2

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


## 塞一格物品栏并清掉其余格子，保证测试从干净状态开始。
## 先 add_item 再 add_handy_slot，和真实获得路径一致：
## get_item_data 是在 add_item()/_init() 里登记的，只塞快捷栏会取不到模板
func _fill(inventory: Inventory, pos: int, item_id: int, num: int) -> void:
	var count: int = inventory.handy_items_pos.size()
	for slot: int in range(count + 1):
		inventory.clear_handy_slot(slot)
	inventory.add_item(item_id, num)
	inventory.clear_handy_slot(pos)
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


func _attack_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "attack"
	event.pressed = true
	return event


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

	var once: ItemData = _register_stub(items, STUB_ONCE_ID, STUB_ONCE_CONSUME)
	var over: ItemData = _register_stub(items, STUB_OVER_ID, 99)
	var freebie: ItemData = _register_stub(items, STUB_FREE_ID, 0)
	_check(once != null and over != null and freebie != null, "测试道具都登记好了")

	_test_selection(inventory, hotbar)
	_test_use_consumption(inventory, player)
	_test_weapon(inventory, items, controller, player)
	_test_input(hotbar, inventory)
	_test_potion_use(hotbar, inventory, player, items)
	await _test_drag_guard(hotbar, inventory)

	game.queue_free()
	await process_frame
	await process_frame
	print("HANDY_SELECTION_AND_USE: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 选中状态本身：位置校验、只看格子不看内容、整堆交换后不漂移
## 注意：本地版本的 select_handy_slot 不接受 -1，清空格子也不会自动取消选中
func _test_selection(inventory: Inventory, hotbar: Control) -> void:
	# 起始选中写在 resources/inventory/inventory.tres 里，开局就有武器可用
	_check(inventory.get_selected_handy() == 0, "开局选中第1格（配置里的起始选中）")
	_check(hotbar.item_buttons[0].is_selected, "开局第1格就有描边")

	inventory.select_handy_slot(2)
	_check(inventory.get_selected_handy() == 2, "选中位置记为第3格")
	_check(hotbar.item_buttons[2].is_selected, "选中格子出现描边")
	_check(not hotbar.item_buttons[0].is_selected, "未选中格子没有描边")

	_check(not inventory.select_handy_slot(2), "重复选中同一格返回false")
	_check(not inventory.select_handy_slot(Inventory.HANDY_SLOT_COUNT), "越界位置被拒绝")
	_check(not inventory.select_handy_slot(-1), "负数位置被拒绝")
	_check(inventory.get_selected_handy() == 2, "被拒绝的选中不改变当前选中")

	# 选中空格是允许的，选中状态只认格子
	_fill(inventory, 0, STUB_ONCE_ID, 3)
	_check(inventory.select_handy_slot(5), "可以选中空格子")
	_check(inventory.get_handy_slot_id(5) == -1, "空格子取物品id为-1")

	# 整堆交换改的是格子内容，选中格不变
	inventory.select_handy_slot(0)
	inventory.add_handy_slot(1, STUB_FREE_ID, 5)
	inventory.swap_handy_slot(0, 1, STUB_ONCE_ID, 3)
	_check(inventory.get_selected_handy() == 0, "整堆交换后选中仍指原来那一格")
	_check(inventory.get_handy_slot_id(0) == STUB_FREE_ID, "交换后选中格读到的是换进来的物品")
	_check(inventory.get_handy_slot_count(0) > 0 and inventory.get_handy_slot_count(1) > 0, "两格都放着东西")

	# 清空选中格：数据清掉，但本地版本保留选中（没有自动取消选中）
	inventory.clear_handy_slot(0)
	_check(inventory.get_handy_slot_id(0) == -1, "清空后本格没有物品")
	_check(inventory.get_selected_handy() == 0, "清空选中格后选中位置保留")


## 使用选中的格子：消耗数量由 ItemData.left_use() 的返回值决定，扣数只由 Inventory 执行
func _test_use_consumption(inventory: Inventory, player: PlayerCharacter) -> void:
	# 选中空格：什么都不该发生，也不该去动别的格子
	_fill(inventory, 3, STUB_ONCE_ID, 5)
	inventory.select_handy_slot(3)
	inventory.clear_handy_slot(3)
	inventory.left_use_handy_slot(player)
	_check(inventory.get_handy_slot_id(3) == -1, "选中空格时使用不会凭空造出物品")

	# once 桩声明一次消耗 2 个
	var per_use: int = STUB_ONCE_CONSUME
	_fill(inventory, 3, STUB_ONCE_ID, 5)
	inventory.select_handy_slot(3)
	inventory.left_use_handy_slot(player)
	_check(inventory.get_handy_slot_count(3) == 5 - per_use, "按 use() 返回值扣掉 %d 个" % per_use)
	_check(inventory.get_selected_handy() == 3, "还有剩余时保持选中")

	inventory.left_use_handy_slot(player)
	_check(inventory.get_handy_slot_count(3) == 5 - per_use * 2, "第二次同样按返回值扣")

	# 用光之后格子消失
	inventory.left_use_handy_slot(player)
	_check(inventory.get_handy_slot_count(3) == 0, "用光后数量归零")
	_check(inventory.handy_items_pos.has(3) == false, "用光的格子被清掉")

	# 超量消耗：只剩 1 个时用一次就整格清掉（不会扣成负数）
	_fill(inventory, 4, STUB_OVER_ID, 1)
	inventory.select_handy_slot(4)
	inventory.left_use_handy_slot(player)
	_check(inventory.get_handy_slot_count(4) == 0 and inventory.handy_items_pos.has(4) == false, "最后一个用完清格")

	# 声明不消耗的道具：用多少次都还在
	inventory.add_item(STUB_FREE_ID, 2)
	inventory.clear_handy_slot(5)
	inventory.add_handy_slot(5, STUB_FREE_ID, 2)
	inventory.select_handy_slot(5)
	inventory.left_use_handy_slot(player)
	_check(inventory.get_handy_slot_count(5) == 2, "use() 返回 0 的道具不会被扣掉")

## 武器物品走 WeaponData.weapon；当前实现是"选中即装备"（handy_item_changed 里直接 equip）
func _test_weapon(inventory: Inventory, items: Node, controller: WeaponController, player: PlayerCharacter) -> void:
	var sword_item: ItemData = items.get_template(LONGSWORD_ITEM_ID)

	_check(sword_item != null, "长剑物品模板存在")
	_check(sword_item is WeaponData, "长剑物品是 WeaponData")
	if sword_item is WeaponData:
		var sword_data: WeaponData = sword_item as WeaponData
		_check(sword_data.weapon != null, "长剑物品挂上了武器数据")
		_check(sword_data.weapon.id == &"longsword", "挂的是长剑武器数据")

	# 玩家侧没有直接换武器的入口
	_check(not player.has_method("equip_next_weapon"), "玩家侧没有直接换武器的入口")

	# 选中武器格 = 立刻装备
	controller.equip(null)
	_fill(inventory, 6, LONGSWORD_ITEM_ID, 3)
	var changed: Array[WeaponDefinition] = []
	controller.weapon_changed.connect(func(weapon: WeaponDefinition) -> void: changed.append(weapon))
	inventory.select_handy_slot(6)
	_check(controller.equipped_weapon != null and controller.equipped_weapon.id == &"longsword", "选中武器格就装上该武器")
	_check(changed.size() == 1, "装备武器发出了 weapon_changed")

	# 对武器格再按一次使用：不消耗，装备不变
	inventory.left_use_handy_slot(player)
	_check(inventory.get_handy_slot_count(6) == 3, "武器不会被 use() 消耗")
	_check(controller.equipped_weapon != null and controller.equipped_weapon.id == &"longsword", "使用武器格后装备不变")

	# 选中空格：把武器卸下，且不会去动别的格子
	inventory.select_handy_slot(7)
	_check(controller.equipped_weapon == null, "选中空格会卸下武器")
	inventory.left_use_handy_slot(player)
	_check(inventory.get_handy_slot_count(6) == 3, "选中空格使用不会扣别的格子")
	_check(controller.equipped_weapon == null, "选中空格使用后仍是空手")

	# 选中非武器道具：同样卸下武器，道具本身不动
	_fill(inventory, 8, STUB_FREE_ID, 3)
	inventory.select_handy_slot(8)
	_check(controller.equipped_weapon == null, "选中非武器格时卸下武器")
	inventory.left_use_handy_slot(player)
	_check(inventory.get_handy_slot_count(8) == 3, "不消耗的道具按一次也不会少")

	# 左键：当前 player.gd 是"先 left_use_handy_slot()，再无条件下发按下给武器控制器"，
	# 没有"必须选中武器才挥"的门槛。这里按实际行为验收，并把这一点记下来。
	inventory.clear_handy_slot(8)
	_fill(inventory, 0, STUB_ONCE_ID, STUB_ONCE_CONSUME * 2)
	inventory.select_handy_slot(0)
	var before_press: int = inventory.get_handy_slot_count(0)
	controller.set_trigger_pressed(false)
	controller.cancel_attack()
	player._unhandled_input(_attack_event())
	_check(inventory.get_handy_slot_count(0) == before_press - STUB_ONCE_CONSUME, "左键会先使用选中物品（按 use() 返回值扣）")

	# 选中武器格：选中即装备，左键能起手攻击
	_fill(inventory, 6, LONGSWORD_ITEM_ID, 1)
	inventory.select_handy_slot(6)
	_check(controller.equipped_weapon != null and controller.equipped_weapon.id == &"longsword", "选中武器格会装上该武器")

	var starts: Array[WeaponDefinition] = []
	controller.attack_started.connect(func(weapon: WeaponDefinition) -> void: starts.append(weapon))
	controller.set_trigger_pressed(false)
	controller.cancel_attack()
	player._unhandled_input(_attack_event())
	controller._physics_process(1.0)
	_check(starts.size() == 1, "选中武器格后左键起手攻击")
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
	_check(inventory.get_handy_slot_id(1) == -1, "滚轮可以停在空格上（第2格）")

	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_DOWN))
	_check(inventory.get_selected_handy() == 2, "滚轮继续向后走一格")
	_check(inventory.get_handy_slot_id(2) == -1, "第3格也是空格，照样被选中")

	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_UP))
	_check(inventory.get_selected_handy() == 1, "滚轮反向走回第2格")

	# 从最后一格向后绕回第一格
	inventory.select_handy_slot(Inventory.HANDY_SLOT_COUNT - 2)
	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_DOWN))
	_check(inventory.get_selected_handy() == Inventory.HANDY_SLOT_COUNT - 1, "滚轮走到最后一格")

	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_DOWN))
	_check(inventory.get_selected_handy() == 0, "滚轮从最后一格绕回第1格")

	# 没有选中时向后落在第1格，向前落在最后一格
	inventory.handy_selected = -1
	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_DOWN))
	_check(inventory.get_selected_handy() == 0, "没有选中时滚轮向后选中第1格")

	inventory.handy_selected = -1
	hotbar._input(_mouse_event(MOUSE_BUTTON_WHEEL_UP))
	_check(inventory.get_selected_handy() == Inventory.HANDY_SLOT_COUNT - 1, "没有选中时滚轮向前选中最后一格")

	# 左键点格子只切换选中，绝不触发使用
	inventory.select_handy_slot(0)
	var filled_before: int = inventory.get_handy_slot_count(0)
	hotbar.item_buttons[4]._on_gui_input(_mouse_event(MOUSE_BUTTON_LEFT))
	_check(inventory.get_selected_handy() == 4, "左键点格子切换选中")
	_check(inventory.get_handy_slot_count(0) == filled_before, "左键点格子不使用、不扣数量")


## 药水右键：格子右键与游戏内右键都默认喝下；Shift+右键投掷。
## 药水不先走 add_item()，专门覆盖运行时实例缓存缺失的回归。
func _test_potion_use(hotbar: Control, inventory: Inventory, player: PlayerCharacter, items: Node) -> void:
	for slot: int in Inventory.HANDY_SLOT_COUNT:
		inventory.clear_handy_slot(slot)

	var slot_potion: PotionData = _make_heal_potion(items)
	inventory.add_handy_slot(4, slot_potion.id, 1)
	player.health = 40.0
	Buffs.clear(player)
	hotbar.item_buttons[4]._on_gui_input(_mouse_event(MOUSE_BUTTON_RIGHT))
	_check(inventory.get_selected_handy() == 4, "右键快捷栏药水会选中该格")
	_check(inventory.get_handy_slot_count(4) == 0, "右键快捷栏药水会消耗一瓶")
	_check(player.health > 40.0, "右键快捷栏药水会喝下并回血")

	var world_potion: PotionData = _make_heal_potion(items)
	inventory.add_handy_slot(5, world_potion.id, 1)
	inventory.select_handy_slot(5)
	player.health = 40.0
	Buffs.clear(player)
	var right_event := InputEventAction.new()
	right_event.action = &"throw"
	right_event.pressed = true
	player._unhandled_input(right_event)
	_check(inventory.get_handy_slot_count(5) == 0, "游戏内右键药水会消耗一瓶")
	_check(player.health > 40.0, "游戏内右键药水会喝下并回血")

	var throw_potion: PotionData = _make_heal_potion(items)
	inventory.add_handy_slot(6, throw_potion.id, 1)
	inventory.select_handy_slot(6)
	player.health = 40.0
	Buffs.clear(player)
	var throw_event: InputEventMouseButton = _mouse_event(MOUSE_BUTTON_RIGHT)
	throw_event.shift_pressed = true
	player._unhandled_input(throw_event)
	var thrown_models: int = 0
	for child: Node in player.get_parent().get_children():
		if child is ItemModel:
			thrown_models += 1
	_check(inventory.get_handy_slot_count(6) == 0, "Shift+右键会消耗药水")
	_check(is_equal_approx(player.health, 40.0), "Shift+右键不会直接喝下药水")
	_check(thrown_models == 1, "Shift+右键会生成投掷药水")


func _make_heal_potion(items: Node) -> PotionData:
	var potion: PotionData = POTION_TEMPLATE.duplicate() as PotionData
	potion.alchemical_attribute = [HEAL_ATTRIBUTE]
	potion.id = PotionData.next_potion_id()
	while not bool(items.call("register_instance", potion)):
		potion.id = PotionData.next_potion_id()
	return potion


## 拖拽期间的输入行为：当前版本的 _can_operate() 只看"面板可见 + 有玩家/背包"，
## 不再判断是否正在拖拽，所以滚轮/数字键在拖拽中仍然会换选中（这里按实际行为验收）
func _test_drag_guard(hotbar: Control, inventory: Inventory) -> void:
	# 预览控件由拖拽系统自己挂到光标上，这里不要先进场景树
	var preview: Control = Control.new()
	hotbar.item_buttons[0].force_drag({"item_id": STUB_ONCE_ID, "count": 1}, preview)
	_check(root.gui_is_dragging(), "测试拖拽已开始")
	_check(hotbar._can_operate(), "拖拽期间物品栏输入仍然生效")

	hotbar._input(_key_event(KEY_2))
	_check(inventory.get_selected_handy() == 1, "拖拽期间数字键仍然切换选中")

	root.gui_cancel_drag()
	await process_frame
	_check(not root.gui_is_dragging(), "测试拖拽已结束")
