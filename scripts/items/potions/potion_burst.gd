# ===== AI 新增文件 (药水砸碎后的圆形范围：圈内每个目标各调用一次 use_effect) =====
class_name PotionBurst
extends Area2D

## 药水砸碎后留下的圆形范围：圈内每个目标各调用一次 use_effect。
## 只处理需要目标的属性(need_target = true)；不需要目标的属性由药水在破碎时直接结算。
## duration 为 0：生成这一帧立刻结算一次就消失；大于 0：持续存在，
## 期间进入圈里的目标同样各生效一次，出圈或一直待在圈里都不会重复触发。

##检测层：1=World(玩家) 2=怪物。按角色身体判定，不查受击盒(Area2D)
const TARGET_MASK: int = 3

##范围半径(像素)：由药水模板在 setup 时传进来
var radius: float = 32.0
##存在时间(秒)：0＝立刻结算一次
var duration: float = 1.0
##要作用到目标上的属性，只放 need_target 为 true 的
var attributes: Array[AlchemicalData] = []

##已经生效过的目标：同一个目标只调用一次
var _applied: Array[Node] = []
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


##由药水在碎点调用：设置范围参数并立刻开始结算
func setup(at: Vector2, burst_radius: float, burst_duration: float, burst_attributes: Array[AlchemicalData]) -> void:
	radius = burst_radius
	duration = burst_duration
	attributes = burst_attributes
	global_position = at
	if _shape != null:
		_shape.radius = maxf(radius, 1.0)
	_started = true
	#生成时就在圈里的目标先结算：Area2D 的重叠要等物理帧同步，这里直接查一次更稳
	_apply_to(_query_bodies())
	if duration > 0.0:
		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)
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
	if _elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	_apply_to([body])


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


##每个目标只生效一次
func _apply_to(bodies: Array) -> void:
	if not _started:
		return
	_prune()
	for body: Variant in bodies:
		var target: Node = body as Node
		if target == null or _applied.has(target):
			continue
		_applied.append(target)
		for attribute: AlchemicalData in attributes:
			if attribute != null and attribute.has_method("use_effect"):
				attribute.use_effect(target)


##清掉已经释放的目标，避免数组越攒越大，也避免留着已释放对象的引用
func _prune() -> void:
	for index: int in range(_applied.size() - 1, -1, -1):
		if not is_instance_valid(_applied[index]):
			_applied.remove_at(index)


##存在时间大于 0 时把范围画出来，越接近消失越淡
func _draw() -> void:
	if duration <= 0.0 or not _started:
		return
	var left: float = clampf(1.0 - _elapsed / duration, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.86, 0.58, 0.08 + 0.10 * left))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.93, 0.74, 0.22 + 0.48 * left), 1.0)
