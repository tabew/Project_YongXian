extends SceneTree

## 炸弹材料（材料 id 5 / 属性 id 6「爆炸」）的验收：
## 材料与属性注册、丢进坩埚能带进爆炸、装瓶后属性不丢、爆炸的范围伤害与击退。
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
## 敌对受击盒所在层(Layer 3 = EnemyHurtbox = 值 4)，和 training_dummy / base_monster 一致
const ENEMY_HURTBOX_LAYER: int = 4
## 命中掩码之外的层：炼金层(Layer 4 = 值 8)，放这里的受击盒不该被炸到
const OUTSIDE_MASK_LAYER: int = 8
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


## 造一个带受击盒的目标，并把每次实际命中记录下来（伤害、击退都在 CombatHit 上）。
## 层级和阵营仿照正式怪物（敌方 = 阵营 2 / Layer 3 = 值 4）
func _target(at: Vector2, team: int = 2, layer: int = ENEMY_HURTBOX_LAYER) -> Dictionary:
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

	var hits: Array[CombatHit] = []
	component.damaged.connect(func(hit: CombatHit, _amount: float) -> void: hits.append(hit))
	return {"health": component, "hits": hits}


## 在 at 处引爆一次属性：药水/炸弹破碎时传进来的就是这个位置上的 Node2D
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
	_check(bomb.alchemical_attribute.size() == 1, "炸弹只带一条炼金属性")
	if bomb.alchemical_attribute.size() == 1:
		_check(bomb.alchemical_attribute[0].get_script() == _explosive_script, "炸弹带的是爆炸属性")
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
	_check(created != null, "按 id %d 能从属性注册表造出爆炸" % EXPLOSIVE_ID)
	if created == null:
		return

	_check(created.get_script() == _explosive_script, "注册表 id %d 指向爆炸脚本" % EXPLOSIVE_ID)
	_check(created.name == EXPLOSIVE_NAME, "爆炸属性名字正确")
	_check(created.max_level == 3, "爆炸属性等级上限是 3")
	_check(created.need_target == false, "爆炸不需要目标，破碎点直接引爆")
	_check((created.get("damage") as float) > 0.0 and (created.get("explosion_radius") as float) > 0.0,
			"爆炸配了伤害与半径")
	_check(((created.get("hit_mask") as int) & ENEMY_HURTBOX_LAYER) != 0, "爆炸的命中层包含敌对受击盒")
	_check((created.get("knockback") as float) > 0.0, "爆炸配了击退")


func _test_blast_damage() -> void:
	var explosive: AlchemicalData = _attributes.create(EXPLOSIVE_ID, 1)
	var radius: float = explosive.get("explosion_radius") as float
	var damage: float = explosive.call("enemy_damage") as float

	var near: Dictionary = _target(Vector2(30.0, 0.0))
	var edge: Dictionary = _target(Vector2(0.0, radius * 0.9))
	var outside: Dictionary = _target(Vector2(radius * 1.5, 0.0))
	var friendly: Dictionary = _target(Vector2(20.0, 0.0), 1)
	var wrong_layer: Dictionary = _target(Vector2(20.0, 0.0), 2, OUTSIDE_MASK_LAYER)
	await _sync_physics()
	_blast(explosive, Vector2.ZERO)

	_check(is_equal_approx(near["health"].current_health, TARGET_HEALTH - damage), "半径内的敌人吃到一次爆炸伤害")
	_check(is_equal_approx(edge["health"].current_health, TARGET_HEALTH - damage), "半径边缘内的敌人也吃到伤害")
	_check(is_equal_approx(outside["health"].current_health, TARGET_HEALTH), "半径外的目标不受影响")
	_check(is_equal_approx(friendly["health"].current_health, TARGET_HEALTH), "同阵营不会被炸到")
	_check(is_equal_approx(wrong_layer["health"].current_health, TARGET_HEALTH), "命中掩码之外的层不会被炸到")

	#击退：从爆心朝外推，爆心正右侧的目标被往 +X 推
	var near_hits: Array = near["hits"]
	_check(near_hits.size() == 1, "命中记录收到一次爆炸")
	if near_hits.size() == 1:
		var hit: CombatHit = near_hits[0]
		_check(is_equal_approx(hit.damage, damage), "命中伤害等于属性算出来的爆炸伤害")
		_check(hit.knockback.x > 0.0 and absf(hit.knockback.x) >= absf(hit.knockback.y), "击退方向从爆心朝外")
	_check((friendly["hits"] as Array).is_empty() and (outside["hits"] as Array).is_empty(), "被炸不到的目标一次命中都没收到")

	#等级越高炸得越狠
	var leveled: AlchemicalData = _attributes.create(EXPLOSIVE_ID, 3)
	var leveled_damage: float = leveled.call("enemy_damage") as float
	_check(leveled_damage > damage, "3 级爆炸伤害高于 1 级（%s > %s）" % [str(leveled_damage), str(damage)])
	var leveled_target: Dictionary = _target(Vector2(20.0, 0.0))
	await _sync_physics()
	_blast(leveled, Vector2.ZERO)
	_check(is_equal_approx(leveled_target["health"].current_health, TARGET_HEALTH - leveled_damage),
			"高级爆炸打出的是高级伤害")


func _test_cauldron(bomb: IngredientData) -> PotionData:
	if bomb == null:
		return null

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
	_check(attributes.size() == 1, "炸弹丢进坩埚带进一条属性")
	if attributes.size() == 1:
		_check(attributes[0].get_script() == _explosive_script, "带进锅里的就是爆炸")

	cauldron.call("start_transform")
	_check(cauldron.get("attributes").size() == 1, "爆炸不参与反应，反应完还留在锅里")
	_check(cauldron.call("can_finish_transform"), "锅里有属性就能装瓶")

	var potion: PotionData = cauldron.call("finish_transform") as PotionData
	_check(potion != null, "装瓶得到药水")
	if potion == null:
		return null

	_check(potion.alchemical_attribute.size() == 1
			and potion.alchemical_attribute[0].get_script() == _explosive_script, "药水带上了爆炸属性")
	_check(inventory.get_count(potion.id) == 1, "药水进了背包")
	_check(cauldron.get("attributes").is_empty(), "装瓶后清锅")

	#关键：这一瓶进背包后属性不能丢——按 id 取回来还得是同一瓶、还带着爆炸
	var from_bag: ItemData = inventory.get_item_template(potion.id)
	_check(is_same(from_bag, potion), "背包按 id 取回的是同一瓶药水")
	_check(from_bag != null and from_bag.alchemical_attribute.size() == 1, "取回来的这一瓶还带着爆炸属性")

	#带爆炸的药水砸碎就是炸弹：碎点引爆一次
	var victim: Dictionary = _target(Vector2(24.0, 0.0))
	await _sync_physics()
	_blast(potion.alchemical_attribute[0], Vector2.ZERO)
	_check(victim["health"].current_health < TARGET_HEALTH, "带爆炸的药水砸碎会炸")
	return potion


func _run() -> void:
	_items = root.get_node("ItemListGlobal")
	_attributes = root.get_node("AlchemicalAttributeList")
	_explosive_script = load(EXPLOSIVE_SCRIPT_PATH) as GDScript
	_check(_explosive_script != null, "爆炸脚本能载入")

	_arena = Node2D.new()
	root.add_child(_arena)

	var bomb: IngredientData = _test_material()
	_test_attribute()
	await _test_blast_damage()
	await _test_cauldron(bomb)

	print("炸弹材料验收：%d 项检查，%d 项失败" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)