class_name EnemyPathfinder
extends RefCounted

## 静态 A* 工具：把怪物周围的可通行地形与最近命中的物理墙体转成格阻挡后求路径。
## 与旧 BaseMonster 内部实现等价，抽出来供 EnemyNavigator 与 PathRequestScheduler 共享。

const INVALID_TILE: Vector2i = Vector2i(2147483647, 2147483647)


static func build_path(
	host: BaseMonster,
	start_tile: Vector2i,
	target_tile: Vector2i,
	margin_tiles: int,
	physics_solids: Dictionary
) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if host == null or host.world_generator == null:
		return empty
	if start_tile == target_tile or not host.is_navigation_tile_allowed(target_tile):
		return empty

	var margin := Vector2i(margin_tiles, margin_tiles)
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

	for y: int in range(min_tile.y, max_tile.y + 1):
		for x: int in range(min_tile.x, max_tile.x + 1):
			var tile := Vector2i(x, y)
			var blocked: bool = not host.is_navigation_tile_allowed(tile)
			if not blocked:
				blocked = physics_solids.has(tile)
			if blocked:
				grid.set_point_solid(tile, true)

	# 怪物当前格与目标格必须能够作为路径端点。
	grid.set_point_solid(start_tile, false)
	if not host.is_navigation_tile_allowed(target_tile):
		return empty
	grid.set_point_solid(target_tile, false)

	var calculated: Array[Vector2i] = grid.get_id_path(start_tile, target_tile)
	if calculated.size() <= 1:
		return empty
	return calculated


## 把 RayCast2D 命中的墙体形状一次转换为格子包围盒，供 AStar 标记阻挡。
static func physics_collider_tiles(collider: CollisionObject2D) -> Dictionary:
	var result: Dictionary = {}
	if collider == null:
		return result
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


static func _shape_bounds_points(shape: Shape2D) -> PackedVector2Array:
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


static func _mark_bounds_tiles(
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
