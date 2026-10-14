class_name EnemyBrain
extends RefCounted

## 通用四状态 AI：Patrol / Chase / Attack / Search。
##
## 每个怪物一个实例，持有自己的黑板与随机序列；共享配置、感知服务、路径调度与事件总线。
## 硬性规则：丢失玩家视野后以怪物当前位置作为新的 PatrolAnchor，绝不回出生点或原巡逻点，
## 因此状态集合里没有 Return / GoHome / Flee。
##
## 每帧只做便宜的计时与路径跟随；感知、状态转换、选点与寻路请求按 update_interval 分帧，
## 并用随机 stagger 打散，远处怪物再乘上 LOD 倍率。

const TILE_SIZE: float = float(WorldGenerator.TILE_SIZE)

var host: BaseMonster = null
var config: EnemyAIConfig = null
var blackboard: EnemyBlackboard = null
var perception: EnemyPerception = null
var navigator: EnemyNavigator = null
var attack: EnemyAttack = null

var _rng := RandomNumberGenerator.new()
var _update_accumulator: float = 0.0
var _lod_active: bool = false


func setup(
	monster: BaseMonster,
	ai_config: EnemyAIConfig,
	board: EnemyBlackboard,
	senses: EnemyPerception,
	navigation: EnemyNavigator,
	attack_impl: EnemyAttack,
	seed_value: int
) -> void:
	host = monster
	config = ai_config
	blackboard = board
	perception = senses
	navigator = navigation
	attack = attack_impl

	_rng.seed = seed_value
	_lod_active = false
	# stagger：用确定性随机把决策起点打散到 update_interval 内，避免同一帧集体决策。
	_update_accumulator = _rng.randf() * config.update_interval
	blackboard.state = EnemyState.State.PATROL
	blackboard.state_elapsed = 0.0
	blackboard.attack_cooldown = 0.0
	blackboard.perception_timer = 0.0
	blackboard.action_timer = 0.0
	blackboard.patrol_wait_remaining = config.patrol_start_delay
	blackboard.facing = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	blackboard.clear_target()
	blackboard.clear_search()


func current_state() -> EnemyState.State:
	return blackboard.state if blackboard != null else EnemyState.State.PATROL


func is_lod_active() -> bool:
	return _lod_active


## 每帧驱动：计时 -> 分帧决策 -> 每帧动作。
func tick(delta: float) -> void:
	if host == null or config == null or blackboard == null:
		return
	if not is_instance_valid(host.player) or host.world_generator == null:
		return
	_advance_timers(delta)
	if attack != null and attack.is_busy():
		attack.update(host, delta)
		return
	var interval: float = _effective_update_interval()
	_update_accumulator += delta
	if interval <= 0.0 or _update_accumulator >= interval:
		_update_accumulator = 0.0
		_decide()
	_act(delta)


## 外部脚本（例如 BaseMonster.clear_player_aggro）要求立刻放弃目标。
func abandon_target() -> void:
	if host == null or blackboard == null:
		return
	_lose_target()


## 受击等打断正在进行的攻击动作。
func interrupt_attack() -> void:
	if attack != null:
		attack.cancel(host)


func _advance_timers(delta: float) -> void:
	blackboard.attack_cooldown = maxf(blackboard.attack_cooldown - delta, 0.0)
	blackboard.state_elapsed += delta
	blackboard.action_timer = maxf(blackboard.action_timer - delta, 0.0)
	blackboard.patrol_wait_remaining = maxf(blackboard.patrol_wait_remaining - delta, 0.0)
	blackboard.search_wait_remaining = maxf(blackboard.search_wait_remaining - delta, 0.0)
	blackboard.perception_timer = maxf(blackboard.perception_timer - delta, 0.0)
	if blackboard.has_suspicious_event:
		blackboard.suspicious_timer = maxf(blackboard.suspicious_timer - delta, 0.0)
		if blackboard.suspicious_timer <= 0.0:
			blackboard.has_suspicious_event = false
	if navigator != null:
		navigator.advance(delta)
	_update_lod()
	_update_lose_sight_timer(delta)


func _update_lod() -> void:
	_lod_active = false
	if config != null and config.lod_enabled and is_instance_valid(host.player):
		var distance: float = host.global_position.distance_to(host.player.global_position)
		_lod_active = distance > config.lod_distance_tiles * TILE_SIZE
	# LOD 同时降低感知、决策、路径刷新与动画更新频率。
	if navigator != null:
		navigator.lod_scale = config.lod_interval_scale if (_lod_active and config != null) else 1.0


func _update_lose_sight_timer(delta: float) -> void:
	var state: EnemyState.State = blackboard.state
	if state != EnemyState.State.CHASE and state != EnemyState.State.ATTACK:
		return
	if blackboard.can_see_target:
		blackboard.lose_sight_elapsed = 0.0
		return
	if blackboard.lose_sight_elapsed <= 0.0:
		blackboard.lose_sight_position = host.global_position
	blackboard.lose_sight_elapsed += delta


func _effective_update_interval() -> float:
	return config.update_interval * (config.lod_interval_scale if _lod_active else 1.0)


func _effective_perception_interval() -> float:
	return config.perception_interval * (config.lod_interval_scale if _lod_active else 1.0)


func _decide() -> void:
	if not is_instance_valid(host.player) or host.player.health <= 0:
		if blackboard.state != EnemyState.State.PATROL:
			_lose_target()
		return
	_refresh_perception()
	match blackboard.state:
		EnemyState.State.PATROL:
			_decide_patrol()
		EnemyState.State.CHASE:
			_decide_chase()
		EnemyState.State.ATTACK:
			_decide_attack()
		EnemyState.State.SEARCH:
			_decide_search()


## 感知按 perception_interval 分帧，并交给共享 PerceptionManager 做全局限流。
func _refresh_perception() -> void:
	if blackboard.perception_timer > 0.0:
		return
	blackboard.perception_timer = _effective_perception_interval()
	var manager: Node = host.shared_service(&"PerceptionManager")
	if manager != null and manager.has_method("request_evaluation"):
		manager.call("request_evaluation", host)


func _act(delta: float) -> void:
	match blackboard.state:
		EnemyState.State.PATROL:
			_act_patrol(delta)
		EnemyState.State.CHASE:
			_act_chase(delta)
		EnemyState.State.ATTACK:
			_act_attack(delta)
		EnemyState.State.SEARCH:
			_act_search(delta)
	if host.velocity.length_squared() > 1.0:
		blackboard.facing = host.velocity.normalized()


func _change_state(new_state: EnemyState.State) -> void:
	if blackboard.state == new_state:
		return
	blackboard.state = new_state
	blackboard.state_elapsed = 0.0
	if attack != null:
		attack.set_attacking(new_state == EnemyState.State.ATTACK)


# --- Patrol -----------------------------------------------------------------

func _decide_patrol() -> void:
	if blackboard.can_see_target:
		_begin_chase()
		return
	if blackboard.has_suspicious_event:
		blackboard.consume_suspicious()
		_begin_search(blackboard.suspicious_position)
		return
	if navigator.has_path() or navigator.has_pending_request():
		return
	if blackboard.patrol_wait_remaining > 0.0:
		return
	# 上一次请求算完却没有可用路径（点不可达 / 与当前格重合）：等待后重选。
	if navigator.consume_failed_request():
		blackboard.patrol_wait_remaining = config.path_failure_retry_delay
		return
	if not _try_request_patrol_point():
		blackboard.patrol_wait_remaining = config.path_failure_retry_delay


## 只负责跟随路径，绝不在这里改写等待计时。
##
## 决策按 update_interval（并乘 LOD 倍率）分帧，而动作每帧都跑；等待计时也是每帧递减。
## 如果在这一层把"当前没有路径"当成寻路失败并重置等待，就会在下一个决策帧到来之前
## 反复重置计时，怪物永远等不到"空闲且等待结束"的决策帧，于是完全不巡逻。
## 路径失败一律交给 _decide_patrol() 通过 navigator.consume_failed_request() 处理。
func _act_patrol(delta: float) -> void:
	if blackboard.patrol_wait_remaining > 0.0:
		navigator.stop()
		_scan(delta)
		return
	match navigator.follow():
		EnemyNavigator.FollowResult.MOVING, EnemyNavigator.FollowResult.WAITING:
			pass
		EnemyNavigator.FollowResult.ARRIVED:
			blackboard.patrol_wait_remaining = config.patrol_wait_time
		EnemyNavigator.FollowResult.NO_PATH:
			pass


## 在 PatrolAnchor 半径内选一个可达点并请求路径；选不到返回 false 让调用方等待。
func _try_request_patrol_point() -> bool:
	var anchor: Vector2 = blackboard.patrol_anchor
	var radius: float = config.patrol_radius_tiles * TILE_SIZE
	if radius <= 0.0:
		return navigator.request_path(WorldGenerator.world_to_tile(anchor), true)
	var current_tile: Vector2i = WorldGenerator.world_to_tile(host.global_position)
	for _attempt: int in config.patrol_point_attempts:
		var candidate: Vector2 = _random_point_around(anchor, radius)
		# 与当前格重合的点会算出空路径，直接换一个候选。
		if WorldGenerator.world_to_tile(candidate) == current_tile:
			continue
		if not host.is_patrol_tile_allowed(WorldGenerator.world_to_tile(candidate)) or not _is_candidate_point(candidate, anchor):
			continue
		return navigator.request_path(WorldGenerator.world_to_tile(candidate), true)
	return false


# --- Chase ------------------------------------------------------------------

func _decide_chase() -> void:
	if blackboard.can_see_target:
		blackboard.lose_sight_elapsed = 0.0
		blackboard.last_known_position = host.player.global_position
		blackboard.has_last_known_position = true
		if _in_attack_range() and attack != null and attack.can_attack(host, host.player):
			_change_state(EnemyState.State.ATTACK)
			return
	elif blackboard.lose_sight_elapsed >= config.lose_sight_grace:
		_lose_target()
		return
	elif config.search_on_lost_sight and blackboard.has_last_known_position:
		_begin_search(blackboard.last_known_position)
		return

	if blackboard.has_last_known_position:
		navigator.request_path(WorldGenerator.world_to_tile(blackboard.last_known_position))


func _act_chase(_delta: float) -> void:
	match navigator.follow():
		EnemyNavigator.FollowResult.MOVING, EnemyNavigator.FollowResult.WAITING:
			pass
		EnemyNavigator.FollowResult.ARRIVED:
			# 到达最后已知位置但还没重新看到玩家：原地等待宽限结束，不回出生点。
			navigator.stop()
		EnemyNavigator.FollowResult.NO_PATH:
			# 路径失败：保持等待，由刷新节流在 path_refresh_interval 后重试。
			pass


# --- Attack -----------------------------------------------------------------

func _decide_attack() -> void:
	if not blackboard.can_see_target:
		if blackboard.lose_sight_elapsed >= config.lose_sight_grace:
			_lose_target()
			return
		if config.search_on_lost_sight and blackboard.has_last_known_position:
			_begin_search(blackboard.last_known_position)
			return
		# 视线被墙挡住但还在宽限内：交回 Chase 绕行到最后已知位置，
		# 不做"隔墙锁定"，也不回到出生点。
		_change_state(EnemyState.State.CHASE)
		return

	blackboard.lose_sight_elapsed = 0.0
	blackboard.last_known_position = host.player.global_position
	blackboard.has_last_known_position = true
	if not _in_attack_range():
		_change_state(EnemyState.State.CHASE)


func _act_attack(_delta: float) -> void:
	navigator.stop()
	if not is_instance_valid(host.player):
		return
	_face_towards(host.player.global_position)
	if attack == null or blackboard.attack_cooldown > 0.0:
		return
	if not attack.can_attack(host, host.player):
		return
	if attack.perform_attack(host, host.player):
		var cooldown: float = attack.attack_cooldown()
		blackboard.attack_cooldown = cooldown if cooldown > 0.0 else config.attack_cooldown
	else:
		blackboard.attack_cooldown = attack.failed_attack_cooldown()


# --- Search -----------------------------------------------------------------

func _decide_search() -> void:
	if blackboard.can_see_target:
		_begin_chase()
		return
	if blackboard.action_timer <= 0.0:
		_finish_search()
		return
	if blackboard.has_suspicious_event:
		blackboard.consume_suspicious()
		_begin_search(blackboard.suspicious_position)
		return
	if blackboard.search_wait_remaining > 0.0:
		return
	if blackboard.search_arrived:
		blackboard.search_arrived = false
		_advance_search_point()
		return
	if navigator.has_path() or navigator.has_pending_request():
		return
	# 该点不可达：稍作停留后换下一个搜索点。
	if navigator.consume_failed_request():
		blackboard.search_wait_remaining = config.search_point_dwell_time
		return
	_advance_search_point()


func _act_search(delta: float) -> void:
	if blackboard.search_wait_remaining > 0.0:
		navigator.stop()
		_scan(delta)
		return
	match navigator.follow():
		EnemyNavigator.FollowResult.MOVING, EnemyNavigator.FollowResult.WAITING:
			pass
		EnemyNavigator.FollowResult.ARRIVED:
			blackboard.search_arrived = true
			blackboard.search_wait_remaining = config.search_point_dwell_time
		EnemyNavigator.FollowResult.NO_PATH:
			# 失败由 _decide_search() 通过 consume_failed_request() 处理。
			pass


func _begin_search(center: Vector2) -> void:
	blackboard.search_center = center
	blackboard.search_points = _pick_search_points(center)
	blackboard.search_index = -1
	blackboard.search_arrived = false
	blackboard.search_wait_remaining = 0.0
	blackboard.action_timer = config.search_duration
	_change_state(EnemyState.State.SEARCH)
	_advance_search_point()


func _advance_search_point() -> void:
	blackboard.search_index += 1
	if blackboard.search_index >= blackboard.search_points.size():
		_finish_search()
		return
	navigator.request_path(
		WorldGenerator.world_to_tile(blackboard.search_points[blackboard.search_index]), true
	)


## 搜索超时或搜索完所有点：以当前位置作为新的巡逻锚点回到 Patrol，不回出生点。
func _finish_search() -> void:
	blackboard.patrol_anchor = host.global_position
	blackboard.clear_target()
	blackboard.clear_search()
	navigator.clear()
	blackboard.patrol_wait_remaining = 0.0
	_change_state(EnemyState.State.PATROL)


func _pick_search_points(center: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var radius: float = config.search_radius_tiles * TILE_SIZE
	var attempts: int = maxi(config.search_point_count * 4, 4)
	for _attempt: int in attempts:
		if points.size() >= config.search_point_count:
			break
		var candidate: Vector2 = _random_point_around(center, radius)
		if not _is_candidate_point(candidate, center):
			continue
		points.append(candidate)
	return points


# --- 共用 -------------------------------------------------------------------

func _begin_chase() -> void:
	if not is_instance_valid(host.player):
		return
	blackboard.consume_suspicious()
	blackboard.clear_search()
	blackboard.lose_sight_elapsed = 0.0
	blackboard.last_known_position = host.player.global_position
	blackboard.has_last_known_position = true
	_change_state(EnemyState.State.CHASE)
	navigator.clear()
	navigator.request_path(WorldGenerator.world_to_tile(blackboard.last_known_position), true)


## 丢失目标：不回家、不回原巡逻点，以当前位置作为新的巡逻锚点。
func _lose_target() -> void:
	blackboard.patrol_anchor = host.global_position
	blackboard.clear_target()
	blackboard.clear_search()
	navigator.clear()
	blackboard.patrol_wait_remaining = 0.0
	_change_state(EnemyState.State.PATROL)


func _in_attack_range() -> bool:
	if not is_instance_valid(host.player):
		return false
	var reach: float = config.attack_range_tiles * TILE_SIZE
	if attack != null and attack.attack_range() > 0.0:
		reach = attack.attack_range()
	return host.global_position.distance_to(host.player.global_position) <= reach


func _face_towards(world_position: Vector2) -> void:
	var direction: Vector2 = host.global_position.direction_to(world_position)
	if direction.is_zero_approx():
		return
	blackboard.facing = direction


## 等待/停留时缓慢环顾，配合视野锥使用。
func _scan(delta: float) -> void:
	if config.patrol_scan_speed_degrees <= 0.0:
		return
	var turn: float = deg_to_rad(config.patrol_scan_speed_degrees) * delta
	blackboard.facing = blackboard.facing.rotated(turn).normalized()


func _random_point_around(origin: Vector2, radius: float) -> Vector2:
	var angle: float = _rng.randf() * TAU
	var distance: float = sqrt(_rng.randf()) * radius
	return origin + Vector2.RIGHT.rotated(angle) * distance


## 候选点必须可通行，且与参照点之间没有地形阻挡（避免选到墙对面）。
func _is_candidate_point(point: Vector2, origin: Vector2) -> bool:
	if not host.is_navigation_tile_allowed(WorldGenerator.world_to_tile(point)):
		return false
	return host.is_terrain_line_clear(origin, point)
