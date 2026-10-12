class_name BaseMonster
extends CharacterBody2D

## 所有怪物共用的视线与寻路模板。
## RayCast2D 负责物理墙体，地形采样负责当前没有物理层的程序化阻挡格。

@export_group("寻路")
@export var navigation_speed: float = 72.0
@export var path_refresh_interval: float = 2.0
@export var path_margin_tiles: int = 6

@export_group("受击反馈")
## 基础反馈只产生约2像素位移；武器击退仍按强度加算，形成更明显的推开。
@export_range(0.0, 500.0, 1.0) var default_knockback_speed: float = 40.0
@export_range(0.01, 1.0, 0.01) var knockback_duration: float = 0.10
@export_range(0.01, 1.0, 0.01) var hit_flash_duration: float = 0.06

var _knockback_impulse: Vector2 = Vector2.ZERO
var _knockback_remaining: float = 0.0
var _knockback_applied_this_frame: bool = false
var _hit_flash_remaining: float = 0.0

@onready var target_raycast: RayCast2D = $TargetRayCast

var player: PlayerCharacter = null
var world_generator: WorldGenerator = null
var spawn_chunk: Vector2i = Vector2i.ZERO
var _has_player_aggro: bool = false

## 共享占位动画轨道；子类可替换动画库和 Visual 下的外形。
var _visual_height: float = 0.0:
	set(value):
		_visual_height = value
		_update_visual_pose()
var visual_pose: Vector2 = Vector2.ZERO:
	set(value):
		visual_pose = value
		_update_visual_pose()
var visual_tint: Color = Color.WHITE:
	set(value):
		visual_tint = value
		_update_visual_pose()

## 由通用模板创建，使用各怪物自己的 HealthComponent。
var health_bar: ProgressBar = null
var animation_tree: AnimationTree = null
var animation_playback: AnimationNodeStateMachinePlayback = null

var _path: Array[Vector2i] = []
var _path_index: int = 0
var _path_refresh_timer: float = 0.0
var _last_path_target: Vector2i = Vector2i(2147483647, 2147483647)
var _last_line_blocked_by_physics: bool = false
var _last_physics_collider: CollisionObject2D = null


func _ready() -> void:
	add_to_group("monsters")
	target_raycast.add_exception(self)
	_setup_health_bar()
	animation_tree = get_node_or_null("AnimationTree") as AnimationTree
	if animation_tree != null:
		animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		animation_tree.active = true
		animation_playback = animation_tree.get("parameters/playback")
		animation_playback.start(&"Idle")
		animation_tree.advance(0.0)
	var health_component := get_node_or_null("Health") as HealthComponent
	if health_component != null:
		health_component.damaged.connect(_on_monster_damaged)
		health_component.died.connect(_on_monster_died)


func _physics_process(delta: float) -> void:
	advance_monster_animation(delta)
	_hit_flash_remaining = maxf(_hit_flash_remaining - delta, 0.0)
	_update_hit_flash()
	_knockback_applied_this_frame = _knockback_remaining > 0.0
	if _knockback_applied_this_frame:
		var step_time: float = minf(delta, _knockback_remaining)
		var strength: float = maxf(_knockback_remaining - step_time * 0.5, 0.0) / knockback_duration
		_move_knockback(_knockback_impulse * strength * step_time)
		_knockback_remaining = maxf(_knockback_remaining - delta, 0.0)
		_path_refresh_timer = 0.0


## 子类调用 super._physics_process() 后应优先处理这一状态，避免 AI 覆盖击退。
func is_receiving_knockback() -> bool:
	return _knockback_remaining > 0.0 or _knockback_applied_this_frame


func _update_hit_flash() -> void:
	var visual := get_node_or_null("Visual") as CanvasItem
	if visual != null and visual.material is ShaderMaterial:
		(visual.material as ShaderMaterial).set_shader_parameter("hit_flash", 1.0 if _hit_flash_remaining > 0.0 else 0.0)


func _resolve_knockback(hit: CombatHit) -> Vector2:
	if not hit.knockback.is_zero_approx():
		# 同方向加算：武器击退强度 + 模板基础击退强度。
		return hit.knockback + hit.knockback.normalized() * default_knockback_speed
	var direction: Vector2 = Vector2.ZERO
	if is_instance_valid(hit.source) and hit.source != self:
		direction = hit.source.global_position.direction_to(global_position)
	if direction.is_zero_approx() and not hit.position.is_equal_approx(global_position):
		direction = hit.position.direction_to(global_position)
	if direction.is_zero_approx() and is_instance_valid(player):
		direction = player.global_position.direction_to(global_position)
	if direction.is_zero_approx():
		direction = Vector2.UP
	return direction * default_knockback_speed


func _move_knockback(motion: Vector2) -> void:
	# 小步检查程序化地形，再让物理引擎扫掠身体，不能被击退穿过墙体。
	var steps: int = maxi(ceili(motion.length() / (WorldGenerator.TILE_SIZE * 0.25)), 1)
	var step: Vector2 = motion / float(steps)
	for _index: int in steps:
		var destination: Vector2 = global_position + step
		if world_generator != null and not is_navigation_tile_allowed(WorldGenerator.world_to_tile(destination)):
			_knockback_impulse = Vector2.ZERO
			break
		if move_and_collide(step) != null:
			_knockback_impulse = Vector2.ZERO
			break


func _update_visual_pose() -> void:
	var visual := get_node_or_null("Visual") as Node2D
	if visual != null:
		visual.position = visual_pose + Vector2(0.0, -_visual_height)
		visual.modulate = visual_tint
	queue_redraw()


func _on_monster_damaged(hit: CombatHit, _actual_damage: float) -> void:
	_hit_flash_remaining = hit_flash_duration
	_update_hit_flash()
	var health_component := get_node_or_null("Health") as HealthComponent
	if not health_component.is_alive():
		return
	stop_navigation()
	_knockback_impulse = _resolve_knockback(hit)
	_knockback_remaining = knockback_duration if not _knockback_impulse.is_zero_approx() else 0.0
	# 受击打断动作，包括跳跃；Hurt 的高度轨道会立即落地归零。
	play_monster_animation(&"Hurt", true)


func _on_monster_died(_hit: CombatHit) -> void:
	kill()


func play_monster_animation(state: StringName, restart: bool = false) -> void:
	if animation_playback == null:
		return
	if restart:
		animation_playback.start(state)
	elif animation_playback.get_current_node() != state:
		animation_playback.travel(state)
	else:
		return
	animation_tree.advance(0.0)
	# travel 首次求值处理状态切换，第二次应用新状态的初始轨道。
	animation_tree.advance(0.0)


func monster_animation_state() -> StringName:
	return animation_playback.get_current_node() if animation_playback != null else &"Idle"


func advance_monster_animation(delta: float) -> void:
	if animation_tree != null:
		animation_tree.advance(delta)


func _setup_health_bar() -> void:
	var health_component := get_node_or_null("Health") as HealthComponent
	if health_component == null:
		return

	health_bar = get_node_or_null("HealthBar") as ProgressBar
	if health_bar == null:
		health_bar = ProgressBar.new()
		health_bar.name = "HealthBar"
		add_child(health_bar)
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.size = Vector2(28.0, 4.0)
	health_bar.position = Vector2(-14.0, -22.0)
	health_bar.z_index = 1
	var name_label := get_node_or_null("NameLabel") as Label
	if name_label != null:
		health_bar.position.y = name_label.position.y + name_label.size.y + 1.0

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.10, 0.08, 0.08, 0.95)
	background.border_color = Color(0.02, 0.02, 0.02)
	background.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.78, 0.18, 0.16)
	health_bar.add_theme_stylebox_override("background", background)
	health_bar.add_theme_stylebox_override("fill", fill)
	health_component.health_changed.connect(_update_health_bar)
	_update_health_bar(health_component.current_health, health_component.max_health)


func _update_health_bar(current: float, maximum: float) -> void:
	health_bar.max_value = maxf(maximum, 1.0)
	health_bar.value = current


## 调试全灭与正常死亡共用；先释放怪物携带的道具，避免随父节点一起删除。
func kill() -> void:
	if is_queued_for_deletion():
		return
	play_monster_animation(&"Death", true)
	var world_parent: Node = get_parent()
	if world_parent != null:
		for child: Node in get_children():
			if child.is_in_group("ingredients") or child.is_in_group("throwable_stones"):
				child.reparent(world_parent, true)
	queue_free()


## MonsterSpawner 的统一初始化接口；子类需要扩展时调用 super.configure()。
func configure(
	target_player: PlayerCharacter,
	generator: WorldGenerator,
	chunk_coords: Vector2i
) -> void:
	configure_target(target_player, generator)
	spawn_chunk = chunk_coords


func configure_target(target_player: PlayerCharacter, generator: WorldGenerator) -> void:
	player = target_player
	world_generator = generator
	_knockback_impulse = Vector2.ZERO
	_knockback_remaining = 0.0
	_knockback_applied_this_frame = false
	_hit_flash_remaining = 0.0
	_update_hit_flash()
	clear_player_aggro()
	_path.clear()
	_path_index = 0
	_path_refresh_timer = 0.0
	_last_path_target = Vector2i(2147483647, 2147483647)


## 子类传入自身的索敌范围判断；首次仇恨只能在视线无遮挡时建立。
func try_acquire_player_aggro(within_detection_range: bool) -> bool:
	if _has_player_aggro:
		return true
	if within_detection_range and has_clear_line_to_player():
		_has_player_aggro = true
	return _has_player_aggro


func has_player_aggro() -> bool:
	return _has_player_aggro


func clear_player_aggro() -> void:
	_has_player_aggro = false
	_path.clear()
	_path_index = 0
	_path_refresh_timer = 0.0
	stop_navigation()


func has_clear_line_to_player() -> bool:
	if not is_instance_valid(player):
		return false
	return has_clear_line_to_position(player.global_position, player)


func has_clear_line_to_position(
	world_target: Vector2,
	allowed_collider: CollisionObject2D = null
) -> bool:
	if world_generator == null:
		return false

	_last_line_blocked_by_physics = false
	_last_physics_collider = null
	target_raycast.target_position = to_local(world_target)
	target_raycast.force_raycast_update()
	if target_raycast.is_colliding():
		var collider: Object = target_raycast.get_collider()
		if allowed_collider == null or collider != allowed_collider:
			_last_line_blocked_by_physics = true
			if collider is CollisionObject2D:
				_last_physics_collider = collider as CollisionObject2D
			return false

	return _terrain_line_is_clear(global_position, world_target)


## 沿线密集采样，弥补当前 TileSet 没有物理碰撞层、RayCast2D 看不到地形的问题。
func _terrain_line_is_clear(from: Vector2, to: Vector2) -> bool:
	var distance: float = from.distance_to(to)
	var step_length: float = float(WorldGenerator.TILE_SIZE) * 0.25
	var steps: int = maxi(ceili(distance / step_length), 1)
	for step: int in range(1, steps):
		var point: Vector2 = from.lerp(to, float(step) / float(steps))
		var tile: Vector2i = WorldGenerator.world_to_tile(point)
		if not is_navigation_tile_allowed(tile):
			return false
	return true


## 子类可追加自己的移动限制；默认仅检查地形可通行性。
func is_navigation_tile_allowed(tile: Vector2i) -> bool:
	return world_generator != null and world_generator.is_walkable(tile)


func navigate_toward_player(delta: float) -> bool:
	if is_receiving_knockback():
		return false
	if not has_player_aggro() or not is_instance_valid(player) or world_generator == null:
		stop_navigation()
		return false

	_path_refresh_timer = maxf(_path_refresh_timer - delta, 0.0)
	var target_tile: Vector2i = WorldGenerator.world_to_tile(player.global_position)
	if target_tile != _last_path_target or _path_refresh_timer <= 0.0:
		_rebuild_path(target_tile)

	while _path_index < _path.size():
		var waypoint: Vector2 = WorldGenerator.tile_to_world(_path[_path_index])
		if global_position.distance_to(waypoint) > 3.0:
			break
		_path_index += 1

	if _path_index >= _path.size():
		stop_navigation()
		return false

	var next_tile: Vector2i = _path[_path_index]
	if not is_navigation_tile_allowed(next_tile):
		_path_refresh_timer = 0.0
		stop_navigation()
		return false

	var next_position: Vector2 = WorldGenerator.tile_to_world(next_tile)
	velocity = global_position.direction_to(next_position) * navigation_speed
	move_and_slide()
	if get_slide_collision_count() > 0:
		_path_refresh_timer = 0.0
	play_monster_animation(&"Move")
	return true


func stop_navigation() -> void:
	velocity = Vector2.ZERO
	match monster_animation_state():
		&"Idle", &"Move":
			play_monster_animation(&"Idle")


func _rebuild_path(target_tile: Vector2i) -> void:
	_path.clear()
	_path_index = 0
	_last_path_target = target_tile
	_path_refresh_timer = path_refresh_interval

	var start_tile: Vector2i = WorldGenerator.world_to_tile(global_position)
	var margin := Vector2i(path_margin_tiles, path_margin_tiles)
	var min_tile := Vector2i(
		mini(start_tile.x, target_tile.x),
		mini(start_tile.y, target_tile.y)
	) - margin
	var max_tile := Vector2i(
		maxi(start_tile.x, target_tile.x),
		maxi(start_tile.y, target_tile.y)
	) + margin

	var grid := AStarGrid2D.new()
	grid.region = Rect2i(min_tile, max_tile - min_tile + Vector2i.ONE)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()

	var physics_solids: Dictionary = {}
	if _last_line_blocked_by_physics and is_instance_valid(_last_physics_collider):
		physics_solids = _physics_collider_tiles(_last_physics_collider)
	for y: int in range(min_tile.y, max_tile.y + 1):
		for x: int in range(min_tile.x, max_tile.x + 1):
			var tile := Vector2i(x, y)
			var blocked: bool = not is_navigation_tile_allowed(tile)
			if not blocked:
				blocked = physics_solids.has(tile)
			if blocked:
				grid.set_point_solid(tile, true)

	# 怪物当前格与玩家目标格必须能够作为路径端点。
	grid.set_point_solid(start_tile, false)
	if not is_navigation_tile_allowed(target_tile):
		return
	grid.set_point_solid(target_tile, false)

	var calculated: Array[Vector2i] = grid.get_id_path(start_tile, target_tile)
	if calculated.size() <= 1:
		return
	_path = calculated
	_path_index = 1


## 把 RayCast2D 命中的墙体形状一次转换为格子包围盒，供 AStar 标记阻挡。
func _physics_collider_tiles(collider: CollisionObject2D) -> Dictionary:
	var result: Dictionary = {}
	for child: Node in collider.get_children():
		if child is CollisionShape2D:
			var collision_shape := child as CollisionShape2D
			if collision_shape.disabled or collision_shape.shape == null:
				continue
			var points: PackedVector2Array = _shape_bounds_points(collision_shape.shape)
			_mark_bounds_tiles(result, collision_shape.global_transform, points)
		elif child is CollisionPolygon2D:
			var collision_polygon := child as CollisionPolygon2D
			if collision_polygon.disabled:
				continue
			_mark_bounds_tiles(
				result, collision_polygon.global_transform, collision_polygon.polygon
			)

	if result.is_empty() and collider is Node2D:
		result[WorldGenerator.world_to_tile((collider as Node2D).global_position)] = true
	return result


func _shape_bounds_points(shape: Shape2D) -> PackedVector2Array:
	if shape is RectangleShape2D:
		var half: Vector2 = (shape as RectangleShape2D).size * 0.5
		return PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y),
		])
	if shape is CircleShape2D:
		var radius: float = (shape as CircleShape2D).radius
		return PackedVector2Array([
			Vector2(-radius, -radius), Vector2(radius, -radius),
			Vector2(radius, radius), Vector2(-radius, radius),
		])
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		var capsule_half := Vector2(capsule.radius, capsule.height * 0.5)
		return PackedVector2Array([
			Vector2(-capsule_half.x, -capsule_half.y),
			Vector2(capsule_half.x, -capsule_half.y),
			Vector2(capsule_half.x, capsule_half.y),
			Vector2(-capsule_half.x, capsule_half.y),
		])
	if shape is ConvexPolygonShape2D:
		return (shape as ConvexPolygonShape2D).points
	if shape is SegmentShape2D:
		var segment := shape as SegmentShape2D
		return PackedVector2Array([segment.a, segment.b])
	return PackedVector2Array()


func _mark_bounds_tiles(
	result: Dictionary,
	shape_transform: Transform2D,
	local_points: PackedVector2Array
) -> void:
	if local_points.is_empty():
		return
	var first: Vector2 = shape_transform * local_points[0]
	var bounds := Rect2(first, Vector2.ZERO)
	for index: int in range(1, local_points.size()):
		bounds = bounds.expand(shape_transform * local_points[index])

	var epsilon := Vector2(0.01, 0.01)
	var min_tile: Vector2i = WorldGenerator.world_to_tile(bounds.position + epsilon)
	var max_tile: Vector2i = WorldGenerator.world_to_tile(bounds.end - epsilon)
	for y: int in range(min_tile.y, max_tile.y + 1):
		for x: int in range(min_tile.x, max_tile.x + 1):
			result[Vector2i(x, y)] = true
