class_name CombatHurtbox
extends Area2D

## Multiple hurtboxes on one actor should reference the SAME HealthComponent.
@export var health: HealthComponent
@export var team: int = 2


func _ready() -> void:
	monitoring = false
	if health == null:
		push_warning("CombatHurtbox requires a HealthComponent: %s" % get_path())


func can_receive_hit(source: Node2D, source_team: int) -> bool:
	if not is_instance_valid(health) or not health.is_alive() or team == source_team:
		return false
	return source != health.get_parent() and not source.is_ancestor_of(health)


func receiver_id() -> int:
	return health.get_instance_id()


func receive_hit(hit: CombatHit) -> bool:
	return is_instance_valid(health) and health.receive_hit(hit)
