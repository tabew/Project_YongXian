class_name GiveMonsterAttack
extends EnemyAttack

## "给"的攻击实现：6~10 格投石，6 格内跳跃近战。
##
## 状态转换、冷却计时与丢失视野处理都由 EnemyBrain 负责，这里只回答"能不能打"和"怎么打"。
## 数值集中在这里，GiveMonster 以常量别名转发，方便旧测试与旧脚本继续引用。

const TILE_SIZE: float = float(WorldGenerator.TILE_SIZE)
const DAMAGE: int = 1
const ATTACK_COOLDOWN: float = 1.0
const FAILED_ATTACK_RETRY: float = 0.3
const RANGED_MIN_RANGE: float = TILE_SIZE * 6.0
const RANGED_MAX_RANGE: float = TILE_SIZE * 10.0
const LEAP_MAX_RANGE: float = TILE_SIZE * 6.0
const LEAP_DURATION: float = 0.42
const LEAP_HEIGHT: float = 24.0
const MELEE_HIT_RANGE: float = TILE_SIZE * 2.0
const STONE_PICKUP_RANGE: float = TILE_SIZE

var host: BaseMonster = null

var _has_intent: bool = false
var _is_leaping: bool = false
var _leap_elapsed: float = 0.0
var _leap_start: Vector2 = Vector2.ZERO
var _leap_target: Vector2 = Vector2.ZERO


func setup(monster: BaseMonster, _ai_config: EnemyAIConfig) -> void:
	host = monster


## 状态机用它判断"进入攻击距离"，与投石最远距离一致。
func attack_range() -> float:
	return RANGED_MAX_RANGE


func attack_cooldown() -> float:
	return ATTACK_COOLDOWN


func failed_attack_cooldown() -> float:
	return FAILED_ATTACK_RETRY


## 是否处于交战/出手意图；GiveMonsterVisual 用它决定眼睛颜色。
func has_intent() -> bool:
	return _has_intent


func is_busy() -> bool:
	return _is_leaping


func leap_elapsed() -> float:
	return _leap_elapsed


func can_attack(monster: BaseMonster, target: Node2D) -> bool:
	if monster == null or target == null or not is_instance_valid(target):
		return false
	var distance: float = monster.global_position.distance_to(target.global_position)
	if distance >= RANGED_MIN_RANGE and distance <= RANGED_MAX_RANGE:
		return _find_stone(monster) != null
	if distance < LEAP_MAX_RANGE:
		return _leap_destination_is_valid(monster, target.global_position)
	return false


func perform_attack(monster: BaseMonster, target: Node2D) -> bool:
	if monster == null or target == null or not is_instance_valid(target):
		return false
	var distance: float = monster.global_position.distance_to(target.global_position)
	if distance >= RANGED_MIN_RANGE and distance <= RANGED_MAX_RANGE:
		return _try_throw_stone(monster, target)
	if distance < LEAP_MAX_RANGE:
		return start_leap(monster, target.global_position)
	return false


## 开始一次跳跃近战。落点位移与伤害由物理逻辑处理，动画由模板播放。
func start_leap(monster: BaseMonster, target_position: Vector2) -> bool:
	if monster == null or not _leap_destination_is_valid(monster, target_position):
		return false
	var direction: Vector2 = monster.global_position.direction_to(target_position)
	monster.play_monster_animation(&"Leap", true)
	_is_leaping = true
	_leap_elapsed = 0.0
	_leap_start = monster.global_position
	_leap_target = target_position - direction * TILE_SIZE
	_set_intent(monster, true)
	return true


func update(monster: BaseMonster, delta: float) -> void:
	if not _is_leaping or monster == null:
		return
	_leap_elapsed += delta
	var progress: float = minf(_leap_elapsed / LEAP_DURATION, 1.0)
	monster.global_position = _leap_start.lerp(_leap_target, progress)
	if progress < 1.0:
		return
	_is_leaping = false
	_leap_elapsed = 0.0
	monster.play_monster_animation(&"Idle")
	if is_instance_valid(monster.player) and (
		monster.global_position.distance_to(monster.player.global_position) <= MELEE_HIT_RANGE
	):
		monster.player.take_damage(DAMAGE)


func set_attacking(value: bool) -> void:
	_set_intent(host, value)


## 受击等打断：跳跃被取消，不能再用旧位移覆盖击退。
func cancel(monster: BaseMonster) -> void:
	_is_leaping = false
	_leap_elapsed = 0.0
	_set_intent(monster, false)


func _leap_destination_is_valid(monster: BaseMonster, target_position: Vector2) -> bool:
	var direction: Vector2 = monster.global_position.direction_to(target_position)
	if direction.is_zero_approx():
		return false
	var destination: Vector2 = target_position - direction * TILE_SIZE
	if not monster.is_navigation_tile_allowed(WorldGenerator.world_to_tile(destination)):
		return false
	# 跳跃是整段直线位移：逐格检查地形，避免擦着墙角飞到墙对面。
	if not monster.is_terrain_segment_clear(monster.global_position, destination):
		return false
	return monster.has_clear_line_to_position(destination)


func _try_throw_stone(monster: BaseMonster, target: Node2D) -> bool:
	var stone: Node2D = _find_stone(monster)
	if stone == null:
		_set_intent(monster, false)
		monster.stop_navigation()
		return false
	monster.play_monster_animation(&"Throw", true)
	var result: Variant = stone.call("throw_at", target, DAMAGE)
	if result is bool and not result:
		_set_intent(monster, false)
		return false
	_set_intent(monster, true)
	return true


func _find_stone(monster: BaseMonster) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = STONE_PICKUP_RANGE + 0.001
	for node: Node in monster.get_tree().get_nodes_in_group("throwable_stones"):
		if not node is Node2D or not node.has_method("throw_at"):
			continue
		var stone := node as Node2D
		if stone.is_queued_for_deletion() or not stone.is_visible_in_tree():
			continue
		var distance: float = monster.global_position.distance_to(stone.global_position)
		if distance > nearest_distance:
			continue
		if stone.has_method("can_be_thrown") and not stone.call("can_be_thrown"):
			continue
		if monster.world_generator != null and not monster.has_clear_line_to_position(stone.global_position):
			continue
		nearest = stone
		nearest_distance = distance
	return nearest


func _set_intent(monster: BaseMonster, value: bool) -> void:
	if _has_intent == value:
		return
	_has_intent = value
	if monster == null:
		return
	var body := monster.get_node_or_null("Visual/Body")
	if body is CanvasItem:
		(body as CanvasItem).queue_redraw()
