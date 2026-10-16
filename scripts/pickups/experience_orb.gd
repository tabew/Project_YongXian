class_name ExperienceOrb
extends Node2D

## 击杀掉落的经验球：落地后先停顿一会儿，再朝玩家加速飞入，接触即结算经验。
##
## 停顿是有意为之：让玩家看清“这里死了东西”，也避免怪物贴脸时经验瞬间消失。

signal absorbed(amount: float)

## 停顿时间（秒）。
const DELAY_SECONDS: float = 0.45
const FLY_ACCELERATION: float = 900.0
const FLY_MAX_SPEED: float = 620.0
const COLLECT_DISTANCE: float = 14.0
const BOB_HEIGHT: float = 3.0
const BOB_SPEED: float = 6.0

var amount: float = 1.0

var _player: PlayerCharacter = null
var _elapsed: float = 0.0
var _flying: bool = false
var _speed: float = 0.0
var _collected: bool = false
var _origin: Vector2 = Vector2.ZERO
var _sprite: Sprite2D = null


func _ready() -> void:
	add_to_group("experience_orbs")
	_origin = global_position
	_build_visual()


func bind(value: float, target: PlayerCharacter) -> void:
	amount = maxf(value, 0.0)
	_player = target
	_origin = global_position
	_elapsed = 0.0
	_flying = false
	_speed = 0.0
	_collected = false


func _process(delta: float) -> void:
	if _collected:
		return
	_elapsed += delta
	if not _flying:
		# 停顿阶段只做轻微起伏，让球停在死亡位置。
		if _sprite != null:
			_sprite.position = Vector2(0.0, -2.0 - sin(_elapsed * BOB_SPEED) * BOB_HEIGHT)
		if _elapsed >= DELAY_SECONDS:
			_flying = true
		return
	if not is_instance_valid(_player):
		# 玩家不在（切图/死亡）时原地等待，回来再飞。
		return
	var target: Vector2 = _player.global_position
	_speed = minf(_speed + FLY_ACCELERATION * delta, FLY_MAX_SPEED)
	var step: Vector2 = (target - global_position).normalized() * _speed * delta
	if step.length() >= global_position.distance_to(target) - COLLECT_DISTANCE * 0.5:
		global_position = target
		_collect()
		return
	global_position += step


func _collect() -> void:
	if _collected:
		return
	_collected = true
	var progress: Node = get_node_or_null("/root/RunProgress")
	if progress != null and amount > 0.0:
		progress.add_experience(amount)
	absorbed.emit(amount)
	queue_free()


func _build_visual() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func _draw() -> void:
	# 小菱形光点：不依赖美术资源，和地面材料的像素风格一致。
	var center := Vector2(0.0, -2.0)
	draw_rect(Rect2(-6.0, 2.0, 12.0, 2.0), Color(0.08, 0.09, 0.06, 0.28))
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(0.0, -5.0),
			center + Vector2(4.0, 0.0),
			center + Vector2(0.0, 5.0),
			center + Vector2(-4.0, 0.0),
		]),
		Color(0.62, 0.92, 0.86, 0.95)
	)
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(0.0, -2.5),
			center + Vector2(2.0, 0.0),
			center + Vector2(0.0, 2.5),
			center + Vector2(-2.0, 0.0),
		]),
		Color(0.93, 1.0, 0.98, 1.0)
	)