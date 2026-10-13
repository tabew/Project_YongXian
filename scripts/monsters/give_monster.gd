class_name GiveMonster
extends BaseMonster

## 临时名"给"：在森林、针叶林、热带雨林刷新，可跨群系活动的猿猴型怪物。
##
## AI 全部交给通用四状态状态机（scripts/monsters/ai/），这里只保留血量、死亡流程，
## 以及自己的攻击实现（6~10 格投石、6 格内跳跃近战）。

signal health_changed(current: int, maximum: int)
signal defeated

## 仇恨/视野距离，与 resources/monsters/give_ai_config.tres 的 vision_distance_tiles 一致。
const AGGRO_RANGE: float = float(WorldGenerator.TILE_SIZE) * 10.0
const ATTACK_COOLDOWN: float = GiveMonsterAttack.ATTACK_COOLDOWN
const RANGED_MIN_RANGE: float = GiveMonsterAttack.RANGED_MIN_RANGE
const RANGED_MAX_RANGE: float = GiveMonsterAttack.RANGED_MAX_RANGE
const LEAP_MAX_RANGE: float = GiveMonsterAttack.LEAP_MAX_RANGE
const LEAP_HEIGHT: float = GiveMonsterAttack.LEAP_HEIGHT
const MAX_HEALTH: int = 100

var health: int = MAX_HEALTH

var _is_dead: bool = false


@onready var combat_health: HealthComponent = $Health


func _ready() -> void:
	super._ready()
	combat_health.health_changed.connect(_on_combat_health_changed)
	health = roundi(combat_health.current_health)


func _create_attack() -> EnemyAttack:
	return GiveMonsterAttack.new()


## 供 GiveMonsterVisual 决定眼睛颜色：攻击意图现在由攻击实现维护。
func has_attack_intent() -> bool:
	var give_attack := attack as GiveMonsterAttack
	return give_attack != null and give_attack.has_intent()


func take_damage(amount: int) -> void:
	if amount <= 0 or _is_dead or not combat_health.is_alive():
		return
	var hit := CombatHit.new()
	hit.source = self
	hit.damage = float(amount)
	hit.position = global_position
	combat_health.receive_hit(hit)


func kill() -> void:
	if _is_dead:
		return
	if combat_health.is_alive():
		var hit := CombatHit.new()
		hit.source = self
		hit.damage = combat_health.current_health
		hit.position = global_position
		combat_health.receive_hit(hit)
		return
	_finalize_death()


func _on_combat_health_changed(current: float, maximum: float) -> void:
	health = roundi(current)
	health_changed.emit(health, roundi(maximum))


func _finalize_death() -> void:
	if _is_dead:
		return
	_is_dead = true
	health = 0
	defeated.emit()
	super.kill()
