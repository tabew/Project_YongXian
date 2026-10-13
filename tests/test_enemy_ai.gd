extends Node2D

## 通用四状态 AI 的回归测试：Patrol / Chase / Attack / Search 之间的转换，
## 以及"丢失目标后以当前位置作为新的巡逻锚点、绝不回出生点"的硬性规则。

class FlatTerrain extends WorldGenerator:
	func sample_biome(_tile: Vector2i) -> int:
		return Biome.Kind.TROPICAL_RAINFOREST

	func is_walkable(_tile: Vector2i) -> bool:
		return true


const PLAYER_SCENE: PackedScene = preload("res://scenes/game/player.tscn")
const MONSTER_SCENE: PackedScene = preload("res://scenes/monsters/give_monster.tscn")
const TILE: float = float(WorldGenerator.TILE_SIZE)

var _terrain := FlatTerrain.new(20261013)
var _player: PlayerCharacter = null
var _passed: bool = true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_player = PLAYER_SCENE.instantiate() as PlayerCharacter
	get_tree().root.add_child(_player)
	await get_tree().process_frame
	_player.spawn_on(_terrain, WorldGenerator.tile_to_world(Vector2i(0, 40)))

	await _test_state_flow()
	await _test_search_flow()
	await _test_monster_isolation()
	await _test_anchor_marker()
	await _test_search_on_lost_sight()
	await _test_damage_without_sight()
	await _test_lod_and_seed()
	await _test_shared_service_budget()
	await _test_default_patrol_moves()
	await _test_default_search_moves()
	await _test_patrol_on_generated_terrain()

	print("ENEMY_AI_TEST_RESULT=", _passed)
	if _passed:
		print("ENEMY_AI_TESTS_PASSED")
	get_tree().quit(0 if _passed else 1)


## Patrol -> Chase -> Attack -> Chase -> Patrol(锚点改写) 的完整链路。
func _test_state_flow() -> void:
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 40))
	var monster: GiveMonster = _spawn_monster(WorldGenerator.tile_to_world(Vector2i(0, 0)))
	var spawn_position: Vector2 = monster.global_position
	var board: EnemyBlackboard = monster.get_blackboard()
	var config: EnemyAIConfig = monster.get_ai_config()
	# 视野比攻击距离更远，才能验证"离开攻击距离但仍然可见"。
	config.vision_distance_tiles = 16.0

	await _await_frames(4)
	_check(monster.get_ai_state() == EnemyState.State.PATROL, "starts_in_patrol")
	_check(not monster.has_player_aggro(), "unseen_player_does_not_start_pursuit")
	_check(board.patrol_anchor.is_equal_approx(spawn_position), "patrol_anchor_starts_at_spawn")

	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 8))
	await _await_frames(3)
	_check(monster.get_ai_state() == EnemyState.State.CHASE, "sight_switches_patrol_to_chase")
	_check(board.can_see_target, "chase_has_confirmed_sight")

	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 4))
	await _await_frames(3)
	_check(monster.get_ai_state() == EnemyState.State.ATTACK, "attack_range_switches_chase_to_attack")
	_check(monster.get_attack().has_intent(), "attack_state_marks_intent")

	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 13))
	await _await_frames(3)
	_check(monster.get_ai_state() == EnemyState.State.CHASE, "leaving_range_returns_to_chase")

	# 丢失视野超过宽限：以当前位置为锚点回到 Patrol，而不是回出生点。
	config.lose_sight_grace = 0.2
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 40))
	var anchor := Vector2.ZERO
	var transition_position := Vector2.ZERO
	for _frame: int in 200:
		await get_tree().physics_frame
		if monster.get_ai_state() == EnemyState.State.PATROL:
			anchor = board.patrol_anchor
			transition_position = monster.global_position
			break
	_check(not anchor.is_zero_approx(), "losing_sight_returns_to_patrol")
	_check(anchor.is_equal_approx(transition_position), "anchor_is_position_when_sight_was_lost")
	_check(anchor.distance_to(spawn_position) > TILE, "anchor_is_not_the_spawn_point")
	_check(not monster.has_player_aggro() and board.target == null, "target_cleared_after_losing_sight")
	_check(not board.has_last_known_position, "last_known_position_cleared")

	# 之后围绕新锚点巡逻，仍然不会走回出生点。
	config.patrol_radius_tiles = 1.5
	config.patrol_wait_time = 0.05
	var closest_to_spawn: float = anchor.distance_to(spawn_position)
	var farthest_from_anchor: float = 0.0
	for _frame: int in 150:
		await get_tree().physics_frame
		closest_to_spawn = minf(closest_to_spawn, monster.global_position.distance_to(spawn_position))
		farthest_from_anchor = maxf(farthest_from_anchor, monster.global_position.distance_to(anchor))
	_check(closest_to_spawn > TILE, "patrol_never_walks_back_to_spawn")
	_check(farthest_from_anchor < TILE * 3.0, "patrol_stays_around_the_new_anchor")
	_remove(monster)


## 噪音/警报 -> Search -> 超时回到 Patrol(锚点改写)；搜索中看到玩家 -> Chase。
func _test_search_flow() -> void:
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 40))
	var monster: GiveMonster = _spawn_monster(WorldGenerator.tile_to_world(Vector2i(10, 10)))
	var spawn_position: Vector2 = monster.global_position
	var board: EnemyBlackboard = monster.get_blackboard()
	var config: EnemyAIConfig = monster.get_ai_config()
	config.search_duration = 0.25
	config.search_radius_tiles = 0.5
	config.search_point_count = 2
	config.search_point_dwell_time = 0.05

	await _await_frames(3)
	_check(monster.get_ai_state() == EnemyState.State.PATROL, "search_flow_starts_in_patrol")

	# 噪音与警报走同一条通道：EventBus -> PerceptionManager -> 怪物黑板。
	var noise_position: Vector2 = monster.global_position + Vector2(TILE * 4.0, 0.0)
	EventBus.noise_reported.emit(noise_position, TILE * 3.0, null)
	await _await_frames(2)
	_check(monster.get_ai_state() == EnemyState.State.SEARCH, "noise_switches_patrol_to_search")
	_check(board.search_center.is_equal_approx(noise_position), "search_center_follows_the_noise")

	var anchor := Vector2.ZERO
	var transition_position := Vector2.ZERO
	for _frame: int in 200:
		await get_tree().physics_frame
		if monster.get_ai_state() == EnemyState.State.PATROL:
			anchor = board.patrol_anchor
			transition_position = monster.global_position
			break
	_check(not anchor.is_zero_approx(), "search_timeout_returns_to_patrol")
	_check(anchor.is_equal_approx(transition_position), "search_anchor_is_current_position")
	_check(anchor.distance_to(spawn_position) > TILE * 1.5, "search_anchor_is_not_the_spawn_point")

	EventBus.alert_raised.emit(monster.global_position + Vector2(TILE, 0.0), TILE * 4.0, null)
	await _await_frames(2)
	_check(monster.get_ai_state() == EnemyState.State.SEARCH, "alert_switches_to_search")
	config.vision_distance_tiles = 16.0
	_player.global_position = monster.global_position + Vector2(TILE * 12.0, 0.0)
	await _await_frames(3)
	_check(monster.get_ai_state() == EnemyState.State.CHASE, "sight_during_search_switches_to_chase")
	_remove(monster)


## 多怪物：各自的状态、黑板、锚点与冷却互不影响。
func _test_monster_isolation() -> void:
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 40))
	var first: GiveMonster = _spawn_monster(WorldGenerator.tile_to_world(Vector2i(0, 0)))
	var second: GiveMonster = _spawn_monster(WorldGenerator.tile_to_world(Vector2i(20, 20)))
	_check(first.get_ai_config() != second.get_ai_config(), "monsters_own_separate_configs")
	_check(first.get_blackboard() != second.get_blackboard(), "monsters_own_separate_blackboards")
	first.set_attack_cooldown(5.0)
	second.set_attack_cooldown(2.0)
	_check(first.get_attack_cooldown() > 4.0 and second.get_attack_cooldown() < 3.0, "attack_cooldowns_are_independent")

	var first_anchor: Vector2 = first.get_blackboard().patrol_anchor
	var second_anchor: Vector2 = second.get_blackboard().patrol_anchor

	first.get_ai_config().vision_distance_tiles = 16.0
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 12))
	await _await_frames(4)
	_check(first.get_ai_state() == EnemyState.State.CHASE, "only_the_seeing_monster_chases")
	_check(second.get_ai_state() == EnemyState.State.PATROL, "the_other_monster_keeps_patrolling")
	_check(first.get_blackboard().patrol_anchor.is_equal_approx(first_anchor), "chasing_keeps_its_own_anchor")
	_check(second.get_blackboard().patrol_anchor.is_equal_approx(second_anchor), "other_anchor_untouched")
	_remove(first)
	_remove(second)


## 初始 PatrolAnchor 可以来自场景里的 PatrolAnchor 节点（配置点 / 房间中心）。
func _test_anchor_marker() -> void:
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 40))
	var marker_position: Vector2 = WorldGenerator.tile_to_world(Vector2i(6, 6))
	var monster := MONSTER_SCENE.instantiate() as GiveMonster
	get_tree().root.add_child(monster)
	# 与真实场景一致：先落位，再挂 PatrolAnchor 子节点，最后 configure()。
	monster.global_position = WorldGenerator.tile_to_world(Vector2i(0, 0))
	var marker := Node2D.new()
	marker.name = "PatrolAnchor"
	monster.add_child(marker)
	marker.global_position = marker_position
	monster.configure(_player, _terrain, Vector2i.ZERO)
	await _await_frames(2)
	_check(
		monster.get_blackboard().patrol_anchor.is_equal_approx(marker_position),
		"anchor_comes_from_marker_node"
	)
	_check(
		not monster.get_blackboard().patrol_anchor.is_equal_approx(monster.global_position),
		"marker_anchor_overrides_spawn_point"
	)
	_remove(monster)


## 配置开启 Chase -> Search -> Patrol 后，最终仍然以当前位置为锚点，不回出生点。
func _test_search_on_lost_sight() -> void:
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 40))
	var monster: GiveMonster = _spawn_monster(WorldGenerator.tile_to_world(Vector2i(0, 0)))
	var spawn_position: Vector2 = monster.global_position
	var board: EnemyBlackboard = monster.get_blackboard()
	var config: EnemyAIConfig = monster.get_ai_config()
	config.search_on_lost_sight = true
	config.vision_distance_tiles = 16.0
	config.search_duration = 0.4
	config.search_radius_tiles = 0.5
	config.search_point_count = 1
	config.search_point_dwell_time = 0.05

	await _await_frames(3)
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 8))
	await _await_frames(3)
	_check(monster.get_ai_state() == EnemyState.State.CHASE, "search_on_lost_sight_reaches_chase")

	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 40))
	var saw_search: bool = false
	var returned_to_patrol: bool = false
	for _frame: int in 400:
		await get_tree().physics_frame
		if monster.get_ai_state() == EnemyState.State.SEARCH:
			saw_search = true
		elif saw_search and monster.get_ai_state() == EnemyState.State.PATROL:
			returned_to_patrol = true
			break
	_check(saw_search, "losing_sight_with_search_enabled_enters_search")
	_check(returned_to_patrol, "search_on_lost_sight_ends_in_patrol")
	_check(board.patrol_anchor.distance_to(spawn_position) > TILE, "search_on_lost_sight_never_returns_home")
	_remove(monster)


## 被玩家攻击但看不到玩家（超出视野距离）-> Search，而不是回家。
func _test_damage_without_sight() -> void:
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 40))
	var monster: GiveMonster = _spawn_monster(WorldGenerator.tile_to_world(Vector2i(0, 0)))
	var config: EnemyAIConfig = monster.get_ai_config()
	config.vision_distance_tiles = 4.0
	config.search_duration = 0.5
	await _await_frames(3)
	_check(monster.get_ai_state() == EnemyState.State.PATROL, "damage_test_starts_in_patrol")

	# 玩家在同一直线上但远超视野：怪物被打中却看不到来源。
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 20))
	await _await_frames(2)
	var hit := CombatHit.new()
	hit.source = _player
	hit.damage = 1.0
	hit.position = _player.global_position
	(monster.get_node("Health") as HealthComponent).receive_hit(hit)
	await _await_frames(14)
	_check(monster.get_ai_state() == EnemyState.State.SEARCH, "damage_without_sight_switches_to_search")
	_remove(monster)


## LOD：远处怪物的决策 / 感知 / 路径刷新 / 动画都会降频；随机种子与世界种子和格子绑定。
func _test_lod_and_seed() -> void:
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 40))
	var monster: GiveMonster = _spawn_monster(WorldGenerator.tile_to_world(Vector2i(0, 0)))
	var config: EnemyAIConfig = monster.get_ai_config()
	config.lod_enabled = true
	config.lod_distance_tiles = 10.0
	config.lod_interval_scale = 4.0
	config.vision_distance_tiles = 6.0

	_player.global_position = monster.global_position + Vector2(TILE * 30.0, 0.0)
	await _await_frames(3)
	_check(monster.brain.is_lod_active(), "far_monster_uses_lod")
	_check(is_equal_approx(monster.get_navigator().lod_scale, 4.0), "lod_scales_path_refresh_interval")

	_player.global_position = monster.global_position + Vector2(TILE * 2.0, 0.0)
	await _await_frames(3)
	_check(not monster.brain.is_lod_active(), "near_monster_skips_lod")
	_check(is_equal_approx(monster.get_navigator().lod_scale, 1.0), "near_monster_keeps_normal_refresh")

	# 同世界种子 + 同格子 + 同 ai_id 的两只怪物得到同一随机序列；换世界种子就会改变。
	var twin := MONSTER_SCENE.instantiate() as GiveMonster
	get_tree().root.add_child(twin)
	twin.global_position = monster.global_position
	twin.configure(_player, _terrain, Vector2i.ZERO)
	_check(monster._ai_seed() == twin._ai_seed(), "same_world_tile_and_id_share_the_seed")
	var other_world := FlatTerrain.new(_terrain.world_seed + 1)
	twin.configure(_player, other_world, Vector2i.ZERO)
	_check(monster._ai_seed() != twin._ai_seed(), "different_world_seed_changes_the_seed")
	_remove(twin)
	_remove(monster)


## 共享服务：感知与寻路调度都是自动加载单例，多怪物共用并按帧预算限流。
func _test_shared_service_budget() -> void:
	var manager: Node = get_node_or_null("/root/PerceptionManager")
	var scheduler: Node = get_node_or_null("/root/PathRequestScheduler")
	_check(manager != null and scheduler != null, "shared_services_are_autoloaded")
	_check(manager.has_method("request_evaluation"), "perception_manager_accepts_evaluations")
	_check(scheduler.has_method("request_path"), "path_scheduler_accepts_requests")

	_player.global_position = WorldGenerator.tile_to_world(Vector2i(0, 40))
	var monster: GiveMonster = _spawn_monster(WorldGenerator.tile_to_world(Vector2i(0, 0)))
	var config: EnemyAIConfig = monster.get_ai_config()
	config.patrol_radius_tiles = 3.0
	config.patrol_start_delay = 0.0
	monster.get_blackboard().patrol_wait_remaining = 0.0

	# 预算为 0：请求只能排队，本帧不会真的跑 A*。
	var original_budget: int = scheduler.max_requests_per_frame
	scheduler.max_requests_per_frame = 0
	await _await_frames(20)
	var queued_instead_of_computed: bool = not monster.get_navigator().has_path()

	# 预算恢复：排队中的请求被处理，怪物重新开始巡逻。
	scheduler.max_requests_per_frame = original_budget
	var patrol_start: Vector2 = monster.global_position
	var resumed_patrol: bool = false
	for _frame: int in 200:
		await get_tree().physics_frame
		if monster.global_position.distance_to(patrol_start) > TILE:
			resumed_patrol = true
			break
	_check(queued_instead_of_computed, "path_requests_queue_when_budget_is_exhausted")
	_check(resumed_patrol, "queued_path_request_is_delivered_after_budget_recovers")
	_remove(monster)


## 默认巡逻机制：用真实配置（update_interval = 0.1、开启 LOD）也必须真的走动。
##
## 等待计时每帧递减，而决策按 update_interval（再乘 LOD 倍率）分帧。如果动作层把
## "当前没有路径"当成寻路失败并重置等待，就会在下一个决策帧到来之前反复重置，
## 怪物永远等不到"空闲且等待结束"的决策帧，于是完全不巡逻。这个用例守住该回归。
func _test_default_patrol_moves() -> void:
	var monster: GiveMonster = _spawn_real_monster(WorldGenerator.tile_to_world(Vector2i(0, 0)))
	var config: EnemyAIConfig = monster.get_ai_config()
	var anchor: Vector2 = monster.get_blackboard().patrol_anchor
	# 玩家远离：触发 LOD，决策与路径刷新都被拉长，正是最容易卡住的场景。
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(60, 60))

	var travelled: float = 0.0
	var previous: Vector2 = monster.global_position
	var farthest: float = 0.0
	for _frame: int in 900:
		await get_tree().physics_frame
		travelled += monster.global_position.distance_to(previous)
		previous = monster.global_position
		farthest = maxf(farthest, monster.global_position.distance_to(anchor))

	_check(monster.brain.is_lod_active(), "default_patrol_runs_under_lod")
	_check(monster.get_ai_state() == EnemyState.State.PATROL, "default_patrol_stays_in_patrol")
	_check(travelled > TILE * 6.0, "default_patrol_actually_moves")
	_check(farthest <= (config.patrol_radius_tiles + 2.0) * TILE, "default_patrol_stays_near_anchor")
	_remove(monster)


## 默认搜索：真实配置下收到噪音必须真的移动到搜索点，并在超时后回到 Patrol。
func _test_default_search_moves() -> void:
	var monster: GiveMonster = _spawn_real_monster(WorldGenerator.tile_to_world(Vector2i(0, 0)))
	var spawn_position: Vector2 = monster.global_position
	_player.global_position = WorldGenerator.tile_to_world(Vector2i(60, 60))
	await _await_frames(3)

	EventBus.noise_reported.emit(
		monster.global_position + Vector2(TILE * 3.0, 0.0), TILE * 6.0, null
	)
	var entered_search: bool = false
	for _frame: int in 120:
		await get_tree().physics_frame
		if monster.get_ai_state() == EnemyState.State.SEARCH:
			entered_search = true
			break
	_check(entered_search, "default_search_enters_search")

	var travelled: float = 0.0
	var previous: Vector2 = monster.global_position
	var returned: bool = false
	var farthest_index: int = -1
	for _frame: int in 900:
		await get_tree().physics_frame
		travelled += monster.global_position.distance_to(previous)
		previous = monster.global_position
		farthest_index = maxi(farthest_index, monster.get_blackboard().search_index)
		if monster.get_ai_state() == EnemyState.State.PATROL:
			returned = true
			break
	_check(travelled > TILE * 4.0, "default_search_actually_moves")
	# 只走到第一个搜索点还不够：必须能推进到后续点，才算没有被"等待计时"卡住。
	_check(farthest_index >= 1, "default_search_advances_through_points")
	_check(returned, "default_search_returns_to_patrol")
	_check(
		monster.get_blackboard().patrol_anchor.distance_to(spawn_position) > TILE,
		"default_search_never_returns_home"
	)
	_remove(monster)


## 真实生成地形下的默认巡逻：选点要避开障碍、寻路要真的能走起来。
func _test_patrol_on_generated_terrain() -> void:
	var terrain := WorldGenerator.new(20261013)
	var spawn_tile: Vector2i = _find_walkable_tile(terrain, Vector2i(0, 0))
	_check(terrain.is_walkable(spawn_tile), "generated_terrain_has_a_walkable_spawn")
	_player.spawn_on(terrain, Vector2(60000.0, 60000.0))

	var monster := MONSTER_SCENE.instantiate() as GiveMonster
	get_tree().root.add_child(monster)
	monster.global_position = WorldGenerator.tile_to_world(spawn_tile)
	monster.configure(_player, terrain, WorldGenerator.tile_to_chunk(spawn_tile))

	var travelled: float = 0.0
	var previous: Vector2 = monster.global_position
	var blocked_frames: int = 0
	for _frame: int in 900:
		await get_tree().physics_frame
		travelled += monster.global_position.distance_to(previous)
		previous = monster.global_position
		if not terrain.is_walkable(WorldGenerator.world_to_tile(monster.global_position)):
			blocked_frames += 1
	_check(travelled > TILE * 4.0, "generated_terrain_patrol_actually_moves")
	_check(blocked_frames == 0, "generated_terrain_patrol_never_stands_on_blocked_ground")
	_check(monster.get_ai_state() == EnemyState.State.PATROL, "generated_terrain_patrol_stays_in_patrol")
	_remove(monster)
	# 还原后续用例使用的平坦地形。
	_player.spawn_on(_terrain, WorldGenerator.tile_to_world(Vector2i(0, 40)))


## 从 origin 向外找第一个可通行格。
func _find_walkable_tile(terrain: WorldGenerator, origin: Vector2i) -> Vector2i:
	for radius: int in 40:
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				var tile: Vector2i = origin + Vector2i(dx, dy)
				if terrain.is_walkable(tile):
					return tile
	return origin


## 使用真实配置生成怪物：不覆盖任何间隔或半径，用来验证默认行为。
func _spawn_real_monster(at: Vector2) -> GiveMonster:
	var monster := MONSTER_SCENE.instantiate() as GiveMonster
	get_tree().root.add_child(monster)
	monster.global_position = at
	monster.configure(_player, _terrain, Vector2i.ZERO)
	return monster


## 每个怪物一个实例：逐帧决策、原地待命，方便断言状态与锚点。
func _spawn_monster(at: Vector2) -> GiveMonster:
	var monster := MONSTER_SCENE.instantiate() as GiveMonster
	get_tree().root.add_child(monster)
	monster.global_position = at
	monster.navigation_speed = 240.0
	monster.configure(_player, _terrain, Vector2i.ZERO)
	# 冷却拉长，只验证状态转换，不让"给"真的打到玩家。
	monster.set_attack_cooldown(999.0)
	var config: EnemyAIConfig = monster.get_ai_config()
	config.update_interval = 0.0
	config.perception_interval = 0.0
	config.lod_enabled = false
	config.patrol_radius_tiles = 0.0
	config.patrol_start_delay = 999.0
	config.path_failure_retry_delay = 0.05
	return monster


func _await_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	print("ENEMY_AI_CHECK ", description, "=", condition)
	if not condition:
		_passed = false
		push_error(description)


func _remove(node: Variant) -> void:
	if is_instance_valid(node):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()