class_name HealthComponent
extends Node

signal health_changed(current: float, maximum: float)
signal damaged(hit: CombatHit, actual_damage: float)
## 致命伤害结算后、正式死亡前；阶段型敌人可在这里回满生命。
signal depleted(hit: CombatHit)
signal died(hit: CombatHit)

@export_range(1.0, 100000.0, 1.0) var max_health: float = 100.0
@export_range(0.0, 10000.0, 0.5) var defense: float = 0.0
#buff 修改的受到的伤害倍率，1.0为正常
@export_range(0.0, 10.0, 0.05) var damage_taken: float = 1.0
var current_health: float = 0.0
## 闪避无敌帧与 Boss 阶段切换都使用同一战斗伤害拦截开关。
var invulnerable: bool = false


func _ready() -> void:
	reset()


func is_alive() -> bool:
	return current_health > 0.0


func reset() -> void:
	current_health = maxf(1.0, max_health)
	health_changed.emit(current_health, max_health)


## 回复生命，返回实际回复量。已死亡时不回复。
func heal(amount: float) -> float:
	if amount <= 0.0 or not is_alive():
		return 0.0
	#受到的回复量加成（祝福这类 buff 写回宿主的 healing_received）
	var host: Node = get_parent()

	if host != null and host.has_method("read_stat"):
		amount *= maxf(float(host.call("read_stat", &"healing_received")), 0.0)
	if amount <= 0.0:
		return 0.0
	var before: float = current_health

	current_health = minf(current_health + amount, max_health)
	var healed: float = current_health - before
	if healed > 0.0:
		health_changed.emit(current_health, max_health)
	return healed


## 直接改写当前生命（升级、重生等非战斗路径用），并按需要广播。
func set_current_health(value: float) -> void:
	current_health = clampf(value, 0.0, max_health)
	health_changed.emit(current_health, max_health)


func receive_hit(hit: CombatHit) -> bool:
	if hit == null or invulnerable or not is_alive():
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
		depleted.emit(hit)
		if not is_alive():
			died.emit(hit)
	return true
