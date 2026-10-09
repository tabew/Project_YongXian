class_name BaseMonster
extends CharacterBody2D

## 所有怪物共用的视线与寻路模板。
## RayCast2D 负责物理墙体，地形采样负责当前没有物理层的程序化阻挡格。

@export_group("寻路")
@export var navigation_speed: float = 72.0
@export var path_refresh_interval: float = 2.0
@export var path_margin_tiles: int = 6

@onready var target_raycast: RayCast2D = $TargetRayCast

var player: PlayerCharacter = null
var world_generator: WorldGenerator = null

var _path: Array[Vector2i] = []
var _path_index: int = 0
var _path_refresh_timer: float = 0.0
var _last_path_target: Vector2i = Vector2i(2147483647, 2147483647)
var _last_line_blocked_by_physics: bool = false
var _last_physics_collider: CollisionObject2D = null


func _ready() -> void:
	add_to_group("monsters")
	target_raycast.add_exception(self)


## 调试全灭与正常死亡共用；先释放怪物携带的道具，避免随父节点一起删除。
func kill() -> void:
	var world_parent: Node = get_parent()
	if world_parent != null:
		for child: Node in get_children():
			if child.is_in_group("ingredients") or child.is_in_group("throwable_stones"):
				child.reparent(world_parent, true)
	queue_free()


func configure_target(target_player: PlayerCharacter, generator: WorldGenerator) -> void:
	player = target_player
	world_generator = generator
	_path.clear()
	_path_index = 0
	_path_refresh_timer = 0.0
	_last_path_target = Vector2i(2147483647, 2147483647)


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


## 子类可追加群系限制；例如“给”不允许离开热带雨林。
func is_navigation_tile_allowed(tile: Vector2i) -> bool:
	return world_generator != null and world_generator.is_walkable(tile)


func navigate_toward_player(delta: float) -> bool:
	if not is_instance_valid(player) or world_generator == null:
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
	return true


func stop_navigation() -> void:
	velocity = Vector2.ZERO


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
