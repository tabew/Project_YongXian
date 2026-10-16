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
##要作用到目标上的属性，只放 need_target 为 true 的
var attributes: Array[AlchemicalData] = []

##脉冲间隔(秒)，定时对当时在圈里的每个目标各调用一次 use_effect
@export_range(0.05, 10.0, 0.05) var pulse_interval: float = 0.05
##间隔下限
const MIN_PULSE_INTERVAL: float = 0.05

##被排除在效果之外的目标（药水带"护己"属性时是使用者自己）
var exempt_target: Node = null

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
##exempt：不参与效果的目标（带"护己"属性的药水会把使用者传进来）
func setup(at: Vector2, burst_radius: float, burst_duration: float, burst_attributes: Array[AlchemicalData],
		exempt: Node = null) -> void:
	radius = burst_radius
	duration = burst_duration
	attributes = burst_attributes
	exempt_target = exempt
	global_position = at
	if _shape != null:
		_shape.radius = maxf(radius, 1.0)
	_started = true
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



##发出脉冲，对当时在圈里的每个目标各调用一次 use_effect
func _pulse() -> void:
	if not _started:
		return
	_last_pulse_at = _elapsed
	_apply_to(_query_bodies())



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
		if target == null or _is_exempt(target):
			continue
		for attribute: AlchemicalData in attributes:
			if attribute != null and attribute.has_method("use_effect"):
				attribute.use_effect(target)
				if attribute.is_take_only_one == true:
					attributes.erase(attribute)


##"护己"：使用者自己（连同它下面的节点）不算圈内目标
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
