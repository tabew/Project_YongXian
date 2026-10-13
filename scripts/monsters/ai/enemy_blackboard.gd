class_name EnemyBlackboard
extends RefCounted

## 每个怪物一份的黑板。状态机只读写这里，怪物之间不共享任何可变状态。

## 当前状态与停留时间。
var state: EnemyState.State = EnemyState.State.PATROL
var state_elapsed: float = 0.0

## 已确认的玩家目标；丢失视野并回到 Patrol 时会被清除。
var target: Node2D = null
var target_distance: float = 0.0
var can_see_target: bool = false
var last_known_position: Vector2 = Vector2.ZERO
var has_last_known_position: bool = false
## 丢失视野瞬间的位置，仅用于调试与测试断言。
var lose_sight_position: Vector2 = Vector2.ZERO
var lose_sight_elapsed: float = 0.0

## 巡逻锚点：出生点/配置点，或丢失目标时怪物所在的位置。
## 只有这两种情况会写入它，永远不会回到旧锚点或出生点。
var patrol_anchor: Vector2 = Vector2.ZERO
var patrol_wait_remaining: float = 0.0

## 搜索中心与搜索点。
var search_center: Vector2 = Vector2.ZERO
var search_points: Array[Vector2] = []
var search_index: int = -1
var search_arrived: bool = false
var search_wait_remaining: float = 0.0

## 可疑信息（噪音 / 队友警报 / 被攻击但没看到玩家）。
var suspicious_position: Vector2 = Vector2.ZERO
var has_suspicious_event: bool = false
var suspicious_timer: float = 0.0

## 计时器。
var attack_cooldown: float = 0.0
var perception_timer: float = 0.0
var action_timer: float = 0.0

## 朝向，用于视野锥与环顾。
var facing: Vector2 = Vector2.DOWN


func clear_target() -> void:
	target = null
	has_last_known_position = false
	lose_sight_elapsed = 0.0


func push_suspicious(position: Vector2, lifetime: float) -> void:
	suspicious_position = position
	has_suspicious_event = true
	suspicious_timer = lifetime


func consume_suspicious() -> bool:
	if not has_suspicious_event:
		return false
	has_suspicious_event = false
	suspicious_timer = 0.0
	return true


func clear_search() -> void:
	search_points = []
	search_index = -1
	search_arrived = false
	search_wait_remaining = 0.0
