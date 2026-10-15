extends ItemData

class_name PotionData

##药水数据由坩埚里反应完的属性装瓶而来
##药水不可堆叠

##药水id的起始值
const NEW_POTION_ID:int = 301

##砸碎后生成的圆形范围场景：只放需要目标的属性，圈内每个目标各调用一次 use_effect
const BURST_SCENE: PackedScene = preload("res://scenes/items/potions/potion_burst.tscn")

const POTION_SPEED:float = 400.0

##作用效果范围半径(像素)
@export var burst_radius: float = 32.0

##作用效果范围存在时间(秒)：0＝立刻结算一次就消失
@export var burst_duration: float = 0

##本局已经发到哪个药水id了：必须放在静态段，
##静态的 create_from_attributes 只能碰静态成员，实例方法的计数器在它里面用不了
static var _next_potion_id:int = NEW_POTION_ID

static func next_potion_id() -> int:
	var potion_id:int = _next_potion_id
	_next_potion_id += 1

	return potion_id


func left_use(player:PlayerCharacter) -> int:
	return 1

##投掷药水，朝准心抛出去，撞到受击盒或地形才碎
##飞行由 PotionProjectile 每物理帧推进(刚体保持冻结，不依赖世界有没有物理地板)
##破碎后在碎点产生作用效果圈，圈内每个目标各调用一次 use_effect；
##不需要目标的属性(need_target = false)不经过范围，直接对碎点上的药水模型调用一次。
func right_use(player:PlayerCharacter) -> int:

	if player == null or player.get_parent() == null:
		return 0

	var potion: ItemModel = create_model()

	if potion == null:
		return 0

	potion.collision_layer = 0
	potion.collision_mask = 4

	potion.freeze = true
	potion.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC

	player.get_parent().add_child(potion)

	var origin: Vector2 = player.global_position
	potion.global_position = origin

	var aim: Vector2 = player.get_global_mouse_position() - origin
	var direction: Vector2 = aim.normalized() if aim.length() > 1.0 else Vector2.RIGHT

	var flight: PotionProjectile = PotionProjectile.new()

	potion.add_child(flight)
	flight.start(player, direction, POTION_SPEED, burst_radius, burst_duration, alchemical_attribute)

	return 1
