extends ItemData

class_name PotionData

##药水数据由坩埚里反应完的属性装瓶而来
##药水不可堆叠

##药水id的起始值
const NEW_POTION_ID:int = 300


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
	for attribute:AlchemicalData in alchemical_attribute:
		if attribute != null and attribute.has_method("use_effect"):
			attribute.use_effect(player)
	return 1

##丢出手中药水：朝准心抛出去，撞到角色或地形就碎，碎点触发药水效果。
##整段飞行由 Tween 推位置、刚体保持冻结，所以不依赖世界有没有物理地板；
##命中判定用每帧一条短射线补物理接触，地形则直接问 WorldGenerator。
func right_use(player:PlayerCharacter) -> int:

	if player == null or player.get_parent() == null or player.potions_blocked():
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

	#朝准心投掷，鼠标压在身上时朝正面
	var speed: float = 320.0        #飞行速度，像素/秒

	# 投掷距离受升级卡“投掷精通”影响。
	var max_distance: float = 500.0 * player.potion_range_mult() #最大射程，10格

	var aim: Vector2 = player.get_global_mouse_position() - origin
	var direction: Vector2 = aim.normalized() if aim.length() > 1.0 else Vector2.RIGHT

	var distance: float = max_distance
	var destination: Vector2 = origin + direction * distance
	var duration: float = clampf(distance / speed, 0.08, 0.60)

	#飞行途中改状态，用字典当一个可变的盒子，两个回调共享同一份
	var state: Dictionary = {"done": false}

	#破碎收尾：命中的角色直接把那个角色交给效果；砸在地形上就把碎点上的药水模型交出去，
	##后续实现 AlchemicalData.use_effect(object) 时按这个约定接进来即可，
	##两种情况下 object 都是碎点附近的 Node2D，可以直接取位置
	var finish := func(target: Node, at: Vector2) -> void:
		if state["done"]:
			return
		state["done"] = true
		potion.global_position = at
		var effect_target: Node = target if target != null else potion
		for attribute: AlchemicalData in alchemical_attribute:
			if attribute != null and attribute.has_method("use_effect"):
				attribute.use_effect(effect_target)
		potion.queue_free()

	#不可通行地形和箱庭外都算撞墙，地形访问生成器
	var blocked := func(point: Vector2) -> bool:
		if player.active_map != null:
			var local: Vector2i = WorldGenerator.world_to_tile(point) - player.active_map.origin
			if not player.active_map.contains_local(local.x, local.y):
				return true
		if player.terrain_source == null:
			return false
		return not player.terrain_source.is_walkable(WorldGenerator.world_to_tile(point))

	#每一帧推进一段：角色靠一条物理射线取最近的接触点，地形按4像素一格格扫，
	##两边取更早的那个当破碎点；这一帧再长(掉帧时)也不会穿过角色或墙
	var step := func(t: float) -> void:
		if state["done"]:
			return
		var from: Vector2 = potion.global_position
		var to: Vector2 = origin.lerp(destination, t)
		var span: float = from.distance_to(to)
		var impact: float = -1.0 #0~1，本段里最早的阻挡位置
		var target: Node = null
		if span > 0.001:
			var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, potion.collision_mask)
			#投掷者自己不算障碍，否则药水出手就碎
			query.exclude = [player.get_rid()]
			var contact: Dictionary = potion.get_world_2d().direct_space_state.intersect_ray(query)
			if not contact.is_empty():
				impact = from.distance_to(contact["position"]) / span
				target = contact["collider"] as Node
			#地形没有物理层，只能逐格问生成器；停在最后一个可走的点上，不留在墙里
			var segments: int = maxi(1, ceili(span / 4.0))
			var last_ok: float = 0.0
			for index: int in range(1, segments + 1):
				var fraction: float = float(index) / float(segments)
				if not blocked.call(from.lerp(to, fraction)):
					last_ok = fraction
					continue
				if impact < 0.0 or last_ok < impact:
					impact = last_ok
					target = null
				break
		if impact >= 0.0:
			finish.call(target, from.lerp(to, impact))
			return
		potion.global_position = to
		#飞到最大射程也没撞到东西，同样破碎消失
		if t >= 1.0:
			finish.call(null, to)

	var flight: Tween = potion.create_tween()

	flight.tween_method(step, 0.0, 1.0, duration)

	#飞行时翻个身，看起来像被丢出去
	var spin: float = TAU if direction.x >= 0.0 else -TAU

	flight.parallel().tween_property(potion, "rotation", spin, duration)

	return 1
