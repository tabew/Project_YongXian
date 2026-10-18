class_name PotionBurst
extends Area2D

## 药水砸碎后留下的圆形作用范围：圈内每个目标各调用一次 use_effect。
## 只处理需要目标的属性(need_target = true)；不需要目标的属性由药水在破碎时直接结算。
## duration 为 0：生成这一帧立刻结算一次就消失；
## duration 大于 0，留在世界里按 pulse_interval 定时放脉冲，每个脉冲对"当时在圈里的每个目标"
## 期间进入圈里的目标从下一个脉冲开始吃效果，离开圈就不再被作用。

##检测层：2=玩家 3=怪物。按角色身体判定，不查受击盒(Area2D)
const TARGET_MASK: int = 7

##范围半径(像素)
var radius: float = 32.0
##存在时间(秒)
var duration: float = 1.0
##延时属性给的时长倍率：作用到目标身上的 buff 按它延长
var duration_scale: float = 1.0
##要作用到目标上的属性，只放 need_target 为 true 的
var attributes: Array[AlchemicalData] = []

##脉冲间隔(秒)，定时对当时在圈里的每个目标各调用一次 use_effect
@export_range(0.05, 10.0, 0.05) var pulse_interval: float = 0.05
##间隔下限
const MIN_PULSE_INTERVAL: float = 0.05

##护己效果作用对象，只吃正面效果
var exempt_target: Node = null

##周期性作用于圈自身的属性（例如雷的落雷）：按属性自报的间隔在圈心触发
var _zone_effects: Array[AlchemicalData] = []
##每个这类属性下一次触发的时间点(相对 _elapsed)，每个圈各自持有
var _zone_next: Dictionary = {}

##下一个脉冲的时间点(相对 _elapsed)
var _next_pulse_at: float = 0.0
##最近一次脉冲的时间点，用来画脉冲闪光
var _last_pulse_at: float = 0.0

##形状按实例建：场景里的形状资源会被所有实例共用，改半径会互相影响
var _shape: CircleShape2D = null
var _elapsed: float = 0.0
var _started: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = TARGET_MASK
	monitoring = true
	monitorable = false
	_build_shape()
	set_physics_process(false)


##由药水在碎点调用，设置范围参数并立刻放第一个脉冲
##exempt：只参与正面效果；duration_scale：延时属性给的时长倍率
func setup(at: Vector2, burst_radius: float, burst_duration: float, burst_attributes: Array[AlchemicalData],
		exempt: Node = null, burst_duration_scale: float = 1.0) -> void:
	radius = burst_radius
	duration = burst_duration
	duration_scale = maxf(burst_duration_scale, 0.1)
	attributes = burst_attributes
	exempt_target = exempt
	#护己的使用者记在圈上
	if exempt_target != null:
		set_meta(SelfExempt.EXEMPT_META, exempt_target)
	#周期性作用于圈自身的属性，圈里有没有生物都会触发，触发点在圈心
	_zone_effects.clear()
	_zone_next.clear()

	for attribute: AlchemicalData in attributes:
		if attribute != null and attribute.has_method("zone_interval"):
			_zone_effects.append(attribute)
			_zone_next[attribute.get_instance_id()] = 0.0
	global_position = at
	if _shape != null:
		_shape.radius = maxf(radius, 1.0)
	_started = true
	# 药水圈落在草地上时先把圈内的草清掉（圈是静止的，清一次就够）。
	GrassView.clear_circle(at, radius)
	_elapsed = 0.0
	
	#生成时就在圈里的目标先结算：Area2D 的重叠要等物理帧同步，这里直接查一次更稳
	pulse_interval = maxf(pulse_interval, MIN_PULSE_INTERVAL)
	_pulse()
	_next_pulse_at = pulse_interval

	if duration > 0.0:
		set_physics_process(true)
		queue_redraw()
	else:
		queue_free()


func _build_shape() -> void:
	_shape = CircleShape2D.new()
	_shape.radius = maxf(radius, 1.0)
	var collider: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collider == null:
		collider = CollisionShape2D.new()
		collider.name = "CollisionShape2D"
		add_child(collider)
	collider.shape = _shape


func _physics_process(delta: float) -> void:
	_elapsed += delta

	if _elapsed >= _next_pulse_at:
		_pulse()
		_next_pulse_at += pulse_interval
		if _next_pulse_at <= _elapsed:
			_next_pulse_at = _elapsed + pulse_interval

	if _elapsed >= duration:
		queue_free()
		return
	queue_redraw()



##发出脉冲
func _pulse() -> void:
	if not _started:
		return
	_last_pulse_at = _elapsed
	_apply_to(_query_bodies())
	_tick_zone_effects()


##圈自身的周期性效果，按每个圈自己的计时触发
func _tick_zone_effects() -> void:
	for attribute: AlchemicalData in _zone_effects:
		if attribute == null:
			continue

		var id: int = attribute.get_instance_id()

		if _elapsed < float(_zone_next.get(id, 0.0)):
			continue

		var interval: float = maxf(float(attribute.call("zone_interval")), MIN_PULSE_INTERVAL)

		_zone_next[id] = _elapsed + interval
		Buffs.set_next_duration_scale(duration_scale)
		attribute.use_effect(self)
		Buffs.reset_duration_scale()



##直接按形状查一次圈内的角色，不依赖 Area2D 的重叠是否已经同步
func _query_bodies() -> Array:
	if _shape == null:
		return []
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = global_transform
	query.collision_mask = TARGET_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var bodies: Array = []
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query):
		bodies.append(hit["collider"])
	return bodies


##一次脉冲内对每个目标各作用一次
func _apply_to(bodies: Array) -> void:
	for body: Variant in bodies:
		var target: Node = body as Node
		if target == null:
			continue
		#使用者只吃正面；其它圈内目标只吃非正面
		_apply_attributes(target, _is_exempt(target))


##给一个目标结算属性。
##护己生效时，正面只给for_self，其它圈内目标只吃非正面（for_self = false）；
##没有护己时不做过滤，效果照旧作用于圈内所有人。
func _apply_attributes(target: Node, for_self: bool) -> void:
	var split: bool = _has_exempt()

	for attribute: AlchemicalData in attributes:
		if attribute == null or not attribute.has_method("use_effect"):
			continue
		if attribute.has_method("zone_interval"):
			continue
		if split:
			if for_self and not attribute.is_positive_effect():
				continue
			if not for_self and attribute.is_positive_effect():
				continue
		Buffs.set_next_duration_scale(duration_scale)
		attribute.use_effect(target)
		Buffs.reset_duration_scale()
		if attribute.is_take_only_one == true:
			attributes.erase(attribute)


##是否具有护己属性
func _has_exempt() -> bool:
	return exempt_target != null and is_instance_valid(exempt_target)


##护己效果判断
func _is_exempt(target: Node) -> bool:
	if exempt_target == null or not is_instance_valid(exempt_target):
		return false
	return target == exempt_target or exempt_target.is_ancestor_of(target)



func _draw() -> void:
	if duration <= 0.0 or not _started:
		return
	var flash: float = 1.0
	var left: float = clampf(1.0 - _elapsed / duration, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.86, 0.58, 0.06 + 0.10 * flash * left))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.93, 0.74, 0.18 + 0.55 * flash * left), 1.0)
