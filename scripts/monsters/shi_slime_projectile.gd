class_name ShiSlimeProjectile
extends Node2D

## 粘液弹为史专用弹体：固定出手方向、扫掠命中0.5，不参与材料拾取。
const SPEED: float = 180.0
const DAMAGE: float = 0.5
const LIFE_TIME: float = 2.0
var _host: ShiMonster
var _target: PlayerCharacter
var _direction: Vector2
var _age: float = 0.0
var _map: MapSpec
var _terrain_probe: GroundPickup
var _spent: bool = false


func launch(host: ShiMonster, target: PlayerCharacter, origin: Vector2) -> void:
	_host = host
	_target = target
	global_position = origin
	_direction = origin.direction_to(target.global_position)
	_map = host.world_generator.sample_map(WorldGenerator.world_to_tile(host.global_position)) if host.world_generator != null else null
	_terrain_probe = GroundPickup.new()
	_terrain_probe._generator = host.world_generator
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _spent:
		return
	if not is_instance_valid(_host) or not is_instance_valid(_target) or (_map != null and _target.active_map != null and _target.active_map != _map):
		_spend()
		return
	_age += delta
	if _age >= LIFE_TIME:
		_spend()
		return
	var from: Vector2 = global_position
	var to: Vector2 = from + _direction * SPEED * delta
	var blocked: float = _terrain_probe._terrain_block_fraction(from, to)
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	query.exclude = [_target.get_rid()]
	var wall: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not wall.is_empty():
		blocked = minf(blocked, from.distance_to(wall["position"]) / maxf(from.distance_to(to), 0.001))
	var hit: float = 0.0 if from.distance_to(_target.global_position) <= 7.0 else Geometry2D.segment_intersects_circle(from, to, _target.global_position, 7.0)
	if hit >= 0.0 and hit < blocked:
		_target.take_damage(DAMAGE)
		_spend()
	elif blocked <= 1.0:
		_spend()
	else:
		global_position = to


func _spend() -> void:
	_spent = true
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_terrain_probe):
		_terrain_probe.free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.0, Color("285642"))
	draw_circle(Vector2.ZERO, 3.0, Color("87d2a1"))
	draw_circle(Vector2(-1, -1), 1.0, Color("d0f6d8"))
