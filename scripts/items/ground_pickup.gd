class_name GroundPickup
extends Node2D

## 世界地面材料；与炼金界面内的 ItemModel 物理模型分离。
## 由 GameWorld 选择最近物品后显式调用 collect，不监听输入或自动拾取。
signal collected(item_id: int, amount: int)

## 地面物品：材料、药水、武器都能落地（都是 ItemData 子类）。
var data: ItemData = null
var amount: int = 1
var _sprite: Sprite2D = null
var _collected: bool = false
var _highlighted: bool = false
var _generator: WorldGenerator = null
var _in_flight: bool = false
var _throw_target: Node2D = null
var _throw_damage: float = 0.0
var _throw_start: Vector2 = Vector2.ZERO
var _throw_destination: Vector2 = Vector2.ZERO
var _throw_elapsed: float = 0.0
var _throw_duration: float = 0.0

const THROW_SPEED: float = 320.0
const THROW_ARC_HEIGHT: float = 16.0
const THROW_HIT_RADIUS: float = 10.0


func _ready() -> void:
	add_to_group("ground_pickups")
	set_physics_process(false)
	_update_visual()


func bind(item: ItemData, quantity: int = 1, generator: WorldGenerator = null) -> void:
	data = item
	amount = maxi(quantity, 0)
	_generator = generator
	_collected = false
	_in_flight = false
	_throw_target = null
	set_physics_process(false)
	_update_visual()


func collect(player: PlayerCharacter) -> bool:
	if not is_available_for_pickup():
		return false
	if not is_instance_valid(player) or player.inventory == null:
		return false
	# 先标记，避免 inventory_update 的同步监听者重复收取本节点。
	_collected = true
	_update_throwable_group()
	player.inventory.add_item(data.id, amount)
	_play_sfx(&"pickup_material", global_position)
	collected.emit(data.id, amount)
	visible = false
	queue_free()
	return true


func is_available_for_pickup() -> bool:
	return not _collected and not _in_flight and not is_queued_for_deletion() and data != null and amount > 0


func can_be_thrown() -> bool:
	# 只有材料里的石块一类能投掷；药水与武器走各自的使用方式。
	return (
		is_available_for_pickup()
		and data is IngredientData
		and GroundMaterials.is_throwable(data.id)
		and is_inside_tree()
		and is_visible_in_tree()
		and can_process()
	)


## 使用现有地面石头作为弹体，落地后仍是同一份材料；目标位置在出手时固定。
func throw_at(target: Node2D, damage: float) -> bool:
	if not can_be_thrown() or not is_instance_valid(target):
		return false
	if amount > 1:
		var piece := GroundPickup.new()
		piece.bind(data, 1, _generator)
		get_parent().add_child(piece)
		piece.global_position = global_position
		if not piece.throw_at(target, damage):
			piece.queue_free()
			return false
		amount -= 1
		_update_visual()
		return true
	var owner_node: Node = get_parent()
	if owner_node.is_in_group("monsters") and owner_node.get_parent() != null:
		reparent(owner_node.get_parent(), true)
	_in_flight = true
	_throw_target = target
	_throw_damage = maxf(damage, 0.0)
	_throw_start = global_position
	_throw_destination = target.global_position
	_throw_elapsed = 0.0
	_throw_duration = clampf(_throw_start.distance_to(_throw_destination) / THROW_SPEED, 0.18, 0.60)
	set_highlighted(false)
	_update_throwable_group()
	set_physics_process(true)
	_play_sfx(&"stone_throw", global_position)
	return true


func _physics_process(delta: float) -> void:
	if not _in_flight:
		return
	_throw_elapsed += delta
	var progress: float = minf(_throw_elapsed / _throw_duration, 1.0)
	var from: Vector2 = global_position
	var next: Vector2 = _throw_start.lerp(_throw_destination, progress)
	var blocked: float = _terrain_block_fraction(from, next)
	var query := PhysicsRayQueryParameters2D.create(from, next, 1)
	if is_instance_valid(_throw_target) and _throw_target is CollisionObject2D:
		query.exclude = [(_throw_target as CollisionObject2D).get_rid()]
	var wall: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not wall.is_empty():
		var distance: float = from.distance_to(next)
		blocked = minf(blocked, from.distance_to(wall["position"]) / maxf(distance, 0.001))
	var hit: float = -1.0
	if is_instance_valid(_throw_target) and _throw_target.is_visible_in_tree():
		if from.distance_to(_throw_target.global_position) <= THROW_HIT_RADIUS:
			hit = 0.0
		elif from != next:
			hit = Geometry2D.segment_intersects_circle(from, next, _throw_target.global_position, THROW_HIT_RADIUS)
	if hit >= 0.0 and hit < blocked:
		global_position = from.lerp(next, hit)
		if _throw_target.has_method("take_damage"):
			_throw_target.call("take_damage", _throw_damage)
		_finish_throw()
		return
	if blocked <= 1.0:
		global_position = from.lerp(next, maxf(blocked - 0.001, 0.0))
		_finish_throw()
		return
	global_position = next
	_sprite.position = Vector2(0, -2 - sin(progress * PI) * THROW_ARC_HEIGHT)
	if progress >= 1.0:
		_finish_throw()


func _finish_throw() -> void:
	_in_flight = false
	_throw_target = null
	set_physics_process(false)
	_update_visual()
	_play_sfx(&"stone_land", global_position)


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载。
func _play_sfx(id: StringName, position: Vector2 = Vector2.INF) -> void:
	var manager: Node = get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.call("play_sfx", id, position)


## 枚举整段扫过的格子，含恰好擦过的对角格，避免高速投石穿过虚拟地形墙。
func _terrain_block_fraction(from: Vector2, to: Vector2) -> float:
	if _generator == null:
		return INF
	var current: Vector2i = WorldGenerator.world_to_tile(from)
	var end: Vector2i = WorldGenerator.world_to_tile(to)
	if not _generator.is_walkable(current):
		return 0.0
	var direction: Vector2 = to - from
	var step := Vector2i(signi(end.x - current.x), signi(end.y - current.y))
	var size: float = float(WorldGenerator.TILE_SIZE)
	var delta_x: float = absf(size / direction.x) if step.x != 0 else INF
	var delta_y: float = absf(size / direction.y) if step.y != 0 else INF
	var next_x: float = (float(current.x + maxi(step.x, 0)) * size - from.x) / direction.x if step.x != 0 else INF
	var next_y: float = (float(current.y + maxi(step.y, 0)) * size - from.y) / direction.y if step.y != 0 else INF
	var remaining: int = absi(end.x - current.x) + absi(end.y - current.y) + 2
	while current != end and remaining > 0:
		remaining -= 1
		# 到达终点的某一轴后不再推进该轴，避免近似相等在末端误判成对角穿越。
		if current.x == end.x:
			next_x = INF
		if current.y == end.y:
			next_y = INF
		var crossing: float = minf(next_x, next_y)
		if crossing > 1.0:
			return INF
		if next_x != INF and next_y != INF and is_equal_approx(next_x, next_y):
			if not _generator.is_walkable(current + Vector2i(step.x, 0)) or not _generator.is_walkable(current + Vector2i(0, step.y)):
				return crossing
			current += step
			next_x += delta_x
			next_y += delta_y
		elif next_x < next_y:
			current.x += step.x
			next_x += delta_x
		else:
			current.y += step.y
			next_y += delta_y
		if not _generator.is_walkable(current):
			return crossing
	return INF if current == end else 0.0


func _update_throwable_group() -> void:
	var available: bool = is_available_for_pickup() and data != null and GroundMaterials.is_throwable(data.id)
	if available:
		add_to_group("throwable_stones")
	elif is_in_group("throwable_stones"):
		remove_from_group("throwable_stones")


## 可由世界层标记当前可拾取目标；无需每个物品独立处理输入或轮询。
func set_highlighted(value: bool) -> void:
	if _highlighted == value:
		return
	_highlighted = value
	queue_redraw()


func _update_visual() -> void:
	if not is_instance_valid(_sprite):
		_sprite = get_node_or_null("Sprite2D") as Sprite2D
		if _sprite == null:
			_sprite = Sprite2D.new()
			_sprite.name = "Sprite2D"
			add_child(_sprite)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position = Vector2(0, -2)
	_sprite.texture = data.texture if data != null else null
	# 宝箱可掉落不同原始分辨率的图标；世界内统一限制为一格大小。
	_sprite.scale = Vector2.ONE
	if _sprite.texture != null:
		var icon_size: Vector2 = _sprite.texture.get_size()
		_sprite.scale = Vector2.ONE * minf(1.0, 16.0 / maxf(icon_size.x, icon_size.y))
	visible = data != null and amount > 0 and not _collected
	_update_throwable_group()
	queue_redraw()


func _draw() -> void:
	if data == null or _collected:
		return
	# 阴影与高光保持静态像素边缘，避免大量物品各自运行动画。
	draw_rect(Rect2(-6, 3, 12, 2), Color(0.08, 0.09, 0.06, 0.30))
	draw_rect(Rect2(-4, 2, 8, 4), Color(0.08, 0.09, 0.06, 0.18))
	draw_rect(Rect2(5, -7, 2, 1), Color(1.0, 0.91, 0.66, 0.8))
	if _highlighted:
		draw_rect(Rect2(-9, -11, 18, 20), Color("f5dfa0"), false, 1.0)
