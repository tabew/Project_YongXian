class_name OrbitBall
extends Node2D

## 升级卡“环绕球”：攻击期间额外一颗球绕角色快速旋转，独立结算伤害。
##
## 挂在攻击实例下，攻击结束随父节点一起释放，因此松手即消失，不需要额外清理。

const ORBIT_RADIUS: float = 40.0
const ORBIT_SPEED: float = TAU
const HIT_INTERVAL: float = 0.4
const BALL_RADIUS: float = 6.0
const CIRCLE_POINTS: int = 10
const QUERY_BATCH: int = 32
## 环绕球伤害占主武器的比例。
const DAMAGE_RATIO: float = 0.6

signal hit_landed(hit: CombatHit, hurtbox: CombatHurtbox)

var _wielder: Node2D = null
var _definition: WeaponDefinition = null
var _team: int = 1
var _angle: float = 0.0
var _elapsed: float = 0.0
var _next_hit: Dictionary = {}
var _shape: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
var _query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
var _sprite: Sprite2D = null


func setup(wielder: Node2D, definition: WeaponDefinition, team: int, index: int, total: int) -> void:
	_wielder = wielder
	_definition = definition
	_team = team
	_angle = TAU * float(index) / float(maxi(total, 1))
	_query.shape = _shape
	_query.collision_mask = definition.hit_mask
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	if definition.texture != null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		_sprite.texture = definition.texture
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.scale = Vector2.ONE * (BALL_RADIUS * 2.0 / maxf(float(definition.texture.get_width()), 1.0))
		add_child(_sprite)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_wielder):
		queue_free()
		return
	_elapsed += delta
	_angle = fmod(_angle + ORBIT_SPEED * delta, TAU)
	position = Vector2.from_angle(_angle) * ORBIT_RADIUS
	if _sprite != null:
		_sprite.rotation = _angle
	_query_ball()


## 用圆形采样做形状查询，同一目标按 HIT_INTERVAL 重复受伤。
func _query_ball() -> void:
	_shape.points = _circle_points()
	_query.transform = Transform2D(0.0, global_position)
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var excluded: Array[RID] = []
	while true:
		_query.exclude = excluded
		var results: Array[Dictionary] = space.intersect_shape(_query, QUERY_BATCH)
		for result: Dictionary in results:
			excluded.append(result["rid"])
			var hurtbox: CombatHurtbox = result["collider"] as CombatHurtbox
			if hurtbox != null:
				_try_hit(hurtbox)
		if results.size() < QUERY_BATCH:
			break


func _try_hit(hurtbox: CombatHurtbox) -> void:
	if _definition == null or not hurtbox.can_receive_hit(_wielder, _team):
		return
	var id: int = hurtbox.receiver_id()
	if float(_next_hit.get(id, -INF)) > _elapsed:
		return
	_next_hit[id] = _elapsed + HIT_INTERVAL
	_deal_damage(hurtbox)


func _deal_damage(hurtbox: CombatHurtbox) -> void:
	var multiplier: float = 1.0
	if _wielder != null and _wielder.has_method("outgoing_damage_multiplier"):
		multiplier = float(_wielder.call("outgoing_damage_multiplier", hurtbox))
	var hit: CombatHit = CombatHit.new()
	hit.source = _wielder
	hit.weapon_id = _definition.id
	hit.critical = MapRng.shared(MapRng.Stream.COMBAT).randf() < _definition.critical_chance
	hit.damage = _definition.damage * DAMAGE_RATIO * multiplier * (_definition.critical_multiplier if hit.critical else 1.0)
	hit.position = hurtbox.global_position
	var direction: Vector2 = (hurtbox.global_position - global_position).normalized()
	hit.knockback = (direction if not direction.is_zero_approx() else Vector2.RIGHT) * _definition.knockback * 0.5
	if hurtbox.receive_hit(hit):
		hit_landed.emit(hit, hurtbox)


func _circle_points() -> PackedVector2Array:
	var points: PackedVector2Array = []
	for index: int in CIRCLE_POINTS:
		points.append(Vector2.from_angle(TAU * float(index) / float(CIRCLE_POINTS)) * BALL_RADIUS)
	return points