extends SceneTree

## 武器附魔验收：
##   1) 数据规则：只有 can_be_weapon_enchant 的属性上得了武器；
##      同 attribute_id 只有更高等级顶替，同级/低级整条忽略（不会回退）；
##   2) 拖放判定：药水拖到武器上，等级够才收下，不够直接拒绝（药水自动回原格）；
##   3) 附魔把模板武器变成独立实例(400+)，共享模板不被污染；
##   4) 附魔后手持武器换成带附魔的那把，药水被消耗、运行时实例被注销；
##   5) 命中时附魔属性真的作用出去：WIELDER 作用到持武器的人，HIT_TARGET 作用到被打的目标；
##   6) 背包里同款武器堆叠时，一次附魔只换走一份，剩下的还留在原 id。
##
## 运行：godot --headless --path . --script res://tools/test_weapon_enchant.gd

const GAME_SCENE: String = "res://scenes/game/game_world.tscn"
const DUMMY_SCENE: String = "res://scenes/combat/training_dummy.tscn"
## 开局快捷栏第1格的长剑(模板 id)
const LONGSWORD_TEMPLATE_ID: int = 200
## 开局背包里的长棍(模板 id)
const LONG_STAFF_TEMPLATE_ID: int = 201
## AlchemicalAttributeList.ATTRIBUTE 的取值；用字面量，避免 --script 模式依赖自动加载标识符
const ATTRIBUTE_HOLY: int = 1
const ATTRIBUTE_CONTINUOUS_HEAL: int = 2
const ATTRIBUTE_MINERAL: int = 3
const ATTRIBUTE_EXPLOSIVE: int = 6

var _checks: int = 0
var _failures: int = 0
var _items: Node = null
var _attributes: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _attribute(attribute_id: int, level: int) -> AlchemicalData:
	return _attributes.call("create", attribute_id, level) as AlchemicalData


##造一瓶只用于测试的药水，登记成运行时实例
func _make_potion(potion_attributes: Array[AlchemicalData]) -> PotionData:
	var template: PotionData = _items.call("get_template", PotionData.NEW_POTION_ID) as PotionData
	var potion: PotionData = template.duplicate() as PotionData
	potion.alchemical_attribute = potion_attributes
	potion.id = PotionData.next_potion_id()
	while not bool(_items.call("register_instance", potion)):
		potion.id = PotionData.next_potion_id()
	return potion


## 1) 纯数据规则
func _test_enchant_rules() -> void:
	var definition := WeaponDefinition.new()
	_check(definition.enchant_attributes.is_empty(), "新武器没有附魔")

	var explosive_lv0: AlchemicalData = _attribute(ATTRIBUTE_EXPLOSIVE, 0)
	var explosive_lv2: AlchemicalData = _attribute(ATTRIBUTE_EXPLOSIVE, 2)
	var holy_lv0: AlchemicalData = _attribute(ATTRIBUTE_HOLY, 0)

	_check(definition.add_enchant(explosive_lv0), "第一次附魔成功")
	_check(definition.enchant_attributes.size() == 1, "武器上有一条附魔")
	_check(not definition.can_enchant_with(explosive_lv0), "同级判定为不可附魔")
	_check(not definition.add_enchant(explosive_lv0), "同等级再附魔不生效")

	_check(definition.add_enchant(explosive_lv2), "更高等级顶替原附魔")
	_check(definition.enchant_attributes.size() == 1, "同属性只保留一条")
	_check(definition.enchant_attributes[0].level == 2, "等级被顶到 2")

	_check(not definition.add_enchant(explosive_lv0), "低级药水整条忽略(不回退)")
	_check(definition.enchant_attributes[0].level == 2, "低级药水没有改动已有附魔")

	_check(definition.add_enchant(holy_lv0), "不同属性可以叠加")
	_check(definition.enchant_attributes.size() == 2, "武器上现在有两条附魔")

	# 只有 can_be_weapon_enchant 的属性才上得了武器：炼药属性(矿物这类)默认 false
	var mineral_lv0: AlchemicalData = _attribute(ATTRIBUTE_MINERAL, 0)
	_check(not mineral_lv0.can_be_weapon_enchant, "炼药属性默认不允许武器附魔")
	_check(not definition.can_enchant_with(mineral_lv0), "默认 false 的属性附不上去")
	_check(not definition.add_enchant(mineral_lv0), "默认 false 的属性附魔不生效")
	_check(definition.enchant_attributes.size() == 2, "被拒绝的属性没有进附魔表")


## 2) 拖放判定：够级才收，不够让拖拽失败
func _test_drop_guard(inventory: Inventory, hotbar: Control) -> void:
	var button: SlotButton = hotbar.item_buttons[0]
	_check(button.slot_item != null and button.slot_item.item is WeaponData, "快捷栏第1格是武器")

	var high_potion: PotionData = _make_potion([_attribute(ATTRIBUTE_HOLY, 2)])
	var low_potion: PotionData = _make_potion([_attribute(ATTRIBUTE_HOLY, 0)])
	var other_potion: PotionData = _make_potion([_attribute(ATTRIBUTE_EXPLOSIVE, 1)])
	inventory.add_item(high_potion.id, 1)
	inventory.add_item(low_potion.id, 1)
	inventory.add_item(other_potion.id, 1)

	_check(inventory.enchant_handy_weapon(0, high_potion.id), "用 2 级神圣药水附魔成功")

	var low_payload: Dictionary = {"item_id": low_potion.id, "count": 1}
	var other_payload: Dictionary = {"item_id": other_potion.id, "count": 1}
	_check(not button._can_drop_data(Vector2.ZERO, low_payload), "低级同类药水被拖放判定拒绝")
	_check(button._can_drop_data(Vector2.ZERO, other_payload), "不同属性药水可以通过拖放判定")

	_check(not inventory.enchant_handy_weapon(0, low_potion.id), "低级同类药水附魔失败")
	_check(inventory.get_count(low_potion.id) == 1, "失败的药水留在背包里，没被消耗")

	_check(inventory.enchant_handy_weapon(0, other_potion.id), "不同属性药水附魔成功")
	_check(inventory.get_count(other_potion.id) == 0, "成功的药水被消耗掉")


## 3) 实例化 / 不污染模板 / 手持武器换成带附魔的那把
func _test_instance_and_equip(inventory: Inventory, player: PlayerCharacter) -> void:
	var instance_id: int = inventory.get_handy_slot_id(0)
	_check(instance_id >= WeaponData.INSTANCE_ID_START, "附魔后的武器拿到了实例 id(%d)" % instance_id)
	_check(instance_id != LONGSWORD_TEMPLATE_ID, "快捷栏里的 id 不再是模板 id")

	var template_item: WeaponData = _items.call("get_template", LONGSWORD_TEMPLATE_ID) as WeaponData
	_check(template_item.weapon.enchant_attributes.is_empty(), "共享模板没有被污染")

	var instance: WeaponData = _items.call("get_template", instance_id) as WeaponData
	_check(instance != null and instance.weapon != template_item.weapon, "实例有自己独立的武器定义")
	_check(instance.weapon.enchant_attributes.size() == 2, "实例上带着两条附魔(神圣+爆炸)")

	_check(player.weapon_controller.equipped_weapon == instance.weapon,
			"附魔后手持武器换成了带附魔的那把")


## 4) 真实拖放路径：格子的 _drop_data -> 宿主 -> 背包附魔（快捷栏与背包各走一遍）
func _test_ui_drop_path(game: Node2D, inventory: Inventory, hotbar: Control) -> void:
	#快捷栏里的附魔武器再加一条爆炸，把它顶到 2 级
	var hotbar_potion: PotionData = _make_potion([_attribute(ATTRIBUTE_EXPLOSIVE, 2)])
	inventory.add_item(hotbar_potion.id, 1)

	var button: SlotButton = hotbar.item_buttons[0]
	button._drop_data(Vector2.ZERO, {"item_id": hotbar_potion.id, "count": 1})

	_check(inventory.get_count(hotbar_potion.id) == 0, "拖放到快捷栏武器上消耗了药水")

	var instance: WeaponData = _items.call("get_template", inventory.get_handy_slot_id(0)) as WeaponData
	var explosive_level: int = -1
	for attribute: AlchemicalData in instance.weapon.enchant_attributes:
		if attribute.attribute_id == ATTRIBUTE_EXPLOSIVE:
			explosive_level = attribute.level
	_check(explosive_level == 2, "拖放把爆炸附魔顶到了 2 级")
	_check(instance.weapon.enchant_attributes.size() == 2, "同属性仍然只占一条")

	#背包里的模板武器也能被药水附魔
	var bag: Control = game.get_node("GameHUD/BagUi")
	_check(bag.item_for_button.has(LONG_STAFF_TEMPLATE_ID), "背包里有开局的长棍")

	var bag_potion: PotionData = _make_potion([_attribute(ATTRIBUTE_HOLY, 1)])
	inventory.add_item(bag_potion.id, 1)
	bag.item_for_button[LONG_STAFF_TEMPLATE_ID]._drop_data(Vector2.ZERO, {"item_id": bag_potion.id, "count": 1})

	_check(inventory.get_count(bag_potion.id) == 0, "背包附魔消耗了药水")
	_check(inventory.get_count(LONG_STAFF_TEMPLATE_ID) == 0, "背包里的模板武器记录被换掉")
	_check(not bag.item_for_button.has(LONG_STAFF_TEMPLATE_ID), "旧的背包格子被收掉")

	var staff_template: WeaponData = _items.call("get_template", LONG_STAFF_TEMPLATE_ID) as WeaponData
	_check(staff_template.weapon.enchant_attributes.is_empty(), "长棍模板没有被污染")

	var staff_instance: int = 0
	for item_id: int in inventory.has_items:
		if item_id >= WeaponData.INSTANCE_ID_START and (_items.call("get_template", item_id) as WeaponData).name == staff_template.name:
			staff_instance = item_id
	_check(staff_instance > 0 and bag.item_for_button.has(staff_instance), "背包里出现附魔后的长棍实例")


## 5) 命中时附魔真的作用出去
func _test_hit_effects(game: Node2D, player: PlayerCharacter) -> void:
	var template_item: WeaponData = _items.call("get_template", LONGSWORD_TEMPLATE_ID) as WeaponData
	var definition: WeaponDefinition = template_item.weapon.duplicate(true) as WeaponDefinition

	var heal: AlchemicalData = _attribute(ATTRIBUTE_CONTINUOUS_HEAL, 1)
	_check(heal.enchant_target == AlchemicalData.EnchantTarget.WIELDER, "恢复属性配置为对持有者生效")
	_check(definition.add_enchant(heal), "把恢复附到武器上")

	var attack: WeaponAttack = definition.attack_scene.instantiate() as WeaponAttack
	player.add_child(attack)
	attack.start(definition, player, 1, Vector2.RIGHT)

	var dummy: TrainingDummy = (load(DUMMY_SCENE) as PackedScene).instantiate() as TrainingDummy
	game.add_child(dummy)
	dummy.global_position = player.global_position + Vector2(16.0, 0.0)
	await physics_frame

	var hurtbox: CombatHurtbox = dummy.get_node("Hurtbox") as CombatHurtbox
	var dummy_health: float = dummy.health.current_health
	attack._land_hit(hurtbox)
	_check(dummy.health.current_health < dummy_health, "命中照常结算伤害")
	_check(Buffs.has(player, &"regen"), "恢复附魔命中后作用到持武器的人身上")
	_check(not Buffs.has(dummy, &"regen"), "对持有者生效的属性不会作用到被打的目标")

	#同一把武器再来一条"对目标生效"的恢复，验证目标选择
	var target_definition: WeaponDefinition = definition.duplicate(true) as WeaponDefinition
	var heal_on_target: AlchemicalData = _attribute(ATTRIBUTE_CONTINUOUS_HEAL, 1)
	heal_on_target.enchant_target = AlchemicalData.EnchantTarget.HIT_TARGET
	_check(target_definition.add_enchant(heal_on_target), "把对目标生效的恢复附到武器上")

	var second_attack: WeaponAttack = target_definition.attack_scene.instantiate() as WeaponAttack
	player.add_child(second_attack)
	second_attack.start(target_definition, player, 1, Vector2.RIGHT)
	second_attack._land_hit(hurtbox)
	_check(Buffs.has(dummy, &"regen"), "对目标生效的属性作用到被打的目标身上")


## 6) 背包里同款武器堆叠时，附魔只换走一份
func _test_stacked_weapon_enchant(game: Node2D, inventory: Inventory) -> void:
	var bag: Control = game.get_node("GameHUD/BagUi")
	var potion: PotionData = _make_potion([_attribute(ATTRIBUTE_EXPLOSIVE, 1)])

	inventory.add_item(LONG_STAFF_TEMPLATE_ID, 2)
	inventory.add_item(potion.id, 1)
	_check(inventory.get_count(LONG_STAFF_TEMPLATE_ID) == 2, "背包里堆着两把同款武器")

	var ids_before: Array[int] = []
	for item_id: int in inventory.has_items:
		ids_before.append(item_id)

	_check(inventory.enchant_bag_weapon(LONG_STAFF_TEMPLATE_ID, potion.id), "堆叠的武器可以附魔")

	var instance_id: int = -1
	for item_id: int in inventory.has_items:
		if item_id >= WeaponData.INSTANCE_ID_START and not ids_before.has(item_id):
			instance_id = item_id

	_check(instance_id > 0, "出现附魔后的武器实例")
	_check(inventory.get_count(instance_id) == 1, "附魔实例只占一份，没把整堆搬过去")
	_check(inventory.get_count(LONG_STAFF_TEMPLATE_ID) == 1, "同款模板武器还剩一份")
	_check(inventory.get_count(potion.id) == 0, "只消耗了一瓶药水")
	_check(bag.item_for_button.has(LONG_STAFF_TEMPLATE_ID), "原武器格子没被收掉")
	_check(bag.item_for_button[LONG_STAFF_TEMPLATE_ID].slot_item.count == 1, "原武器格子显示还剩 1 把")
	_check(bag.item_for_button.has(instance_id), "附魔实例有自己的格子")


func _run() -> void:
	Engine.max_fps = 120
	root.size = Vector2i(1280, 720)
	_items = root.get_node("ItemListGlobal")
	_attributes = root.get_node("AlchemicalAttributeList")

	var game: Node2D = (load(GAME_SCENE) as PackedScene).instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	var player: PlayerCharacter = game.get_node("Player") as PlayerCharacter
	player.set_physics_process(false)
	game.get_node("MonsterSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	await physics_frame
	await physics_frame

	var inventory: Inventory = player.inventory
	var hotbar: Control = game.get_node("GameHUD/BottomBagUi")

	_test_enchant_rules()
	await _test_drop_guard(inventory, hotbar)
	await _test_instance_and_equip(inventory, player)
	await _test_ui_drop_path(game, inventory, hotbar)
	_test_stacked_weapon_enchant(game, inventory)
	await _test_hit_effects(game, player)

	print("WEAPON_ENCHANT: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)