extends SceneTree

## 检查新材料接入协作者的背包、快捷栏、拖拽旋转和原炼金配方。
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _check_spawn_compatibility(game: Node2D) -> void:
	var spawner: Node2D = game.get_node("MonsterSpawner")
	var config: MapConfig = game._map_config_for_monsters()
	_check(not config.combat_biomes.is_empty(), "正式游戏未使用现有怪物的群系配置")
	for seed_value: int in [1, 18473, 97231, 2147483646]:
		for variant: int in [0, 1]:
			var generator := WorldGenerator.new(seed_value, config, variant)
			var replica := WorldGenerator.new(seed_value, config, variant)
			var content := MapContent.build(generator)
			var combat_count: int = 0
			for spec: MapSpec in generator.map_specs():
				_check(spec.biome_id == replica.map_spec(spec.node_id).biome_id, "怪物群系约束破坏同种子/变体确定性")
				if generator.run.type_of(spec.node_id) not in [RoomType.Kind.COMBAT, RoomType.Kind.BOSS]:
					continue
				_check(content.budget_of(spec.node_id, MapContent.ENEMY) > 0, "战斗/Boss区域缺少刷怪资格")
				combat_count += 1
				var tile: Vector2i = spec.origin + Vector2i(spec.center)
				var accepted: bool = false
				for definition: Resource in spawner.spawn_definitions:
					accepted = accepted or definition.can_spawn_at(generator, tile)
				_check(accepted, "战斗/Boss区域所有现有怪物都被群系拒绝 node=%d" % spec.node_id)
			_check(combat_count > 0, "正式地图缺少战斗区域")
	var forest_only := MapConfig.new()
	forest_only.combat_biomes = PackedInt32Array([Biome.Kind.FOREST])
	var forest_generator := WorldGenerator.new(18473, forest_only)
	for spec: MapSpec in forest_generator.map_specs():
		if forest_generator.run.type_of(spec.node_id) in [RoomType.Kind.COMBAT, RoomType.Kind.BOSS]:
			_check(spec.biome_id == Biome.Kind.FOREST, "雨林保障覆盖了不支持雨林的自定义怪物池")
	var extra: Resource = spawner.spawn_definitions[0].duplicate()
	var desert: Array[int] = [Biome.Kind.DESERT]
	extra.allowed_biomes = desert
	spawner.spawn_definitions.append(extra)
	_check(game._map_config_for_monsters().combat_biomes.has(Biome.Kind.DESERT), "新增怪物群系未自动加入战斗主题")
	extra.allowed_biomes.clear()
	_check(game._map_config_for_monsters().combat_biomes.is_empty(), "不限群系的怪物仍受到地图白名单限制")
	spawner.spawn_definitions.erase(extra)
	var generator: WorldGenerator = game._generator
	var replica := WorldGenerator.new(generator.world_seed, generator.config, generator.variant)
	for spec: MapSpec in generator.map_specs():
		_check(spec.biome_id == replica.map_spec(spec.node_id).biome_id, "实际游戏与区块/小地图采样群系不一致")
		if generator.run.type_of(spec.node_id) not in [RoomType.Kind.COMBAT, RoomType.Kind.BOSS]:
			continue
		var tile: Vector2i = spec.origin + Vector2i(spec.center)
		var monster: Node2D = spawner.spawn_monster(spawner.spawn_definitions[0], tile)
		_check(monster != null, "实际战斗区域无法实例化协作者的怪物")
		if monster != null:
			monster.queue_free()


func _run() -> void:
	Engine.max_fps = 120
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 18473)
	var scene: PackedScene = load("res://scenes/game/game_world.tscn")
	var game: Node2D = scene.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	var player: PlayerCharacter = game.get_node("Player")
	player.set_physics_process(false)
	game.get_node("MonsterSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	var bag: Control = game.get_node("GameHUD/BagUi")
	var hotbar: Control = game.get_node("GameHUD/BottomBagUi")
	var alchemy: Node2D = game.get_node("GameHUD/Alchemy")
	var inventory: Inventory = player.inventory
	var old_herb: int = inventory.get_count(0)
	var old_testherb: int = inventory.get_count(1)
	var items: Node = root.get_node("ItemListGlobal")
	var attributes: Node = root.get_node("AlchemicalAttributeList")
	_check_spawn_compatibility(game)
	for id: int in [0, 1, 2, 3]:
		_check(items.has_template(id), "原物品或新物品模板缺失 id=%d" % id)
	for id: int in [0, 1, 2, 3, 4, 5]:
		_check(attributes.get_template(id) != null, "原属性或新属性模板缺失 id=%d" % id)
	inventory.add_item(2, 4)
	inventory.add_item(3, 6)
	_check(inventory.get_handy_slot_id(0) == 200 and inventory.get_handy_slot_id(1) == 201, "开局快捷栏未放长剑与长枪")
	for slot: int in range(Inventory.HANDY_SLOT_COUNT):
		inventory.clear_handy_slot(slot)
	_check(bag.item_for_button.has(2) and bag.item_for_button.has(3), "背包UI未显示新材料")
	_check(bag.item_for_button[2].slot_item.count == 4 and bag.item_for_button[3].slot_item.count == 6, "背包UI数量未同步")
	bag.take_item(2, 2)
	hotbar._on_slot_put(2, 2, 0)
	bag.take_item(3, 4)
	hotbar._on_slot_put(3, 4, 1)
	_check(inventory.get_count(2) == 2 and inventory.get_count(3) == 2, "移入快捷栏未扣除背包份数")
	_check(inventory.get_handy_slot_id(0) == 2 and inventory.get_handy_slot_count(0) == 2, "石头未进入快捷栏")
	_check(hotbar.item_buttons[0].slot_item.item_id == 2, "快捷栏石头图标未同步")
	hotbar._on_slot_take(3, 1, 1)
	hotbar._on_slot_swap(3, 1, 1, 0)
	_check(inventory.get_handy_slot_id(0) == 3 and inventory.get_handy_slot_count(0) == 4, "快捷栏交换未保留木棍整堆")
	_check(inventory.get_handy_slot_id(1) == 2 and inventory.get_handy_slot_count(1) == 2, "快捷栏交换未保留石头整堆")
	bag.take_item(3, 2)
	hotbar._on_slot_put(3, 2, 2)
	_check(inventory.get_handy_slot_id(0) == 3 and inventory.get_handy_slot_id(2) == 3 and inventory.get_handy_slot_count(2) == 2, "同类材料不能分占快捷栏格子")
	hotbar._on_slot_take(2, 1, 1)
	bag.put_item(2, 1)
	_check(inventory.get_count(2) == 3 and inventory.get_handy_slot_count(1) == 1, "快捷栏返还背包数量错误")
	var pickup: GroundPickup = null
	for child: Node in game._map_entity_roots[0].get_children():
		if child is GroundPickup:
			pickup = child as GroundPickup
			break
	_check(pickup != null, "测试缺少地面材料")
	if pickup != null:
		player.global_position = pickup.global_position + Vector2(16, 0)
		game._refresh_pickup()
		_check(game._nearby_pickup == pickup, "未拖拽时近处材料不可拾取")
		var count_before: int = inventory.get_count(pickup.data.id)
		var button: Button = hotbar.item_buttons[0]
		var preview := Control.new()
		button.dragged_preview = preview
		button.dragged_data = {"item_id": 3, "count": 1, "rotation": 0.0}
		button.force_drag(button.dragged_data, preview)
		_check(root.gui_is_dragging(), "实际GUI拖拽未启动")
		var event := InputEventKey.new()
		event.physical_keycode = KEY_E
		event.pressed = true
		button._input(event)
		_check(is_equal_approx(preview.rotation_degrees, 6.0) and is_equal_approx(float(button.dragged_data["rotation"]), preview.rotation), "E键未保留原有物品旋转")
		game._unhandled_input(event)
		_check(game._nearby_pickup == null and inventory.get_count(pickup.data.id) == count_before and not pickup.is_queued_for_deletion(), "拖拽旋转时同时拾取了地面物品")
		# force_drag 是程序启动的拖拽，显式取消来验证失败拖拽清理路径。
		root.gui_cancel_drag()
		await process_frame
		_check(not root.gui_is_dragging(), "拖拽未结束")
	var cauldron: Node = alchemy.get_node("Cauldon")
	cauldron.attributes.clear()
	cauldron.attributes.append(attributes.create(0))
	cauldron.attributes.append(attributes.create(1))
	cauldron.start_transform()
	_check(cauldron.attributes.size() == 1 and cauldron.attributes[0].attribute_id == 2, "原治疗+神圣配方不再生成持续治疗")
	cauldron.attributes.clear()
	cauldron.attributes.append(attributes.create(0))
	cauldron.attributes.append(attributes.create(0))
	cauldron.start_transform()
	_check(cauldron.attributes.size() == 1 and cauldron.attributes[0].attribute_id == 0 and cauldron.attributes[0].level == 1, "原治疗升级配方失效")
	_check(inventory.get_count(0) == old_herb and inventory.get_count(1) == old_testherb, "新材料操作改动了原材料库存")
	game._enter_map(2)
	_check(inventory.get_handy_slot_id(0) == 3 and inventory.get_handy_slot_count(0) == 4 and inventory.get_handy_slot_id(1) == 2 and inventory.get_handy_slot_count(1) == 1, "切图未保留快捷栏状态")
	# shift+左键快捷移动：背包与快捷栏之间整堆挪动
	var shift_click := InputEventMouseButton.new()
	shift_click.button_index = MOUSE_BUTTON_LEFT
	shift_click.pressed = true
	shift_click.shift_pressed = true
	var move_count: int = inventory.get_count(4)
	var empty_pos: int = inventory.find_handy_slot_for(4)
	var handy_slots_before: int = inventory.handy_items_pos.size()
	inventory.add_item(4,3)
	_check(bag.item_for_button.has(4), "背包UI未显示快捷移动用的测试材料")
	bag.item_for_button[4]._on_gui_input(shift_click)
	_check(inventory.get_count(4) == move_count, "shift+左键未从背包扣掉整堆材料")
	_check(inventory.get_handy_slot_id(empty_pos) == 4 and inventory.get_handy_slot_count(empty_pos) == move_count + 3, "shift+左键未把整堆材料放进快捷栏空格")
	_check(not bag.item_for_button.has(4), "shift+左键拿完后背包格子未收掉")
	_check(inventory.handy_items_pos.size() == handy_slots_before + 1, "shift+左键改动了别的快捷栏格子")
	hotbar.item_buttons[empty_pos]._on_gui_input(shift_click)
	_check(inventory.get_count(4) == move_count + 3 and inventory.get_handy_slot_id(empty_pos) == -1, "shift+左键未把快捷栏整格挪回背包")
	_check(bag.item_for_button.has(4), "挪回背包后背包未重建格子")
	# 普通左键和shift+右键都不走快捷移动
	var plain_click := InputEventMouseButton.new()
	plain_click.button_index = MOUSE_BUTTON_LEFT
	plain_click.pressed = true
	bag.item_for_button[4]._on_gui_input(plain_click)
	_check(inventory.get_count(4) == move_count + 3, "普通左键触发了快捷移动")
	var shift_right_click := InputEventMouseButton.new()
	shift_right_click.button_index = MOUSE_BUTTON_RIGHT
	shift_right_click.pressed = true
	shift_right_click.shift_pressed = true
	bag.item_for_button[4]._on_gui_input(shift_right_click)
	_check(inventory.get_count(4) == move_count + 3, "shift+右键触发了快捷移动")
	# 快捷栏占满时整堆留在背包里
	for pos in Inventory.HANDY_SLOT_COUNT:
		inventory.clear_handy_slot(pos)
	for pos in Inventory.HANDY_SLOT_COUNT:
		inventory.add_handy_slot(pos,5,1)
	bag.item_for_button[4]._on_gui_input(shift_click)
	_check(inventory.get_count(4) == move_count + 3, "快捷栏占满时shift+左键弄丢了背包材料")
	game.queue_free()
	await process_frame
	await process_frame
	print("INVENTORY_MATERIAL_COMPATIBILITY: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
