# ===== AI 新增文件 (爆炸属性 use_effect 的落点：范围伤害 + 击退 + 表现) =====
class_name ExplodeEffect
extends Node2D

## 爆炸：生成当帧对范围内所有受击盒(敌人)和玩家各结算一次伤害与击退，然后播放表现并自毁。
## 击退强度按到爆心的距离衰减：爆心满值，圈边衰减到 edge_scale。
## 由 Explosive.use_effect 实例化 explode.tscn 后把本脚本挂到它的根节点上，
## 所以不需要改动那个场景；范围形状直接用它自带的 Area2D/CollisionShape2D。

##爆炸图集：6 帧 32x32
const EXPLOSION_SHEET: Texture2D = preload("res://assets/effects/explosion.png")
const SHEET_FRAMES: int = 6
##玩家阵营，和 WeaponAttack.wielder_team 一致：受击盒 team 不同才会吃这一下
const SOURCE_TEAM: int = 1
##命中来源标识，只用于 CombatHit 记录
const WEAPON_ID: StringName = &"explosive"
##一次范围查询最多取几个受击盒
const QUERY_LIMIT: int = 32
##没有来源节点时用自己当来源，保证 can_receive_hit 拿到的是一个合法节点
const FALLBACK_SOURCE_IS_SELF: bool = true

##表现总时长(秒)
@export_range(0.05, 2.0, 0.01) var visual_seconds: float = 0.36
##玩家没有受击盒也没有击退系统，击退直接加进速度，这里给强度打个折
@export_range(0.0, 2.0, 0.05) var player_knockback_scale: float = 0.8

var _sprite: Sprite2D = null
var _shape: CircleShape2D = null
var _elapsed: float = 0.0
var _idle_seconds: float = 0.0
var _playing: bool = false


##在当前位置炸一次：radius 内的敌人(受击盒)与玩家都吃伤害与击退。
##击退按到爆心的距离衰减：爆心满值，圈边衰减到 edge_scale(见 Explosive 的同名参数)。
func detonate(radius: float, enemy_damage: float, player_damage: float, knockback: float, hit_mask: int, source: Node,
		edge_scale: float = 0.3, falloff_power: float = 1.0) -> void:
	_prepare_shape(radius)
	_hit_hurtboxes(enemy_damage, knockback, hit_mask, _resolve_source(source), edge_scale, falloff_power)
	_hit_player(player_damage, knockback, edge_scale, falloff_power)
	_play_visual(radius)


##按到爆心的距离算击退倍率：爆心 1.0，圈边 edge_scale，power 控制曲线形状
func _knockback_scale(distance: float, radius: float, edge_scale: float, falloff_power: float) -> float:
	var falloff: float = clampf(1.0 - distance / maxf(radius, 0.001), 0.0, 1.0)
	return lerpf(edge_scale, 1.0, pow(falloff, maxf(falloff_power, 0.001)))


##用场景里那套 Area2D/CollisionShape2D 当范围：场景里的形状资源是所有实例共用的，先复制再改半径
func _prepare_shape(radius: float) -> void:
	var collider: CollisionShape2D = get_node_or_null("Area2D/CollisionShape2D") as CollisionShape2D
	var scene_shape: Shape2D = collider.shape if collider != null else null

	if scene_shape is CircleShape2D:
		_shape = (scene_shape as CircleShape2D).duplicate() as CircleShape2D
		if collider != null:
			#只改这一份副本，原场景资源的半径保持不动
			collider.shape = _shape
	else:
		_shape = CircleShape2D.new()

	_shape.radius = maxf(radius, 1.0)


func _resolve_source(source: Node) -> Node2D:
	if source is Node2D:
		return source as Node2D

	if FALLBACK_SOURCE_IS_SELF:
		return self

	return null


##圈内的受击盒：和武器一样走 CombatHit，一次命中就带上伤害、击退与受击闪红
func _hit_hurtboxes(enemy_damage: float, knockback: float, hit_mask: int, source: Node2D, edge_scale: float, falloff_power: float) -> void:
	if source == null or enemy_damage <= 0.0:
		return

	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = hit_mask
	query.collide_with_areas = true   #受击盒是 Area2D
	query.collide_with_bodies = false #玩家没有受击盒，单独处理
	#排除爆炸自己那个 Area2D，免得它的形状被当成目标
	var own_area: Area2D = get_node_or_null("Area2D") as Area2D

	if own_area != null:
		query.exclude = [own_area.get_rid()]

	for result: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, QUERY_LIMIT):
		var hurtbox: CombatHurtbox = result["collider"] as CombatHurtbox

		if hurtbox == null or not hurtbox.can_receive_hit(source, SOURCE_TEAM):
			continue

		var hit: CombatHit = CombatHit.new()
		hit.source = source
		hit.weapon_id = WEAPON_ID
		hit.damage = enemy_damage
		hit.position = hurtbox.global_position
		#从爆点朝外推：正好站在爆心上的目标给一个向上，避免零向量
		var to_target: Vector2 = hurtbox.global_position - global_position
		var direction: Vector2 = to_target.normalized() if not to_target.is_zero_approx() else Vector2.UP
		hit.knockback = direction * knockback * _knockback_scale(to_target.length(), _shape.radius, edge_scale, falloff_power)
		hurtbox.receive_hit(hit)


##玩家：没有受击盒也没有击退系统，直接扣血并把击退加进速度
func _hit_player(player_damage: float, knockback: float, edge_scale: float, falloff_power: float) -> void:
	var player: PlayerCharacter = null

	for node: Node in get_tree().get_nodes_in_group("player"):
		if node is PlayerCharacter:
			player = node as PlayerCharacter
			break

	if player == null or not is_instance_valid(player):
		return

	var to_target: Vector2 = player.global_position - global_position

	if to_target.length() > _shape.radius:
		return

	var push: Vector2 = to_target.normalized() if not to_target.is_zero_approx() else Vector2.UP
	var scale: float = _knockback_scale(to_target.length(), _shape.radius, edge_scale, falloff_power)
	player.velocity += push * knockback * player_knockback_scale * scale

	if player_damage > 0.0:
		player.take_damage(player_damage)


##表现：把图集铺在爆点，图集整张按爆炸直径缩放，存在时间内推帧
func _play_visual(radius: float) -> void:
	var frame_width: int = EXPLOSION_SHEET.get_width() / SHEET_FRAMES

	_sprite = Sprite2D.new()
	_sprite.name = "ExplosionSprite"
	_sprite.texture = EXPLOSION_SHEET
	_sprite.hframes = SHEET_FRAMES
	_sprite.frame = 0
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * ((maxf(radius, 1.0) * 2.0) / float(maxi(frame_width, 1)))
	add_child(_sprite)

	_playing = true
	_elapsed = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_idle_seconds += delta

	if not _playing:
		#没人调用 detonate 时也不要一直留在场景里
		if _idle_seconds > 1.0:
			queue_free()
		return

	_elapsed += delta
	var progress: float = clampf(_elapsed / maxf(visual_seconds, 0.01), 0.0, 1.0)

	if _sprite != null:
		_sprite.frame = mini(int(progress * float(SHEET_FRAMES)), SHEET_FRAMES - 1)

	if progress >= 1.0:
		_playing = false
		queue_free()
