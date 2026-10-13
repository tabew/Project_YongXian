class_name EnemyPerception
extends RefCounted

## 统一感知接口：判断能否看到玩家，并接收可疑信息。
##
## 默认实现复用宿主怪物已有的 TargetRayCast + 程序化地形采样（BaseMonster 的
## has_clear_line_to_position），不引入新的检测方式；PerceptionManager 负责按帧
## 预算调度调用时机，避免每帧所有怪物都做全量检测。

const TILE_SIZE: float = float(WorldGenerator.TILE_SIZE)

var host: BaseMonster = null
var config: EnemyAIConfig = null
var blackboard: EnemyBlackboard = null


func setup(monster: BaseMonster, ai_config: EnemyAIConfig, board: EnemyBlackboard) -> void:
	host = monster
	config = ai_config
	blackboard = board


func vision_distance() -> float:
	return config.vision_distance_tiles * TILE_SIZE if config != null else 0.0


func hearing_radius() -> float:
	return config.hearing_radius_tiles * TILE_SIZE if config != null else 0.0


## CanSeePlayer：视野距离 + 视野锥 + 无遮挡视线。
func can_see(target: Node2D) -> bool:
	if host == null or target == null or not is_instance_valid(target):
		return false
	var to_target: Vector2 = target.global_position - host.global_position
	if to_target.length() > vision_distance():
		return false
	if not _inside_vision_cone(to_target):
		return false
	return host.has_clear_line_to_position(target.global_position, target)


func _inside_vision_cone(to_target: Vector2) -> bool:
	if config == null or config.vision_angle_degrees >= 360.0:
		return true
	if blackboard == null or blackboard.facing.is_zero_approx():
		return true
	var half_angle: float = deg_to_rad(config.vision_angle_degrees * 0.5)
	return absf(blackboard.facing.angle_to(to_target)) <= half_angle


## 可疑信息统一入口：噪音、队友警报、被攻击但没看到玩家都走这里。
func report_suspicious(position: Vector2) -> void:
	if blackboard == null:
		return
	var lifetime: float = config.suspicious_event_lifetime if config != null else 5.0
	blackboard.push_suspicious(position, lifetime)
