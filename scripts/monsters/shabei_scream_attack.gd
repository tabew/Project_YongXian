class_name ShabeiScreamAttack
extends EnemyAttack

const DURATION: float = 4.0
const LAYERS: int = 5
const LAYER_INTERVAL: float = DURATION / LAYERS
const RANGE: float = 15.0 * WorldGenerator.TILE_SIZE
var _busy: bool = false
var _elapsed: float = 0.0
var _emitted: int = 0
var _flee_timer: float = 0.0
var _failed_escape_tiles: Dictionary = {}
var _escape_target_position: Vector2 = Vector2.ZERO
var emitted_layers: Array[ShabeiSoundWave] = []

func attack_range() -> float:
	return RANGE
func attack_cooldown() -> float:
	return 1.0
func is_busy() -> bool:
	return _busy
func can_attack(host: BaseMonster, target: Node2D) -> bool:
	return not _busy and is_instance_valid(target) and host.global_position.distance_to(target.global_position) <= RANGE and host.has_clear_line_to_position(target.global_position, target as CollisionObject2D)
func perform_attack(monster: BaseMonster, target: Node2D) -> bool:
	if not can_attack(monster,target):
		return false
	var host := monster as ShabeiMonster
	_busy = true
	_elapsed = 0.0
	_emitted = 0
	_flee_timer = 0.0
	_failed_escape_tiles.clear()
	_escape_target_position = target.global_position
	emitted_layers.clear()
	host.begin_scream()
	_emit_layer(host)
	return true

func update(monster: BaseMonster, delta: float) -> void:
	if not _busy:
		return
	var host := monster as ShabeiMonster
	if not is_instance_valid(host.player) or host.player.health <= 0.0:
		_busy = false
		host.finish_flee()
		return
	if host.fleeing:
		_update_flee(host, delta)
		return
	host.velocity = Vector2.ZERO
	_elapsed = minf(_elapsed + delta, DURATION)
	while _emitted < LAYERS and _elapsed + 0.00001 >= _emitted * LAYER_INTERVAL:
		_emit_layer(host)
	if _elapsed + 0.00001 >= DURATION:
		_elapsed = DURATION
		host.screaming = false
		host.stop_scream_sound()
		host.fleeing = true
		host.mouth_open = 0.0
		host.play_monster_animation(&"Idle", true)
		host.navigator.clear()
		_update_flee(host,0.0)

func _emit_layer(host: ShabeiMonster) -> void:
	var wave := ShabeiSoundWave.new()
	host.get_parent().add_child(wave)
	wave.launch(host,host.player,host.global_position,host.global_position.direction_to(host.player.global_position))
	emitted_layers.append(wave)
	_emitted += 1
	host.blackboard.facing = host.global_position.direction_to(host.player.global_position)

func _update_flee(host: ShabeiMonster, delta: float) -> void:
	if host.global_position.distance_to(host.player.global_position) > RANGE:
		_busy = false
		host.finish_flee()
		return
	if host.player.global_position.distance_to(_escape_target_position) > 2.0 * WorldGenerator.TILE_SIZE:
		_escape_target_position = host.player.global_position
		_failed_escape_tiles.clear()
	if host.navigator.consume_failed_request():
		_failed_escape_tiles[host.navigator.last_target_tile] = true
		_flee_timer = 0.0
	_flee_timer = maxf(_flee_timer - delta,0.0)
	if _flee_timer <= 0.0 and not host.navigator.has_pending_request():
		_flee_timer = 0.4
		if not host.navigator.has_path() or host.navigator.refresh_timer <= 0.0:
			_request_escape(host)
	host.navigator.follow()
	if host.velocity.length_squared() > 1.0:
		host.blackboard.facing = host.velocity.normalized()

func _request_escape(host: ShabeiMonster) -> void:
	var away: Vector2 = host.player.global_position.direction_to(host.global_position)
	if away.is_zero_approx():
		away = host.blackboard.facing
	var candidates: Array[Vector2i] = []
	for distance: float in [6.0,4.0,8.0]:
		for angle: float in [0.0,PI/6.0,-PI/6.0,PI/3.0,-PI/3.0,PI/2.0,-PI/2.0]:
			var point: Vector2 = host.global_position + away.rotated(angle) * distance * WorldGenerator.TILE_SIZE
			var tile: Vector2i = WorldGenerator.world_to_tile(point)
			if point.distance_squared_to(host.player.global_position) <= host.global_position.distance_squared_to(host.player.global_position):
				continue
			if host.player.active_map != null:
				var local: Vector2i = tile - host.player.active_map.origin
				if not host.player.active_map.contains_local(local.x,local.y):
					continue
			if not _failed_escape_tiles.has(tile) and host.is_navigation_tile_allowed(tile) and not candidates.has(tile):
				candidates.append(tile)
	if candidates.is_empty():
		host.stop_navigation()
		return
	candidates.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return WorldGenerator.tile_to_world(a).distance_squared_to(host.player.global_position) > WorldGenerator.tile_to_world(b).distance_squared_to(host.player.global_position))
	# 同步失效结果立即试下个方向；排队结果沿用通用导航的刷新与失败标记。
	for tile: Vector2i in candidates:
		host.navigator.request_path(tile,true)
		if host.navigator.has_pending_request() or host.navigator.has_path():
			break

func cancel(monster: BaseMonster) -> void:
	_busy = false
	var host := monster as ShabeiMonster
	host.stop_scream_sound()
	host.screaming = false
	host.fleeing = false
	host.mouth_open = 0.0
	host._hop_active = false
	host._visual_height = 0.0
