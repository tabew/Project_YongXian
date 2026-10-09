class_name HealthComponent
extends Node

signal health_changed(current: float, maximum: float)
signal damaged(hit: CombatHit, actual_damage: float)
signal died(hit: CombatHit)

@export_range(1.0, 100000.0, 1.0) var max_health: float = 100.0
@export_range(0.0, 10000.0, 0.5) var defense: float = 0.0

var current_health: float = 0.0


func _ready() -> void:
	reset()


func is_alive() -> bool:
	return current_health > 0.0


func reset() -> void:
	current_health = maxf(1.0, max_health)
	health_changed.emit(current_health, max_health)


func receive_hit(hit: CombatHit) -> bool:
	if hit == null or not is_alive():
		return false
	var amount: float = minf(current_health, maxf(0.0, hit.damage - defense))
	if amount <= 0.0:
		return false
	current_health -= amount
	health_changed.emit(current_health, max_health)
	damaged.emit(hit, amount)
	if not is_alive():
		died.emit(hit)
	return true
