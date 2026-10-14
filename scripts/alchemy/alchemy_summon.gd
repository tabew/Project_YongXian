class_name AlchemySummon
extends Node2D

## 炼金召唤物：召唤 / 骨 V 骷髅 / 灵魂 V 游魂 / 活体 V 分身共用的临时战斗单位。
##
## 纯表现 + 物理查询，不参与词条计算：伤害与寿命由召唤方（炼金组合）算好后写进来。
## 外观用代码绘制，不依赖美术资源；自动索敌，靠近后按固定间隔出手，寿命到期消散；
## 带 explodes 标记的召唤物消散时自爆一次范围伤害。

signal expired(summon: AlchemySummon)

## 与玩家同队：不会打到玩家，也不会被玩家武器误伤。
const TEAM: int = 1
## 敌人受击盒所在的物理层（与武器 hit_mask 一致）。
const ENEMY_MASK: int = 4
## 消散时自爆的物理层（同上）。
const BLAST_MASK: int = 4

## 每次出手的伤害（召唤方按武器基础伤害 × 比例算好）。
var damage: float = 6.0
## 寿命（秒）。
var lifetime: float = 8.0
## 出手间隔（秒）。
var attack_interval: float = AlchemyRules.SUMMON_ATTACK_INTERVAL
## 索敌半径（格）。
var search_tiles: float = AlchemyRules.SUMMON_SEARCH_RADIUS_TILES
## 移动速度（像素/秒）。
var move_speed: float = AlchemyRules.SUMMON_MOVE_SPEED
## 消散时是否自爆。
var explodes: bool = false
## 主体颜色（按炼金主导元素取色）。
var tint: Color = Color("a98cff")
## 召唤者：伤害来源与击退方向基准。
var owner_actor: Node2D = null
## 半径（像素），用于绘制与命中判定。
var radius: float = 6.0

var _age: float = 0.0
var _attack_cooldown: float = 0.0
var _bob_time: float = 0.0
var _base_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_base_position = global_position
	z_index = 3
	queue_redraw()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		_expire()
		return
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_bob_time += delta
	var target: CombatHurtbox = _nearest_enemy()
	if target != null:
		var to_target: Vector2 = target.global_position - global_position
		var reach: float = AlchemyRules.SUMMON_ATTACK_RANGE_TILES * float(WorldGenerator.TILE_SIZE)
		if to_target.length() > reach:
			var step: Vector2 = to_target.normalized() * move_speed * delta
			global_position += step
			_base_position = global_position
		elif _attack_cooldown <= 0.0:
			_attack(target)
			_attack_cooldown = attack_interval
	queue_redraw()


## 索敌：半径内最近的敌方受击盒。
func _nearest_enemy() -> CombatHurtbox:
	if not is_inside_tree():
		return null
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return null
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = search_tiles * float(WorldGenerator.TILE_SIZE)
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = ENEMY_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var found: Array[CombatHurtbox] = []
	for result: Dictionary in space.intersect_shape(query, 16):
		var collider: Object = result.get("collider")
		if collider is CombatHurtbox:
			found.append(collider)
	var best: CombatHurtbox = null
	var best_distance: float = INF
	for hurtbox: CombatHurtbox in found:
		if not hurtbox.can_receive_hit(self, TEAM):
			continue
		var distance: float = global_position.distance_squared_to(hurtbox.global_position)
		if distance < best_distance:
			best_distance = distance
			best = hurtbox
	return best


func _attack(target: CombatHurtbox) -> void:
	var hit: CombatHit = CombatHit.new()
	hit.source = owner_actor if is_instance_valid(owner_actor) else self
	hit.weapon_id = &"alchemy_summon"
	hit.critical = false
	hit.damage = damage
	hit.position = target.global_position
	var direction: Vector2 = (target.global_position - global_position).normalized()
	hit.knockback = direction * 90.0
	target.receive_hit(hit)


## 消散：带 explodes 时先自爆，再通知召唤方回收。
func _expire() -> void:
	if explodes:
		_blast()
	expired.emit(self)
	queue_free()


## 自爆：对范围内的敌人各打一次范围伤害。
func _blast() -> void:
	if not is_inside_tree():
		return
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = AlchemyRules.SUMMON_EXPLODE_RADIUS_TILES * float(WorldGenerator.TILE_SIZE)
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = BLAST_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result: Dictionary in space.intersect_shape(query, 16):
		var collider: Object = result.get("collider")
		if not collider is CombatHurtbox:
			continue
		var hurtbox := collider as CombatHurtbox
		if not hurtbox.can_receive_hit(self, TEAM):
			continue
		var hit: CombatHit = CombatHit.new()
		hit.source = owner_actor if is_instance_valid(owner_actor) else self
		hit.weapon_id = &"alchemy_summon_blast"
		hit.critical = false
		hit.damage = damage * AlchemyRules.SUMMON_EXPLODE_DAMAGE_RATIO
		hit.position = hurtbox.global_position
		hit.knockback = (hurtbox.global_position - global_position).normalized() * 120.0
		hurtbox.receive_hit(hit)


## 剩余寿命比例（表现层可用于淡出）。
func lifetime_ratio() -> float:
	if lifetime <= 0.0:
		return 0.0
	return clampf(1.0 - _age / lifetime, 0.0, 1.0)


func _draw() -> void:
	# 代码生成外观：外圈 + 内核 + 随寿命淡出的光晕。
	var bob: float = sin(_bob_time * 6.0) * 1.2
	var center: Vector2 = Vector2(0.0, bob)
	var fade: float = clampf(lifetime_ratio() * 2.0, 0.25, 1.0)
	draw_circle(center, radius + 2.5, Color(tint.r, tint.g, tint.b, 0.18 * fade))
	draw_circle(center, radius, Color(tint.r, tint.g, tint.b, 0.85 * fade))
	draw_arc(center, radius, 0.0, TAU, 24, Color(tint.r, tint.g, tint.b, fade), 1.5, true)
	draw_circle(center + Vector2(0.0, -1.0), radius * 0.35, Color(1.0, 1.0, 1.0, 0.75 * fade))
