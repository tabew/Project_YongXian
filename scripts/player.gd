class_name PlayerCharacter
extends CharacterBody2D

## 主角占位实现：WASD / 方向键控制，速度带加速度与摩擦力，摄像机跟随。
##
## 地形阻挡不依赖物理层，而是直接查询 MapData 的格子是否可通行，
## 后期若改用 TileSet 碰撞层，只要把 collide_with_terrain 关掉即可。

@export_group("移动手感")
## 最大速度（像素/秒）。
@export var max_speed: float = 220.0
## 加速度：按住方向键时每秒增加多少速度。
@export var acceleration: float = 1400.0
## 摩擦力：松开按键后每秒衰减多少速度。
@export var friction: float = 1800.0

@export_group("地形")
## 打开后无法走进水域、山地和雪地。
@export var collide_with_terrain: bool = true

@onready var sprite: Sprite2D = $Sprite2D

## 当前所在地图，由 GameWorld 铺好地图后注入。
var map_data: MapData = null


func _physics_process(delta: float) -> void:
	var input_direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	_apply_input(input_direction, delta)
	_integrate_movement(delta)
	_update_facing()


## 有输入时朝目标速度加速，松手后按摩擦力减速到 0。
func _apply_input(input_direction: Vector2, delta: float) -> void:
	if input_direction != Vector2.ZERO:
		var target_velocity: Vector2 = input_direction * max_speed
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


func _integrate_movement(delta: float) -> void:
	if map_data == null or not collide_with_terrain:
		move_and_slide()
		return

	# 分轴推进：撞到障碍时只损失该轴的速度，贴边移动依然顺滑
	var step: Vector2 = velocity * delta

	var next_x: Vector2 = global_position + Vector2(step.x, 0.0)
	if can_stand_at(next_x):
		global_position.x = next_x.x
	else:
		velocity.x = 0.0

	var next_y: Vector2 = global_position + Vector2(0.0, step.y)
	if can_stand_at(next_y):
		global_position.y = next_y.y
	else:
		velocity.y = 0.0


## 该世界坐标所在的格子是否可通行。
func can_stand_at(world_position: Vector2) -> bool:
	if map_data == null:
		return true
	var tile: Vector2i = map_data.world_to_terrain(world_position)
	return map_data.is_walkable(tile.x, tile.y)


## 由 GameWorld 调用：注入地图并把主角放到出生点。
func spawn_on_map(map: MapData) -> void:
	map_data = map
	velocity = Vector2.ZERO
	global_position = map.terrain_to_world(map.spawn_tile)


func _update_facing() -> void:
	if absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0.0
