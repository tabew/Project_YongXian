class_name GiveMonster
extends BaseMonster

## 临时名"给"：在稀树草原、草原、森林、热带雨林生成，可跨群系活动的猿猴型怪物。
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
const FUR_DROP_CHANCE: float = 0.70
const FUR_DATA: IngredientData = preload("res://resources/items/ingredients/give_fur.tres")
const HIDE_DATA: IngredientData = preload("res://resources/items/ingredients/monkey_hide.tres")

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
	_drop_death_loot()
	defeated.emit()
	super.kill()


## 同一轮抽样二选一，必定掉一件；地图卸载不经过死亡流程。
static func death_loot_for_roll(roll: float) -> IngredientData:
	return FUR_DATA if roll < FUR_DROP_CHANCE else HIDE_DATA


func _drop_death_loot() -> void:
	var loot_parent: Node = get_parent()
	if loot_parent == null:
		return
	var pickup := GroundPickup.new()
	pickup.name = "GiveLoot"
	pickup.bind(death_loot_for_roll(MapRng.shared(MapRng.Stream.LOOT).randf()), 1)
	loot_parent.add_child(pickup)
	pickup.global_position = global_position
