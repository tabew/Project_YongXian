class_name CrocodileBiteAttack
extends EnemyAttack

const DAMAGE: int = 20
const BITE_RANGE: float = float(WorldGenerator.TILE_SIZE) * 1.5
const WINDUP: float = 0.18
const DURATION: float = 0.40
var _elapsed: float = 0.0
var _busy: bool = false
var _resolved: bool = false
var _target: Node2D = null
var _cooldown: float = 1.0

func setup(_host: BaseMonster, config: EnemyAIConfig) -> void:
	_cooldown = config.attack_cooldown

func attack_range() -> float:
	return BITE_RANGE

func attack_cooldown() -> float:
	return _cooldown

func can_attack(host: BaseMonster, target: Node2D) -> bool:
	if _busy or not is_instance_valid(target) or host == null:
		return false
	return host.global_position.distance_to(target.global_position) <= BITE_RANGE and host.has_clear_line_to_position(target.global_position, target as CollisionObject2D)

func perform_attack(host: BaseMonster, target: Node2D) -> bool:
	if not can_attack(host, target):
		return false
	_target = target
	_elapsed = 0.0
	_busy = true
	_resolved = false
	host.stop_navigation()
	host.play_monster_animation(&"Attack", true)
	return true

func is_busy() -> bool:
	return _busy

func update(host: BaseMonster, delta: float) -> void:
	if not _busy:
		return
	_elapsed += delta
	if not _resolved and _elapsed >= WINDUP:
		_resolved = true
		if is_instance_valid(_target) and _target.has_method("take_damage") and host.global_position.distance_to(_target.global_position) <= BITE_RANGE and host.has_clear_line_to_position(_target.global_position, _target as CollisionObject2D):
			_target.call("take_damage", host.outgoing_damage(DAMAGE), host)
	if _elapsed >= DURATION:
		_busy = false
		_target = null
		host.play_monster_animation(&"Idle")

func cancel(host: BaseMonster) -> void:
	_busy = false
	_target = null
	_resolved = true
	if host is CrocodileMonster:
		host.jaw_open = 0.0
