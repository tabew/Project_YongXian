extends ItemData

class_name PotionData

##药水数据由坩埚里反应完的属性装瓶而来
##药水不可堆叠

##药水id的起始值：每瓶药水独占一个 id，号段和附魔武器实例(400 起)分开，
##由 ItemListGlobal.POTION_INSTANCE_ID_START 兜底(未登记的药水 id 也能取回药水模板)
const NEW_POTION_ID:int = 1000

##砸碎后生成的圆形范围场景：只放需要目标的属性，圈内每个目标各调用一次 use_effect
const BURST_SCENE: PackedScene = preload("res://scenes/items/potions/potion_burst.tscn")

const POTION_SPEED:float = 400.0

##基础最大射程(像素)，10 格；升级卡“投掷精通”在它之上乘倍率。
const POTION_MAX_DISTANCE:float = 500.0

##作用效果范围半径(像素)
@export var burst_radius: float = 32.0

##作用效果范围存在时间(秒)：0＝立刻结算一次就消失
@export var burst_duration: float = 10

##本局已经发到哪个药水id了：必须放在静态段，
##静态的 create_from_attributes 只能碰静态成员，实例方法的计数器在它里面用不了
static var _next_potion_id:int = NEW_POTION_ID

## 基模板 id：坩埚与宝箱都用它复制出新的药水实例。
const BASE_TEMPLATE_ID: int = 300
## 随机配方药水最多带几条属性。
const MAX_RANDOM_ATTRIBUTES: int = 3
## 随机配方从这些材料里取属性（ID 与 materials_table 一致，缺 id 的自动跳过）。
const RANDOM_RECIPE_IDS: Array[int] = [
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
	20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37
]


## 随机配方药水：随机取 2~3 种材料，把它们的炼金属性合成一瓶。
## 与坩埚装瓶同一套实现：复制基模板、按 attribute_id 去重取最高等级、发新 id 并注册。
static func create_random(rng: RandomNumberGenerator) -> PotionData:
	var registry: Node = _registry()
	if registry == null:
		return null
	var base: ItemData = registry.call("get_template", BASE_TEMPLATE_ID) as ItemData
	if base == null or not (base is PotionData):
		return null
	var potion: PotionData = (base as PotionData).duplicate() as PotionData
	potion.alchemical_attribute = []
	var pool: Array[int] = RANDOM_RECIPE_IDS.duplicate()
	var picks: int = rng.randi_range(2, 3)
	for index: int in picks:
		# 属性最多三条：材料可能各带两种属性，不封顶会攒到五六条，强度失控。
		if potion.alchemical_attribute.size() >= MAX_RANDOM_ATTRIBUTES:
			break
		if pool.is_empty():
			break
		var pick_index: int = rng.randi_range(0, pool.size() - 1)
		var material_id: int = pool[pick_index]
		pool.remove_at(pick_index)
		var material: IngredientData = registry.call("get_template", material_id) as IngredientData
		if material == null:
			continue
		for attribute: AlchemicalData in material.alchemical_attribute:
			if potion.alchemical_attribute.size() >= MAX_RANDOM_ATTRIBUTES:
				break
			if attribute == null:
				continue
			var existing: AlchemicalData = _find_attribute(potion.alchemical_attribute, attribute.attribute_id)
			if existing == null:
				potion.alchemical_attribute.append(attribute.duplicate())
			elif attribute.level > existing.level:
				existing.level = attribute.level
	if potion.alchemical_attribute.is_empty():
		return null
	potion.name = "无名药水（%s）" % _attribute_summary(potion.alchemical_attribute)
	potion.id = next_potion_id()
	while not bool(registry.call("register_instance", potion)):
		potion.id = next_potion_id()
	return potion


static func _find_attribute(list: Array[AlchemicalData], attribute_id: int) -> AlchemicalData:
	for attribute: AlchemicalData in list:
		if attribute != null and attribute.attribute_id == attribute_id:
			return attribute
	return null


static func _attribute_summary(list: Array[AlchemicalData]) -> String:
	var names: PackedStringArray = PackedStringArray()
	for attribute: AlchemicalData in list:
		if attribute != null:
			names.append(attribute.name)
	return "·".join(names)


## 物品表是自动加载单例：用运行期查找，保证本脚本仍能作为 --script 测试的编译依赖。
static func _registry() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("ItemListGlobal")


static func next_potion_id() -> int:
	var potion_id:int = _next_potion_id
	_next_potion_id += 1

	return potion_id


## 左键喝下：把瓶内全部炼金属性作用到玩家身上。
## “苦行”禁用时返回 0，不消耗药水。
func left_use(player:PlayerCharacter) -> int:
	if player == null or player.potions_blocked():
		return 0

	#是否有护己属性
	var exempt: bool = false

	for attribute: AlchemicalData in alchemical_attribute:
		if attribute != null and attribute.has_method("exempts_user") and attribute.exempts_user():
			exempt = true

	#整瓶药的时长倍率（延时属性叠加），只影响这次施加的 buff
	var scale: float = duration_scale()
	#整瓶药的威力倍率（等级成长 + 药材学），只影响这次结算的数值
	var power: float = player.potion_power_mult()

	for attribute: AlchemicalData in alchemical_attribute:
		if attribute == null or not attribute.has_method("use_effect"):
			continue
		if exempt and attribute.is_negative_effect():
			continue
		Buffs.set_next_duration_scale(scale)
		Buffs.set_next_power_scale(power)
		attribute.use_effect(player)
		Buffs.reset_duration_scale()
		Buffs.reset_power_scale()
	return 1


##整瓶药的时长倍率：延时属性按乘法叠加（没有延时就是 1.0）
func duration_scale() -> float:
	var scale: float = 1.0

	for attribute: AlchemicalData in alchemical_attribute:
		if attribute != null and attribute.has_method("duration_scale_total"):
			scale *= maxf(float(attribute.call("duration_scale_total")), 0.1)
	return scale

##投掷药水，朝准心抛出去，撞到受击盒或地形才碎
##飞行由 PotionProjectile 每物理帧推进(刚体保持冻结，不依赖世界有没有物理地板)
##破碎后在碎点产生作用效果圈，圈内每个目标各调用一次 use_effect；
##不需要目标的属性(need_target = false)不经过范围，直接对碎点上的药水模型调用一次。
func right_use(player:PlayerCharacter) -> int:

	if player == null or player.get_parent() == null or player.potions_blocked():
		return 0

	var potion: ItemModel = create_model()

	#修改药水大小
	for child in potion.get_children():
		(child as Node2D).scale = Vector2(0.5,0.5)

	if potion == null:
		return 0

	potion.collision_layer = 0
	potion.collision_mask = 4

	potion.freeze = true
	potion.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC

	player.get_parent().add_child(potion)

	var origin: Vector2 = player.global_position
	potion.global_position = origin

	# 投掷距离受升级卡“投掷精通”影响：超程的弹道会在射程尽头碎掉。
	var max_distance: float = POTION_MAX_DISTANCE * player.potion_range_mult()

	var aim: Vector2 = player.get_global_mouse_position() - origin
	var direction: Vector2 = aim.normalized() if aim.length() > 1.0 else Vector2.RIGHT

	var flight: PotionProjectile = PotionProjectile.new()

	potion.add_child(flight)
	flight.start(player, direction, POTION_SPEED, burst_radius, burst_duration, alchemical_attribute, max_distance)

	return 1
