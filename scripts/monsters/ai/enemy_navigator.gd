class_name EnemyNavigator
extends RefCounted

## 统一寻路接口：向共享的 PathRequestScheduler 提交请求，每帧跟随已拿到的路径。
## 路径计算与路径跟随分离，保证多个怪物不会在同一帧一起做 A*。

enum FollowResult {
	MOVING,   ## 正在沿路径移动。
	WAITING,  ## 路径请求还在排队，本帧无事可做。
	ARRIVED,  ## 路径走完。
	NO_PATH,  ## 没有可用路径（还没请求，或请求失败）。
}

const WAYPOINT_TOLERANCE: float = 3.0

var host: BaseMonster = null
var config: EnemyAIConfig = null

var path: Array[Vector2i] = []
var path_index: int = 0
## 每次请求都会自增，用来丢弃过期的异步路径结果。
var generation: int = 0
var pending_generation: int = -1
var pending_target_tile: Vector2i = EnemyPathfinder.INVALID_TILE
var last_target_tile: Vector2i = EnemyPathfinder.INVALID_TILE
var refresh_timer: float = 0.0
## LOD 倍率：远处怪物的路径刷新间隔会被拉长，由 EnemyBrain 每帧写入。
var lod_scale: float = 1.0
## 最近一次请求是否"算完但没有可用路径"（目标不可达，或起点与目标同格）。
## 由决策层消费：决策与动作分帧执行，"当前没有路径"并不等于"寻路失败"。
var request_failed: bool = false


func setup(monster: BaseMonster, ai_config: EnemyAIConfig) -> void:
	host = monster
	config = ai_config
	clear()


func advance(delta: float) -> void:
	refresh_timer = maxf(refresh_timer - delta, 0.0)


func clear() -> void:
	generation += 1
	path = []
	path_index = 0
	pending_generation = -1
	pending_target_tile = EnemyPathfinder.INVALID_TILE
	last_target_tile = EnemyPathfinder.INVALID_TILE
	refresh_timer = 0.0
	request_failed = false


## 取走"上一次请求没有可用路径"的标记；取走后不再重复上报。
func consume_failed_request() -> bool:
	if not request_failed:
		return false
	request_failed = false
	return true


## 两次寻路请求之间的最短间隔；LOD 生效时按倍率拉长。
func _refresh_interval() -> float:
	var base: float = config.path_refresh_interval if config != null else 0.4
	return base * maxf(lod_scale, 1.0)


func has_path() -> bool:
	return path_index < path.size()


func has_pending_request() -> bool:
	return pending_generation >= 0


func is_idle() -> bool:
	return not has_path() and not has_pending_request()


## 请求一条到目标格的路径。force 会忽略刷新节流（选点与状态切换时使用）。
func request_path(target_tile: Vector2i, force: bool = false) -> bool:
	if host == null or host.world_generator == null:
		return false
	if not force:
		if pending_generation >= 0 and target_tile == pending_target_tile:
			return false
		if refresh_timer > 0.0:
			return false
	var scheduler: Node = host.shared_service(&"PathRequestScheduler")
	if scheduler == null or not scheduler.has_method("request_path"):
		return false
	generation += 1
	var request_generation: int = generation
	pending_generation = request_generation
	pending_target_tile = target_tile
	last_target_tile = target_tile
	refresh_timer = _refresh_interval()
	scheduler.call(
		"request_path",
		host,
		WorldGenerator.world_to_tile(host.global_position),
		target_tile,
		Callable(host, "_on_ai_path_ready").bind(request_generation),
		config.path_margin_tiles if config != null else 6,
		host.blocked_physics_tiles()
	)
	return true


## PathRequestScheduler 算完后由宿主怪物转交回来；过期结果会被丢弃。
func apply_path(request_generation: int, result: Array[Vector2i]) -> void:
	if request_generation != pending_generation:
		return
	pending_generation = -1
	pending_target_tile = EnemyPathfinder.INVALID_TILE
	path = []
	path_index = 0
	if result.size() <= 1:
		request_failed = true
		return
	request_failed = false
	path = result
	path_index = 1


func follow() -> FollowResult:
	if host == null or host.world_generator == null:
		return FollowResult.NO_PATH
	if not has_path():
		return FollowResult.WAITING if has_pending_request() else FollowResult.NO_PATH

	while path_index < path.size():
		var waypoint: Vector2 = WorldGenerator.tile_to_world(path[path_index])
		if host.global_position.distance_to(waypoint) > WAYPOINT_TOLERANCE:
			break
		path_index += 1
	if path_index >= path.size():
		clear()
		return FollowResult.ARRIVED

	var next_tile: Vector2i = path[path_index]
	if not host.is_navigation_tile_allowed(next_tile):
		clear()
		return FollowResult.NO_PATH
	if host.has_supply_post and host.get_ai_state() == EnemyState.State.PATROL and not host.brain.is_returning_to_supply_post() and not host.supply_patrol_allows(next_tile):
		clear()
		return FollowResult.NO_PATH

	var next_position: Vector2 = WorldGenerator.tile_to_world(next_tile)
	host.velocity = host.global_position.direction_to(next_position) * host.movement_speed()
	host.move_and_slide()
	if host.get_slide_collision_count() > 0:
		# 撞到物理墙体：下个决策帧立刻重新寻路。
		refresh_timer = 0.0
	host.play_monster_animation(&"Move")
	return FollowResult.MOVING


func stop() -> void:
	if host != null:
		host.stop_navigation()
