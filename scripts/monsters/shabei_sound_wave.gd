class_name ShabeiSoundWave
extends Node2D

## 每层自己的释放圆心、半径与一次命中记录，不使用全局共享传播距离。
const MAX_RADIUS: float = 15.0 * WorldGenerator.TILE_SIZE
const SPEED: float = 120.0
const HALF_ANGLE: float = PI / 6.0
const WIDTH: float = 6.0
const PLAYER_RADIUS: float = 7.0
## 单层伤害。与玩家 100 点生命刻度配套（玩家 10 点刻度时为 1.0），
## 满一次咆哮 5 层合计 50 点，比例与旧刻度一致。
const DAMAGE: float = 10.0
var radius: float = 0.0
var _host: ShabeiMonster
var _target: PlayerCharacter
var _direction: Vector2
var _map: MapSpec
var _probe: GroundPickup
var _hit: bool = false
var _spent: bool = false

func launch(host: ShabeiMonster,target: PlayerCharacter,origin: Vector2,direction: Vector2) -> void:
	_host = host
	_target = target
	global_position = origin
	_direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	_map = host.world_generator.sample_map(WorldGenerator.world_to_tile(origin)) if host.world_generator != null else null
	_probe = GroundPickup.new()
	_probe._generator = host.world_generator
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _spent:
		return
	if not is_instance_valid(_host) or not is_instance_valid(_target) or (_map != null and _target.active_map != null and _target.active_map != _map):
		_spend()
		return
	var previous: float = radius
	radius = minf(radius + SPEED * delta,MAX_RADIUS)
	if not _hit and _crosses_player(previous,radius) and _clear_to_player():
		_hit = true
		_target.take_damage(_host.outgoing_damage(DAMAGE))
	queue_redraw()
	if radius >= MAX_RADIUS:
		_spend()

func _crosses_player(previous: float,current: float) -> bool:
	var offset: Vector2 = _target.global_position - global_position
	var distance: float = offset.length()
	if distance > MAX_RADIUS + PLAYER_RADIUS or distance + PLAYER_RADIUS < previous - WIDTH or distance - PLAYER_RADIUS > current + WIDTH:
		return false
	var angle_margin: float = asin(clampf(PLAYER_RADIUS / maxf(distance,PLAYER_RADIUS),0.0,1.0))
	return absf(_direction.angle_to(offset)) <= HALF_ANGLE + angle_margin

func _clear_to_player() -> bool:
	var target: Vector2 = _target.global_position
	if _probe._terrain_block_fraction(global_position,target) <= 1.0:
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position,target,1)
	query.exclude = [_host.get_rid(),_target.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _spend() -> void:
	_spent = true
	queue_free()
func _exit_tree() -> void:
	if is_instance_valid(_probe):
		_probe.free()
func _draw() -> void:
	var angle: float = _direction.angle()
	var alpha: float = 1.0 - radius/MAX_RADIUS * 0.55
	draw_arc(Vector2.ZERO,maxf(radius,1.0),angle-HALF_ANGLE,angle+HALF_ANGLE,32,Color(0.55,0.83,1.0,alpha),WIDTH,true)
	draw_arc(Vector2.ZERO,maxf(radius-3.0,1.0),angle-HALF_ANGLE,angle+HALF_ANGLE,32,Color(0.95,0.99,1.0,alpha),1.5,true)
