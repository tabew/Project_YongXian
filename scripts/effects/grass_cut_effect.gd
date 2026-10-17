class_name GrassCutEffect
extends Node2D

## 草丛被武器切断时飞散的草屑：几片像素受重力下落、快速淡出。
## 与 GroundPickup 一样通过 /root 查找自动加载单例，避免编译期依赖。

const DURATION: float = 0.30
const FLECKS: int = 4
const GRAVITY: float = 420.0
const COLORS: Array[Color] = [
	Color("4d8f38"), Color("71ad4d"), Color("93c466"), Color("356b2a")
]

var _elapsed: float = 0.0
var _offsets: PackedVector2Array = PackedVector2Array()
var _velocities: PackedVector2Array = PackedVector2Array()
var _colors: Array[Color] = []


## 在草丛位置生成一簇草屑；tint 与对应草丛的色调一致。
static func spawn(parent: Node, world_position: Vector2, tint: float) -> GrassCutEffect:
	if parent == null or not parent.is_inside_tree():
		return null
	var effect := GrassCutEffect.new()
	parent.add_child(effect)
	effect.global_position = world_position
	effect._setup(tint)
	return effect


func _setup(tint: float) -> void:
	var source := RandomNumberGenerator.new()
	source.seed = hash([global_position.x, global_position.y, Time.get_ticks_usec()])
	for index: int in FLECKS:
		_offsets.append(Vector2(source.randf_range(-3.0, 3.0), source.randf_range(-2.0, 1.0)))
		_velocities.append(Vector2(
			source.randf_range(-55.0, 55.0),
			source.randf_range(-150.0, -70.0)
		))
		_colors.append(COLORS[index % COLORS.size()].lerp(Color("c8e39a"), tint * 0.35))
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress: float = clampf(_elapsed / DURATION, 0.0, 1.0)
	var alpha: float = 1.0 - progress
	for index: int in FLECKS:
		var at: Vector2 = _offsets[index] + _velocities[index] * _elapsed \
			+ Vector2(0.0, 0.5 * GRAVITY * _elapsed * _elapsed)
		var color: Color = _colors[index]
		color.a *= alpha
		var size: float = lerpf(2.6, 1.2, progress)
		draw_rect(Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)), color)
