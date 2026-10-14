class_name InspirationPickup
extends Node2D

## 单个灵感光点：生成 → 散开 → 悬停 → 无条件飞向玩家 → 飞入。
## 只负责表现与位移；账本由 InspirationManager 维护。
## 穿墙：不参与物理，也不做任何阻挡判定。

## 光点飞入完成，携带应计入的灵感数量。
signal arrived(amount: int)

## 目标节点（玩家）。为空时光点原地悬停，不会丢失。
var target: Node2D = null
## 本光点的灵感数量。
var amount: int = 1
## 来源类型，决定悬停时长 / 轨迹 / 音效。
var source: int = InspirationRules.Source.NORMAL
## 光团：合并后的大光点，飞入时把数字拆开。
var is_cluster: bool = false
## 光团拆分后的明细（供飘字逐个弹出）。
var cluster_parts: PackedInt32Array = PackedInt32Array()

var _elapsed: float = 0.0
var _active: bool = false
var _start_position: Vector2 = Vector2.ZERO
var _scatter_direction: Vector2 = Vector2.RIGHT
var _scatter_distance: float = 1.0
var _hover_position: Vector2 = Vector2.ZERO
var _fly_elapsed: float = 0.0
var _fly_duration: float = 0.6
var _hover_duration: float = 0.2
var _trail: Array[Vector2] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 60
	set_process(false)


## 启动一个光点。seed 决定散开方向，保证可复现。
func launch(position: Vector2, value: int, source_type: int, target_node: Node2D, seed_value: int = 0) -> void:
	global_position = position
	_start_position = position
	_hover_position = position
	amount = maxi(value, 1)
	source = source_type
	target = target_node
	_elapsed = 0.0
	_fly_elapsed = 0.0
	_trail.clear()
	_active = true
	_rng.seed = seed_value if seed_value != 0 else randi()

	_hover_duration = InspirationDrop.hover_duration(source)
	_scatter_distance = _rng.randf_range(InspirationDrop.SCATTER_DISTANCE_MIN, InspirationDrop.SCATTER_DISTANCE_MAX)
	var angle: float = _rng.randf_range(0.0, TAU)
	_scatter_direction = Vector2(cos(angle), sin(angle))
	# 飞入时长按当前距离估个合理值，保证速度曲线看得到"先慢后快"。
	_fly_duration = 0.6

	visible = true
	set_process(true)
	queue_redraw()
	_play_sfx(InspirationDrop.sfx_of(source), global_position)


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载（与 player.gd 一致）。
func _play_sfx(id: StringName, position: Vector2 = Vector2.INF) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.call("play_sfx", id, position)


## 回收进对象池。
func deactivate() -> void:
	_active = false
	visible = false
	set_process(false)
	_trail.clear()
	target = null
	is_cluster = false
	cluster_parts = PackedInt32Array()


func is_active() -> bool:
	return _active


func phase() -> int:
	return InspirationFlight.phase_at(_elapsed, _hover_duration)


func _process(delta: float) -> void:
	if not _active:
		return
	var previous: Vector2 = global_position
	_elapsed += delta

	var current_phase: int = phase()
	if current_phase == InspirationFlight.Phase.BURST or current_phase == InspirationFlight.Phase.SCATTER:
		var offset: Vector2 = InspirationFlight.scatter_offset(_elapsed, _scatter_direction, _scatter_distance)
		global_position = _start_position + offset
		_hover_position = global_position
	elif current_phase == InspirationFlight.Phase.HOVER:
		global_position = _hover_position + Vector2(0.0, InspirationFlight.hover_bob(_elapsed))
	else:
		_fly_elapsed += delta
		var destination: Vector2 = _hover_position if target == null else target.global_position
		# 实时追踪：每帧都拿玩家最新位置，所以不存在"追不上"。
		if _fly_elapsed >= _fly_duration:
			global_position = destination
		else:
			var start: Vector2 = _hover_position
			if InspirationDrop.trajectory_of(source) == InspirationDrop.Trajectory.SPIRAL:
				global_position = InspirationFlight.spiral_position_at(start, destination, _fly_elapsed, _fly_duration)
			else:
				global_position = InspirationFlight.position_at(start, destination, _fly_elapsed, _fly_duration)
		modulate.a = InspirationFlight.arrival_scale(_fly_elapsed, _fly_duration)
		if _fly_elapsed >= _fly_duration:
			_finish()
			return

	_update_trail(previous)
	queue_redraw()


func _finish() -> void:
	_active = false
	set_process(false)
	modulate.a = 1.0
	visible = false
	arrived.emit(amount)


func _update_trail(previous: Vector2) -> void:
	_trail.push_front(previous)
	var limit: int = InspirationFlight.trail_segments_for(amount)
	while _trail.size() > limit:
		_trail.pop_back()


func _draw() -> void:
	var segments: int = InspirationFlight.trail_segments_for(amount)
	for index: int in _trail.size():
		var offset: Vector2 = _trail[index] - global_position
		var radius: float = InspirationFlight.diameter_for(amount) * 0.5 * InspirationFlight.trail_scale(index, segments)
		draw_circle(offset, maxf(radius, 0.6), InspirationFlight.trail_color(index, segments))

	var radius_main: float = InspirationFlight.diameter_for(amount) * 0.5
	if is_cluster:
		radius_main *= 1.8
	draw_circle(Vector2.ZERO, radius_main, Color(1.0, 0.93, 0.62))
	draw_circle(Vector2.ZERO, radius_main * 0.5, Color(1.0, 1.0, 0.9))
