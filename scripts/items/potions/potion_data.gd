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
