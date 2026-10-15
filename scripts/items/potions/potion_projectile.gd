
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
##命中探测半径(像素)：药水有体积，判定用一个这么粗的圆扫过本帧位移。
##只用零宽射线时，瓶心必须几乎正中受击盒才算命中，木桩那种小受击盒(半径10)很容易整颗漏过去，
##表现出来就是“药水直接穿过木桩飞走”。
const HIT_RADIUS: float = 6.0
##一帧最多采样几个圆：采样间隔压到小于圆直径，掉帧时也不会整段跨过目标
const HIT_SAMPLES_MAX: int = 12

var _potion: ItemModel = null
var _player: PlayerCharacter = null
var _direction: Vector2 = Vector2.RIGHT
var _speed: float = 400.0
var _burst_radius: float = 32.0
var _burst_duration: float = 0.0
var _attributes: Array[AlchemicalData] = []
var _spin: float = SPIN_RADIANS_PER_SECOND
##命中探测用的圆与查询参数：开始投掷时建一次，之后每帧只改 transform
var _probe: PhysicsShapeQueryParameters2D = null
var _probe_shape: CircleShape2D = null

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
	_build_probe()
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


##建命中探测：圆、掩码、排除投掷者都只算一次，之后每帧只更新 transform
func _build_probe() -> void:

	if not is_instance_valid(_potion):
		return

	_probe_shape = CircleShape2D.new()
	_probe_shape.radius = HIT_RADIUS

	_probe = PhysicsShapeQueryParameters2D.new()
	_probe.shape = _probe_shape
	_probe.collision_mask = _potion.collision_mask
	_probe.collide_with_areas = true   #受击盒是 Area2D，和武器判定走同一条查询路径
	_probe.collide_with_bodies = true

	#投掷者自己不算障碍
	if is_instance_valid(_player):
		_probe.exclude = [_player.get_rid()]


##这一小段位移里最早撞到东西的位置(0~1)，没有撞到返回 -1。
##用带半径的圆沿位移采样，而不是零宽射线：受击盒普遍比瓶子视觉小，
##射线要求两个中心点几乎共线，木桩那种小受击盒会被整颗漏过去。
func _first_hit_fraction(from: Vector2, to: Vector2, span: float) -> float:

	if _probe == null or not is_instance_valid(_potion):
		return -1.0

	var space: PhysicsDirectSpaceState2D = _potion.get_world_2d().direct_space_state
	var samples: int = clampi(ceili(span / (HIT_RADIUS * 2.0)), 1, HIT_SAMPLES_MAX)

	for index: int in range(1, samples + 1):
		var fraction: float = float(index) / float(samples)
		_probe.transform = Transform2D(0.0, from.lerp(to, fraction))

		if not space.intersect_shape(_probe, 1).is_empty():
			return fraction

	return -1.0


##本段里最早的阻挡位置(0~1)，这一段没被挡到返回 -1
func _first_block(from: Vector2, to: Vector2) -> float:
	var span: float = from.distance_to(to)
	var impact: float = -1.0

	if span <= 0.001:
		return impact

	impact = _first_hit_fraction(from, to, span)

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

	for attribute: AlchemicalData in _attributes:
		if attribute == null or not attribute.has_method("use_effect"):
			continue

		if attribute.need_target:
			burst_attributes.append(attribute)
		else:
			#不需要目标：直接调用一次，效果自己从药水模型上取属性或碎点坐标
			attribute.use_effect(_potion)

	var world: Node = _potion.get_parent()

	if world != null and not burst_attributes.is_empty():
		var burst: PotionBurst = PotionData.BURST_SCENE.instantiate() as PotionBurst

		if burst != null:
			world.add_child(burst)
			burst.setup(at, _burst_radius, _burst_duration, burst_attributes)

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
