class_name ShiMonsterAttack
extends EnemyAttack

const ROTATION_SPEED: float = TAU * 0.5
const CONTACT_DAMAGE: float = 30.0
const CONTACT_COOLDOWN: float = 1.0
var host: ShiMonster
var _busy: bool = false
var _form_remaining: float = 0.0
var _contact_remaining: float = 0.0
var _shots: Array[int] = [0, 0, 0]


func setup(monster: BaseMonster, _config: EnemyAIConfig) -> void:
	host = monster as ShiMonster


func attack_range() -> float:
	return 160.0


func can_attack(_monster: BaseMonster, target: Node2D) -> bool:
	return is_instance_valid(target) and host != null and (host.is_group_leader() or host.nearby_partners().size() >= 2)


func perform_attack(_monster: BaseMonster, _target: Node2D) -> bool:
	if not host.is_group_leader():
		if not host.form_group():
			return false
		_form_remaining = 0.25
		_shots = [0, 0, 0]
	_busy = true
	return true


func is_busy() -> bool:
	return _busy


func update(_monster: BaseMonster, delta: float) -> void:
	if not is_instance_valid(host) or not host.is_group_leader() or not is_instance_valid(host.player):
		_busy = false
		return
	if not host.has_clear_line_to_player():
		# 短暂失去视线先交回通用追击寻路，绕墙后继续旋转，不隔墙发弹。
		_busy = false
		host.blackboard.can_see_target = false
		return
	if _form_remaining > 0.0:
		_form_remaining = maxf(_form_remaining - delta, 0.0)
		if _form_remaining > 0.0:
			return
	_contact_remaining = maxf(_contact_remaining - delta, 0.0)
	var previous: float = host.spin_phase
	host.spin_phase += delta * ROTATION_SPEED
	if host.monster_animation_state() != &"Shoot":
		host.play_monster_animation(&"Spin")
	host.navigator.request_path(WorldGenerator.world_to_tile(host.player.global_position))
	host.navigator.follow()
	for member: ShiMonster in host.group_members:
		if is_instance_valid(member) and member != host:
			member.global_position = host.global_position
	var facing: float = host.global_position.angle_to_point(host.player.global_position)
	for index: int in 3:
		var offset: float = float(index) * TAU / 3.0
		var next_front: float = facing + ceilf((previous + offset - facing) / TAU) * TAU
		if next_front <= previous + offset + 0.00001:
			next_front += TAU
		if next_front <= host.spin_phase + offset:
			fire_slime(index)
	if _contact_remaining <= 0.0 and _touching_player():
		host.player.take_damage(host.outgoing_damage(CONTACT_DAMAGE))
		_contact_remaining = CONTACT_COOLDOWN
	var body := host.get_node("Visual/Body") as CanvasItem
	body.queue_redraw()


func fire_slime(index: int) -> void:
	if not is_instance_valid(host.player) or not host.has_clear_line_to_player():
		return
	var projectile := ShiSlimeProjectile.new()
	host.get_parent().add_child(projectile)
	var offset: Vector2 = Vector2.RIGHT.rotated(host.spin_phase + index * TAU / 3.0) * 12.0
	projectile.launch(host, host.player, host.global_position + offset)
	host.play_monster_animation(&"Shoot", true)
	_shots[index] += 1


func _touching_player() -> bool:
	var shape := CircleShape2D.new()
	shape.radius = ShiMonster.GROUP_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = (host.get_node("CollisionShape2D") as CollisionShape2D).global_transform
	query.margin = 0.2
	query.collision_mask = host.player.collision_layer
	query.exclude = [host.get_rid()]
	for overlap: Dictionary in host.get_world_2d().direct_space_state.intersect_shape(query):
		if overlap["collider"] == host.player:
			return true
	return false


func cancel(_monster: BaseMonster) -> void:
	_busy = false
