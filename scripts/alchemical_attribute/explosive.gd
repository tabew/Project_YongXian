class_name Explosive
extends AlchemicalData

## 爆裂属性 —— “炸弹”这类材料自带的炼金属性。
##
## 炸弹本身只是普通材料（IngredientData），真正决定“会不会炸、炸多大”的是这条属性：
## 材料丢进坩埚把爆裂带进锅里，装瓶成带爆裂的药水，扔出去砸碎时
## PotionData.right_use() 会调用 use_effect(碎点)，在这里做一次范围伤害。

## 爆炸半径（世界像素）。
@export var blast_radius: float = 96.0

## 基础爆炸伤害，实际伤害 = blast_damage * 等级（锅里出来的属性至少 1 级）。
@export var blast_damage: float = 30.0

## 爆炸击退力度。
@export var blast_knockback: float = 220.0

## 只炸敌对受击盒（Layer 3 = EnemyHurtbox），不误伤玩家。
const ENEMY_HURTBOX_MASK: int = 1 << 2
## 玩家阵营，和 WeaponController.team 保持一致。
const PLAYER_TEAM: int = 1
const QUERY_BATCH: int = 32


## 反应函数：实现 A + B = C + D。
## 组合规则还没定，先留空：爆裂目前不消耗别的属性，只是跟着药水走。
func interact(_attributes: Array[AlchemicalData], _which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []
	return result


## 产生使用效果：以 object 所在位置为圆心做一次范围伤害。
## object 由药水破碎时传进来，是碎点附近的 Node2D（地形就传药水模型本身）。
func use_effect(object: Node) -> void:
	var center: Node2D = object as Node2D
	if center == null or not center.is_inside_tree():
		return

	var radius: float = maxf(blast_radius, 0.0)
	if radius <= 0.0:
		return

	#先收集再结算：命中回调里可能删掉受击盒，边查边打容易碰到已释放的对象
	for hurtbox: CombatHurtbox in _hurtboxes_in_radius(center, radius):
		_receive_blast(center, hurtbox)

	#爆炸是噪音，半径内的怪物会听见（和脚步、投掷走同一条感知通道）
	EventBus.noise_reported.emit(center.global_position, radius, center)


func _hurtboxes_in_radius(center: Node2D, radius: float) -> Array[CombatHurtbox]:
	var found: Array[CombatHurtbox] = []
	var space: PhysicsDirectSpaceState2D = center.get_world_2d().direct_space_state
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = radius
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = ENEMY_HURTBOX_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.transform = Transform2D(0.0, center.global_position)
	#分批取，直到取完：同一批里可能混着同阵营或重复的受击盒
	var excluded: Array[RID] = []
	while true:
		query.exclude = excluded
		var results: Array[Dictionary] = space.intersect_shape(query, QUERY_BATCH)
		for result: Dictionary in results:
			excluded.append(result["rid"])
			var hurtbox: CombatHurtbox = result["collider"] as CombatHurtbox
			if hurtbox != null and not found.has(hurtbox):
				found.append(hurtbox)
		if results.size() < QUERY_BATCH:
			break
	return found


func _receive_blast(center: Node2D, hurtbox: CombatHurtbox) -> void:
	if not hurtbox.can_receive_hit(center, PLAYER_TEAM):
		return

	var damage: float = blast_damage * float(maxi(level, 1))
	if damage <= 0.0 and blast_knockback <= 0.0:
		return

	var hit: CombatHit = CombatHit.new()
	hit.source = center
	hit.weapon_id = &"explosive"
	hit.critical = false
	hit.damage = damage
	hit.position = hurtbox.global_position
	var outward: Vector2 = hurtbox.global_position - center.global_position
	hit.knockback = outward.normalized() * blast_knockback if outward.length() > 0.001 else Vector2.ZERO
	hurtbox.receive_hit(hit)
