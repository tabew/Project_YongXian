extends SceneTree

## 炸弹材料（材料 id 5 / 属性 id 6）的验收：
## 材料模板与模型、爆裂属性注册、丢进坩埚能带进爆裂并装瓶、扔出去的范围伤害只打敌人。
##
## 运行：godot --headless --path . --script res://tools/test_bomb_material.gd
##
## 和仓库里其它 --script 验收一样：注册表用 root.get_node 取，
## 不写 ItemListGlobal / AlchemicalAttributeList 这两个自动加载标识符，
## 也不 preload 会引用它们的脚本（编译期拿不到这些单例）。

const BOMB_PATH: String = "res://resources/items/ingredients/bomb.tres"
const EXPLOSIVE_SCRIPT_PATH: String = "res://scripts/alchemical_attribute/explosive.gd"
const CAULDRON_PATH: String = "res://scenes/alchemy/cauldon.tscn"
const ATTRIBUTES_TEXT_PATH: String = "res://scenes/ui/alchemy/attributes_text.tscn"

const BOMB_ID: int = 5
const EXPLOSIVE_ID: int = 6
const EXPLOSIVE_NAME: String = "爆炸"
const TARGET_HEALTH: float = 1000.0

var _checks: int = 0
var _failures: int = 0
var _items: Node
var _attributes: Node
var _explosive_script: GDScript
var _arena: Node2D


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _sync_physics() -> void:
	await physics_frame
	await physics_frame


## 造一个带受击盒的目标，层级和阵营仿照正式怪物（敌方 = 阵营 2 / Layer 3 = 值 4）
func _target(at: Vector2, team: int = 2, layer: int = 4) -> HealthComponent:
	var target: Node2D = Node2D.new()
	target.position = at
	var component: HealthComponent = HealthComponent.new()
	component.max_health = TARGET_HEALTH
	target.add_child(component)
	var hurtbox: CombatHurtbox = CombatHurtbox.new()
	hurtbox.health = component
	hurtbox.team = team
	hurtbox.collision_layer = layer
	hurtbox.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 4.0
	shape_node.shape = shape
	hurtbox.add_child(shape_node)
	target.add_child(hurtbox)
	_arena.add_child(target)
	return component


## 在 at 处引爆一次属性：药水破碎时传进来的就是这个位置上的 Node2D
func _blast(attribute: AlchemicalData, at: Vector2) -> void:
	var center: Node2D = Node2D.new()
	_arena.add_child(center)
	center.global_position = at
	attribute.use_effect(center)


func _test_material() -> IngredientData:
	var bomb: IngredientData = load(BOMB_PATH) as IngredientData
	_check(bomb != null, "炸弹材料能载入")
	if bomb == null:
		return null

	_check(bomb.id == BOMB_ID, "炸弹的材料 id 是 %d" % BOMB_ID)
	_check(bomb.name == "炸弹", "炸弹的名字是炸弹")
	_check(bomb.texture != null, "炸弹有图标")
	_check(bomb.alchemical_attribute.size() >= 1, "炸弹至少带一条炼金属性")
	var bomb_has_explosive: bool = false

	for attribute: AlchemicalData in bomb.alchemical_attribute:
		bomb_has_explosive = bomb_has_explosive or (attribute != null and attribute.get_script() == _explosive_script)
	_check(bomb_has_explosive, "炸弹带的属性里有爆裂")
	_check(is_same(_items.get_template(BOMB_ID), bomb), "炸弹登记在材料注册表 id=%d" % BOMB_ID)

	var model: ItemModel = bomb.create_model()
	_check(model != null, "炸弹材料能造出模型")
	if model != null:
		_check(model.data == bomb, "模型带着炸弹数据")
		_check(model.collision_layer == 8, "模型在炼金层，能丢进坩埚")
		model.free()
	return bomb


func _test_attribute() -> void:
	var created: AlchemicalData = _attributes.create(EXPLOSIVE_ID, 1)
	_check(created != null, "按 id %d 能从属性注册表造出爆裂" % EXPLOSIVE_ID)
	if created == null:
		return
	_check(created.get_script() == _explosive_script, "注册表 id %d 指向爆裂脚本" % EXPLOSIVE_ID)
	_check(created.name == EXPLOSIVE_NAME, "爆裂属性名字正确")
	_check(created.level == 1 and created.max_level == 3, "爆裂属性等级与上限正确")
	_check((created as Explosive).enemy_damage() > 0.0 and (created as Explosive).blast_radius() > 0.0, "爆裂属性配了伤害与半径")


func _test_blast_damage() -> void:
	var explosive: AlchemicalData = _attributes.create(EXPLOSIVE_ID, 1)
	var damage: float = (explosive as Explosive).enemy_damage()
	var radius: float = (explosive as Explosive).blast_radius()

	var near: HealthComponent = _target(Vector2(30, 0))
	var edge: HealthComponent = _target(Vector2(0, radius * 0.9))
	var outside: HealthComponent = _target(Vector2(radius * 1.5, 0))
	var friendly: HealthComponent = _target(Vector2(20, 0), 1)
	var wrong_layer: HealthComponent = _target(Vector2(20, 0), 2, 2)
	await _sync_physics()
	_blast(explosive, Vector2.ZERO)
	_check(is_equal_approx(near.current_health, TARGET_HEALTH - damage), "半径内的敌人吃到一次爆炸伤害")
	_check(is_equal_approx(edge.current_health, TARGET_HEALTH - damage), "半径边缘内的敌人也吃到伤害")
	_check(is_equal_approx(outside.current_health, TARGET_HEALTH), "半径外的目标不受影响")
	_check(is_equal_approx(friendly.current_health, TARGET_HEALTH), "同阵营不会被炸到")
	# 重写后的爆炸会同时结算玩家自伤（见 explode_effect.detonate 与 player_damage），
	# 所以命中范围包含玩家受击层，敌我改由阵营判定，而不是只认敌人受击层。
	_check(wrong_layer.current_health < TARGET_HEALTH, "玩家层上的敌对目标同样会被爆炸波及")

	#等级越高炸得越疼：锅里出来的属性至少 1 级
	var leveled: AlchemicalData = _attributes.create(EXPLOSIVE_ID, 3)
	var leveled_target: HealthComponent = _target(Vector2(20, 0))
	await _sync_physics()
	_blast(leveled, Vector2.ZERO)
	_check(is_equal_approx(leveled_target.current_health, TARGET_HEALTH - (leveled as Explosive).enemy_damage()), "3 级爆裂按自身伤害结算")
	_check((leveled as Explosive).enemy_damage() > damage and (leveled as Explosive).blast_radius() >= radius, "等级越高爆裂威力与半径不降低")


func _test_cauldron(bomb: IngredientData) -> void:
	if bomb == null:
		return

	#坩埚的 AttributesText 在正式场景里由 alchemy.tscn 挂上去，这里自己补一个
	var cauldron: Node = (load(CAULDRON_PATH) as PackedScene).instantiate()
	var texts: Control = (load(ATTRIBUTES_TEXT_PATH) as PackedScene).instantiate()
	texts.name = "AttributesText"
	cauldron.add_child(texts)
	_arena.add_child(cauldron)
	var inventory: Inventory = Inventory.new()
	cauldron.set("inventory", inventory)

	var model: ItemModel = bomb.create_model()
	cauldron.add_child(model)
	cauldron.call("_get_attributes", model)

	var attributes: Array = cauldron.get("attributes")
	var cauldron_has_explosive: bool = false

	for attribute: AlchemicalData in attributes:
		cauldron_has_explosive = cauldron_has_explosive or (attribute != null and attribute.get_script() == _explosive_script)
	_check(attributes.size() >= 1, "炸弹丢进坩埚至少带进一条属性")
	_check(cauldron_has_explosive, "带进锅里的有爆裂")
	_check(attributes[0].level == 1, "材料自带的属性进锅后是 1 级")

	cauldron.call("start_transform")
	_check(cauldron.get("attributes").size() >= 1, "爆裂不参与反应，反应完还留在锅里")
	_check(cauldron.call("can_finish_transform"), "锅里有属性就能装瓶")

	var potion: PotionData = cauldron.call("finish_transform")
	_check(potion != null, "装瓶得到药水")
	if potion == null:
		return
	var potion_explosive: Explosive = null

	for attribute: AlchemicalData in potion.alchemical_attribute:
		if attribute != null and attribute.get_script() == _explosive_script:
			potion_explosive = attribute as Explosive
	_check(potion_explosive != null, "药水带上了爆裂属性")
	_check(inventory.get_count(potion.id) == 1, "药水进了背包")
	_check(cauldron.get("attributes").is_empty(), "装瓶后清锅")

	#带爆裂的药水扔出去就是炸弹：砸碎点引爆一次
	var victim: HealthComponent = _target(Vector2(24, 0))
	await _sync_physics()
	if potion_explosive == null:
		return
	var damage: float = potion_explosive.enemy_damage()
	_blast(potion_explosive, Vector2.ZERO)
	_check(is_equal_approx(victim.current_health, TARGET_HEALTH - damage), "带爆裂的药水砸碎会炸")


func _run() -> void:
	_items = root.get_node("ItemListGlobal")
	_attributes = root.get_node("AlchemicalAttributeList")
	_explosive_script = load(EXPLOSIVE_SCRIPT_PATH) as GDScript
	_check(_explosive_script != null, "爆裂脚本能载入")

	_arena = Node2D.new()
	root.add_child(_arena)

	var bomb: IngredientData = _test_material()
	_test_attribute()
	await _test_blast_damage()
	_test_cauldron(bomb)

	print("炸弹材料验收：%d 项检查，%d 项失败" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
