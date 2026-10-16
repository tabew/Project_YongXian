class_name HealthComponent
extends Node

signal health_changed(current: float, maximum: float)
signal damaged(hit: CombatHit, actual_damage: float)
signal died(hit: CombatHit)

@export_range(1.0, 100000.0, 1.0) var max_health: float = 100.0
@export_range(0.0, 10000.0, 0.5) var defense: float = 0.0
#buff 修改的受到的伤害倍率，1.0为正常
@export_range(0.0, 10.0, 0.05) var damage_taken: float = 1.0

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
	#先过 buff 的受伤倍率，再减防御
	var mitigated: float = maxf(hit.damage * damage_taken - defense, 0.0)
	#伤害吸收效果，各类增减免伤正常结算完，再把最终伤害反转成回复
	if Buffs.is_absorbing(get_parent()):
		Buffs.heal_entity(get_parent(), mitigated)
		return false

	var amount: float = minf(current_health, mitigated)

	if amount <= 0.0:
		return false
	current_health -= amount
	health_changed.emit(current_health, max_health)
	damaged.emit(hit, amount)
	#吸血效果
	Buffs.apply_lifesteal(hit.source, amount)

	if not is_alive():
		died.emit(hit)
	return true
