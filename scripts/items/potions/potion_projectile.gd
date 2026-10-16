
class_name PotionProjectile
extends Node

##药水弹幕

##飞出玩家最远可视范围后还能存在的时间(秒)
const OUT_OF_VIEW_GRACE: float = 2.0
##拿不到相机时的兜底可视半径(像素)
const FALLBACK_VIEW_RADIUS: float = 512.0
##自转角速度=
const SPIN_RADIANS_PER_SECOND: float = TAU
##地形逐格扫描步长(像素)
const TERRAIN_STEP: float = 4.0

var _potion: ItemModel = null
var _player: PlayerCharacter = null
var _direction: Vector2 = Vector2.RIGHT
var _speed: float = 400.0
var _burst_radius: float = 32.0
var _burst_duration: float = 0.0
var _attributes: Array[AlchemicalData] = []
var _spin: float = SPIN_RADIANS_PER_SECOND

var _view_radius: float = FALLBACK_VIEW_RADIUS
var _out_of_view_seconds: float = 0.0
var _done: bool = false


##由药水在出手时调用：要飞的模型就是本节点的父节点
func start(player: PlayerCharacter, direction: Vector2, speed: float, burst_radius: float, burst_duration: float, attributes: Array[AlchemicalData]) -> void:
	_potion = get_parent() as ItemModel
	_player = player
	_direction = direction.normalized() if direction.length() > 0.001 else Vector2.RIGHT
	_speed = maxf(speed, 0.0)
	_burst_radius = burst_radius
	_burst_duration = burst_duration
	_attributes = attributes
	_spin = SPIN_RADIANS_PER_SECOND if _direction.x >= 0.0 else -SPIN_RADIANS_PER_SECOND
	_view_radius = _measure_view_radius()
	_out_of_view_seconds = 0.0
	_done = false
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _done or delta <= 0.0 or not is_instance_valid(_potion):
		return

	var from: Vector2 = _potion.global_position
	var to: Vector2 = from + _direction * _speed * delta
	var impact: float = _first_block(from, to)

	if impact >= 0.0:
		_break_at(from.lerp(to, impact))
		return

	_potion.global_position = to
	_potion.rotation += _spin * delta
	_tick_out_of_view(delta)


##本段里最早的阻挡位置(0~1)，这一段没被挡到返回 -1
func _first_block(from: Vector2, to: Vector2) -> float:
	var span: float = from.distance_to(to)
	var impact: float = -1.0

	if span <= 0.001:
		return impact

	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, _potion.collision_mask)

	#投掷者自己不算障碍
	if is_instance_valid(_player):
		query.exclude = [_player.get_rid()]

	#受击盒是 Area2D，不打开这个开关射线只能打到身体，打不到怪物
	query.collide_with_areas = true

	var contact: Dictionary = _potion.get_world_2d().direct_space_state.intersect_ray(query)

	if not contact.is_empty():
		impact = from.distance_to(contact["position"]) / span

	#地形没有物理层，逐格问生成器
	var segments: int = maxi(1, ceili(span / TERRAIN_STEP))
	var last_ok: float = 0.0

	for index: int in range(1, segments + 1):
		var fraction: float = float(index) / float(segments)

		if not _blocked(from.lerp(to, fraction)):
			last_ok = fraction
			continue

		if impact < 0.0 or last_ok < impact:
			impact = last_ok
		break

	return impact


##不可通行地形和箱庭外都算撞墙，地形访问生成器
func _blocked(point: Vector2) -> bool:
	if not is_instance_valid(_player):
		return false

	if _player.active_map != null:
		var local: Vector2i = WorldGenerator.world_to_tile(point) - _player.active_map.origin

		if not _player.active_map.contains_local(local.x, local.y):
			return true

	if _player.terrain_source == null:
		return false

	return not _player.terrain_source.is_walkable(WorldGenerator.world_to_tile(point))


##药水效果结算
func _break_at(at: Vector2) -> void:
	if _done:
		return

	_done = true

	if not is_instance_valid(_potion):
		queue_free()
		return

	_potion.global_position = at

	var burst_attributes: Array[AlchemicalData] = []
	#护己类属性是"药水级"修饰，不提交给 use_effect，只用来把使用者排除在效果之外
	var exempt_target: Node = null

	for attribute: AlchemicalData in _attributes:
		if attribute == null or not attribute.has_method("use_effect"):
			continue

		if attribute.has_method("exempts_user") and attribute.exempts_user():
			if is_instance_valid(_player):
				exempt_target = _player
			continue

		if attribute.need_target:
			burst_attributes.append(attribute)
		else:
			#不需要目标：直接调用一次，效果自己从药水模型上取属性或碎点坐标
			attribute.use_effect(_potion)

	#把使用者记在药水模型上：爆炸那类直接结算的效果读它才能同样跳过使用者
	if exempt_target != null:
		_potion.set_meta(SelfExempt.EXEMPT_META, exempt_target)

	var world: Node = _potion.get_parent()

	if world != null and not burst_attributes.is_empty():
		var burst: PotionBurst = PotionData.BURST_SCENE.instantiate() as PotionBurst

		if burst != null:
			world.add_child(burst)
			burst.setup(at, _burst_radius, _burst_duration, burst_attributes, exempt_target)

	_potion.queue_free()


##飞出最远可视范围后开始计时，重新回到范围内就清零；计满就碎(安全阀)
func _tick_out_of_view(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	if _potion.global_position.distance_to(_player.global_position) <= _view_radius:
		_out_of_view_seconds = 0.0
		return

	_out_of_view_seconds += delta

	if _out_of_view_seconds >= OUT_OF_VIEW_GRACE:
		_break_at(_potion.global_position)


##玩家最远能看到的距离：视口尺寸按相机缩放换算成世界单位，取半对角线
func _measure_view_radius() -> float:
	if not is_instance_valid(_player):
		return FALLBACK_VIEW_RADIUS

	var viewport: Viewport = _player.get_viewport()

	if viewport == null:
		return FALLBACK_VIEW_RADIUS

	var size: Vector2 = viewport.get_visible_rect().size
	var camera: Camera2D = viewport.get_camera_2d()

	if camera != null:
		size /= camera.zoom

	var radius: float = size.length() * 0.5

	return radius if radius > 1.0 else FALLBACK_VIEW_RADIUS
