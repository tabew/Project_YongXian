extends SceneTree

## 炼金台药水验收：装瓶后药水该进的背包都进了，药水用掉后格子要跟着收，
## 以及药水 id 的登记/号段不能被附魔武器实例撞掉。
##
## 运行：godot --headless --path . --script res://tools/test_alchemy_potion_bag.gd
##
## 背景（这次修的 bug）：炼金界面里那块背包一直开着、不会在打开时重建，
## 而 bag_update 以前只会"加格子/改数量"，从不收掉已经不在背包里的物品，
## 所以炼金台里能看到一瓶其实已经用掉/交出去的药水，正常打开背包（每次打开都重建）却没有。

var _checks: int = 0
var _failures: int = 0
var _world: Node = null
var _genuine_scene: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
	else:
		print("ok: " + message)


## 走一遍真正的装瓶流程：往锅里放属性 → 开始反应 → 装瓶
func _craft(cauldron: Node, attributes: Node, a: int, b: int) -> PotionData:
	cauldron.attributes.clear()
	cauldron.attributes.append(attributes.create(a))
	cauldron.attributes.append(attributes.create(b))
	cauldron.start_transform()
	return cauldron.finish_transform()


## 背包 UI 里显示的格子必须和背包数据一一对应，不能多也不能少
func _slots_match_data(tag: String, bag_ui: Control, inventory: Inventory) -> void:
	var grid: GridContainer = bag_ui.bag_slot_container
	var shown: Dictionary = {}

	for child: Node in grid.get_children():
		var button: SlotButton = child as SlotButton
		if button != null and button.slot_item != null and button.slot_item.item_id >= 0:
			shown[button.slot_item.item_id] = true

	_check(shown.size() == grid.get_child_count(), "%s 网格里没有残留的空壳格子(grid=%d 有效=%d)" % [
		tag, grid.get_child_count(), shown.size()
	])
	_check(shown.size() == bag_ui.item_for_button.size(), "%s 格子数和登记的格数一致" % tag)

	for item_id: int in bag_ui.item_for_button:
		_check(inventory.has_items.has(item_id), "%s 显示的 id %d 还在背包数据里" % [tag, item_id])
		_check(inventory.get_count(item_id) > 0, "%s 显示的 id %d 数量大于0" % [tag, item_id])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 20261)
	var scene: PackedScene = load("res://scenes/game/game_world.tscn")
	var game: Node2D = scene.instantiate() as Node2D
	root.add_child(game)
	_world = game
	game.set_process(false)
	game.get_node("MonsterSpawner").process_mode = Node.PROCESS_MODE_DISABLED

	var player: PlayerCharacter = game.get_node("Player")
	player.set_physics_process(false)
	var bag: Control = game.get_node("GameHUD/BagUi")
	var alchemy: Node2D = game.get_node("GameHUD/Alchemy")
	var alchemy_bag: Control = alchemy.get_node("AlchemicalBag")
	var inventory: Inventory = player.inventory
	var items: Node = root.get_node("ItemListGlobal")
	var attributes: Node = root.get_node("AlchemicalAttributeList")
	var cauldron: Node = alchemy.get_node("Cauldon")

	_check(bag.inventory == inventory and alchemy_bag.inventory == inventory, "两块背包读的是同一份背包数据")
	_check(cauldron.get("inventory") == inventory, "坩埚拿到的是玩家背包")

	#////////////////////////// 号段：药水和附魔武器实例不能撞
	_check(WeaponData.INSTANCE_ID_START < PotionData.NEW_POTION_ID, "药水号段在附魔武器号段之后")
	_check(int(items.get("POTION_INSTANCE_ID_START")) == PotionData.NEW_POTION_ID, "药水实例号段和注册表常量一致")
	#一瓶"丢了登记"的药水也要能取回药水模板，不能变成取不到(背包直接少一格)
	_check(items.get_template(PotionData.NEW_POTION_ID) is PotionData, "没登记的药水号段取回的是药水模板")
	_check(not items.has_template(WeaponData.INSTANCE_ID_START), "没登记的附魔武器号段仍然是非法的")

	#////////////////////////// 装瓶：两个背包都要有
	alchemy.visible = true
	var potion: PotionData = _craft(cauldron, attributes, 0, 1)
	_check(potion != null, "装瓶得到药水")
	if potion == null:
		_finish()
		return

	_check(potion.id >= PotionData.NEW_POTION_ID, "药水 id(%d)在药水实例号段里" % potion.id)
	_check(potion.id < WeaponData.INSTANCE_ID_START or potion.id >= PotionData.NEW_POTION_ID, "药水 id 不落在附魔武器号段")
	_check(items.has_runtime_instance(potion.id), "药水装瓶时登记了运行时 id")
	_check(items.get_template(potion.id) == potion, "注册表按 id 取回的就是这瓶药水")
	_check(inventory.has_items.has(potion.id) and inventory.get_count(potion.id) == 1, "药水进了背包数据")
	_check(inventory.get_item_data.get(potion.id) == potion, "背包按 id 解析到的是这瓶药水")
	_check(alchemy_bag.item_for_button.has(potion.id), "炼金界面背包显示出了药水")

	#正常打开背包
	bag.visible = true
	bag._input_update()
	await process_frame
	_check(bag.item_for_button.has(potion.id), "正常打开背包也显示出了药水")
	_check(bag.item_for_button[potion.id].slot_item.item == potion, "正常背包格子里是这瓶药水的实例")

	#////////////////////////// 药水用完：炼金界面背包不能留残影
	inventory.remove_item(potion.id, 1)
	await process_frame
	_check(!inventory.has_items.has(potion.id), "药水用掉后背包数据里没有了")
	_check(!alchemy_bag.item_for_button.has(potion.id), "炼金界面背包把药水格子收掉了")
	_check(!bag.item_for_button.has(potion.id), "正常背包也把药水格子收掉了")
	_slots_match_data("炼金界面背包", alchemy_bag, inventory)

	#////////////////////////// 投料：锅里那瓶药水还有别的地方在用，id 不能注销
	var kept: PotionData = _craft(cauldron, attributes, 0, 1)
	_check(kept != null, "再装一瓶用于投料")
	if kept != null:
		await process_frame
		var model: ItemModel = kept.create_model()
		_check(model != null, "药水能造出投料用的模型")
		if model != null:
			alchemy.add_child(model)
			#模拟"这瓶药水背包里还留着一份"：同一 id 既在背包里又被丢进锅里
			cauldron.call("_get_attributes", model)
			_check(inventory.get_count(kept.id) > 0, "投料不影响背包里另一份同 id 药水")
			_check(items.has_runtime_instance(kept.id), "背包里还有这份药水时没有注销它的 id")
			_check(items.get_template(kept.id) == kept, "按 id 还能取回这瓶药水本身")
			inventory.remove_item(kept.id, 1)
			await process_frame

	#////////////////////////// 开关背包：同一帧按下+松开只能算一次
	bag.visible = false
	await process_frame
	var press: InputEventKey = InputEventKey.new()
	press.keycode = KEY_TAB
	press.physical_keycode = KEY_TAB
	press.pressed = true
	var release: InputEventKey = press.duplicate() as InputEventKey
	release.pressed = false
	#直接喂给背包的输入处理：模拟同一帧里既收到按下又收到松开
	bag._input(press)
	bag._input(release)
	_check(bag.visible, "同一帧里按下+松开 Tab 也能打开背包（不会开了又关）")
	bag._input(press)
	bag._input(release)
	_check(!bag.visible, "再点一次 Tab 关掉背包")
	bag.visible = false
	await process_frame

	#////////////////////////// 附魔换掉武器 id：炼金界面背包也不能留旧格子
	inventory.add_item(201, 1) #长枪模板
	await process_frame
	var template_id: int = 201
	var staff_slot_potion: PotionData = _craft(cauldron, attributes, 3, 7)
	if staff_slot_potion != null:
		await process_frame
		_check(inventory.get_count(staff_slot_potion.id) == 1, "附魔用的药水现在只有一份")
		_check(inventory.enchant_bag_weapon(template_id, staff_slot_potion.id), "背包里用长枪附魔成功")
		await process_frame
		_check(!inventory.has_items.has(template_id), "模板武器记录被附魔实例换掉了")
		_check(!alchemy_bag.item_for_button.has(template_id), "炼金界面背包收掉了被换掉的模板武器格子")
		_check(!alchemy_bag.item_for_button.has(staff_slot_potion.id), "炼金界面背包收掉了被用掉的药水格子")
		_slots_match_data("炼金界面背包(附魔后)", alchemy_bag, inventory)

	_finish()


func _finish() -> void:
	print("炼金台药水验收：%d 项检查，%d 项失败" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
