class_name PlayerCharacter
extends CharacterBody2D

## 主角占位实现：WASD / 方向键控制，速度带加速度与摩擦力，摄像机跟随。
##
## 地形阻挡不依赖物理层，而是直接问 WorldGenerator 这一格是什么地形。
## 生成器是纯函数式的（只由种子和坐标决定），所以判定结果和画面上看到的永远一致，
## 不需要等区块加载完。

@export_group("移动手感")
## 最大速度（像素/秒）。
@export var max_speed: float = 220.0
## 加速度：按住方向键时每秒增加多少速度。
@export var acceleration: float = 1400.0
## 摩擦力：松开按键后每秒衰减多少速度。
@export var friction: float = 1800.0

@export_group("地形")
## 打开后无法走进深水、浅水、山地和雪峰（路上的格子除外）。
@export var collide_with_terrain: bool = true

@export_group("武器")
## 按顺序循环装备；添加资源即可扩充，无需按武器类型分支。
@export var weapon_loadout: Array[WeaponDefinition] = []

@onready var sprite: Sprite2D = $Sprite2D
@onready var weapon_controller: WeaponController = $WeaponController

## 地形来源，由 GameWorld 注入。
var terrain_source: WorldGenerator = null

# 上一个查过的格子。主角一帧最多查两次，缓存一下省掉重复的噪声计算
var _cached_tile: Vector2i = Vector2i(2147483647, 2147483647)
var _cached_walkable: bool = true


func _physics_process(delta: float) -> void:
	weapon_controller.set_aim(get_global_mouse_position() - global_position)
	var input_direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	_apply_input(input_direction, delta)
	_integrate_movement(delta)
	_update_facing()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		weapon_controller.set_trigger_pressed(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_weapon"):
		equip_next_weapon()
		get_viewport().set_input_as_handled()


func equip_next_weapon() -> bool:
	var current_index: int = weapon_loadout.find(weapon_controller.equipped_weapon)
	for offset: int in range(1, weapon_loadout.size() + 1):
		var candidate: WeaponDefinition = weapon_loadout[(current_index + offset) % weapon_loadout.size()]
		if candidate != null and candidate != weapon_controller.equipped_weapon:
			if weapon_controller.equip(candidate):
				return true
	return false


func _input(event: InputEvent) -> void:
	# Release must also reach us when a UI control consumes the event.
	if event.is_action_released("attack"):
		weapon_controller.set_trigger_pressed(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(weapon_controller):
		weapon_controller.cancel_attack()


## 有输入时朝目标速度加速，松手后按摩擦力减速到 0。
func _apply_input(input_direction: Vector2, delta: float) -> void:
	if input_direction != Vector2.ZERO:
		var target_velocity: Vector2 = input_direction * max_speed
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


func _integrate_movement(delta: float) -> void:
	if terrain_source == null or not collide_with_terrain:
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


## 该世界坐标所在的格子是否可以站人。
## 判定交给生成器：地形可通行，或者那里是路（路会架桥 / 开山道）。
func can_stand_at(world_position: Vector2) -> bool:
	if terrain_source == null:
		return true

	var tile: Vector2i = WorldGenerator.world_to_tile(world_position)
	if tile != _cached_tile:
		_cached_tile = tile
		_cached_walkable = terrain_source.is_walkable(tile)
	return _cached_walkable


## 由 GameWorld 调用：注入地形来源并把主角放到指定世界坐标。
func spawn_on(source: WorldGenerator, world_position: Vector2) -> void:
	weapon_controller.cancel_attack()
	terrain_source = source
	velocity = Vector2.ZERO
	global_position = world_position
	_cached_tile = Vector2i(2147483647, 2147483647)


func _update_facing() -> void:
	if weapon_controller.is_attacking():
		sprite.flip_h = weapon_controller.locked_aim().x < 0.0
	elif absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0.0
