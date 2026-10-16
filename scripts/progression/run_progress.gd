extends Node

## 局内成长：等级、经验、已选升级卡。跨场景保留，开新局时由 GameState 重置。
##
## 这里只负责“状态与数值聚合”，不碰场景：加成的实际应用由玩家、武器与炼金各自读取。

signal experience_changed(current: float, required: float, level: int)
signal level_up(new_level: int)
signal card_taken(card_id: StringName)
signal cards_changed()

## 1 级升 2 级所需经验；之后每级按 CURVE_STEP 递增。
const BASE_EXPERIENCE: int = 8
const CURVE_STEP: int = 4
## 装瓶成功的基础炼金经验。
const ALCHEMY_BASE_EXPERIENCE: int = 6
## 本局首次合成某配方的额外经验。
const ALCHEMY_FIRST_BONUS: int = 12
## 产物含 2 级以上属性时的额外经验。
const ALCHEMY_LEVEL_BONUS: int = 8

var level: int = 1
var experience: float = 0.0
## 等待玩家三选一的次数。
var pending_choices: int = 0
## card_id -> 层数
var cards_taken: Dictionary = {}
## 本局已合成过的配方 key。
var discovered_recipes: Dictionary = {}
## 连续未出稀有的次数，用于保底。
var rolls_since_rare: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	reset()


## 开新局：等级、经验、已选卡与配方记录全部清零。
func reset() -> void:
	level = 1
	experience = 0.0
	pending_choices = 0
	cards_taken.clear()
	discovered_recipes.clear()
	rolls_since_rare = 0
	experience_changed.emit(experience, experience_required(), level)
	cards_changed.emit()


## 升到下一级还需要多少经验。
func experience_required() -> float:
	return float(BASE_EXPERIENCE + CURVE_STEP * (level - 1))


## 升级进度 0~1。
func experience_ratio() -> float:
	var required: float = experience_required()
	if required <= 0.0:
		return 0.0
	return clampf(experience / required, 0.0, 1.0)


## 加经验；跨过多级时逐级结算，每次升级都排一次三选一。
func add_experience(amount: float) -> void:
	if amount <= 0.0:
		return
	experience += amount
	while experience >= experience_required():
		experience -= experience_required()
		level += 1
		pending_choices += 1
		level_up.emit(level)
	experience_changed.emit(experience, experience_required(), level)


## 击杀经验：基础值乘楼层缩放，再乘击杀经验加成。
func kill_experience(base_reward: int, floor_index: int) -> float:
	var scaled: float = float(base_reward) * (1.0 + 0.12 * float(maxi(floor_index, 0)))
	return scaled * (1.0 + UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_KILL_EXP))


## 炼金经验：装瓶成功时结算。配方 key 相同只给一次首合奖励。
func alchemy_experience(recipe_key: String, highest_level: int) -> float:
	var total: float = float(ALCHEMY_BASE_EXPERIENCE)
	if not recipe_key.is_empty() and not discovered_recipes.has(recipe_key):
		discovered_recipes[recipe_key] = true
		total += float(ALCHEMY_FIRST_BONUS)
	if highest_level >= 2:
		total += float(ALCHEMY_LEVEL_BONUS)
	return total * (1.0 + UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_ALCHEMY_EXP))


func stacks_of(card_id: StringName) -> int:
	return int(cards_taken.get(card_id, 0))


## 取一次三选一。保底在连续 PITY_ROLLS 次没出稀有后触发。
func roll_choices(current_weapon: StringName, health_ratio: float) -> Array[UpgradeCard]:
	var force_rare: bool = rolls_since_rare >= UpgradePool.PITY_ROLLS
	var result: Array[UpgradeCard] = UpgradePool.roll(
		UpgradePool.CHOICE_COUNT, cards_taken, current_weapon, health_ratio, force_rare, _rng
	)
	if UpgradePool.contains_rare(result):
		rolls_since_rare = 0
	else:
		rolls_since_rare += 1
	return result


## 选定一张卡：记层数并消耗一次待选。
func take_card(card_id: StringName) -> bool:
	var card: UpgradeCard = UpgradePool.get_card(card_id)
	if card == null:
		return false
	if stacks_of(card_id) >= card.max_stacks:
		return false
	cards_taken[card_id] = stacks_of(card_id) + 1
	pending_choices = maxi(pending_choices - 1, 0)
	card_taken.emit(card_id)
	cards_changed.emit()
	return true


# --- 数值聚合 -------------------------------------------------------------

func max_health_add() -> float:
	return UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_MAX_HEALTH_ADD)


func defense_add() -> float:
	return UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_DEFENSE_ADD)


func damage_taken_mult() -> float:
	return maxf(1.0 + UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_DAMAGE_TAKEN_MULT), 0.05)


func damage_mult() -> float:
	return maxf(1.0 + UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_DAMAGE_MULT), 0.0)


func move_speed_mult() -> float:
	return maxf(1.0 + UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_MOVE_SPEED_MULT), 0.1)


func attack_speed_mult() -> float:
	return clampf(1.0 + UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_ATTACK_SPEED_MULT), 0.25, 4.0)


func crit_chance_add() -> float:
	return UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_CRIT_CHANCE_ADD)


func crit_multiplier_add() -> float:
	return UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_CRIT_MULT_ADD)


func knockback_mult() -> float:
	return maxf(1.0 + UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_KNOCKBACK_MULT), 0.0)


func pickup_radius_add() -> float:
	return UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_PICKUP_ADD)


func lifesteal_on_kill() -> float:
	return UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_LIFESTEAL)


func loot_bonus() -> int:
	return int(UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_LOOT_BONUS))


func chain_mult() -> float:
	return UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_CHAIN_MULT)


func combo_damage_per_stack() -> float:
	return UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_COMBO_DAMAGE)


func low_health_reduction() -> float:
	return clampf(UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_LOW_HEALTH_REDUCTION), 0.0, 0.9)


func regen_per_second() -> float:
	return UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_REGEN)


func alchemy_power_mult() -> float:
	return maxf(1.0 + UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_ALCHEMY_POWER), 0.0)


func potion_range_mult() -> float:
	return maxf(1.0 + UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_POTION_RANGE), 0.1)


func alchemy_echo_chance() -> float:
	return clampf(UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_ALCHEMY_ECHO), 0.0, 1.0)


func heal_mult() -> float:
	return maxf(1.0 + UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_HEAL_MULT), 0.0)


func potion_blocked() -> bool:
	return UpgradePool.sum_effects(cards_taken, UpgradePool.KEY_NO_POTION) > 0.0


## 由一份基础武器定义造出本局的实际武器：副本 + 攻速 + 武器卡。
## 必须在副本上改，直接改会写回 .tres 并跨局残留。
func build_weapon(base: WeaponDefinition) -> WeaponDefinition:
	if base == null:
		return null
	var modified: WeaponDefinition = base.duplicate(true) as WeaponDefinition
	if modified == null:
		return null
	modified.critical_chance = clampf(modified.critical_chance + crit_chance_add(), 0.0, 1.0)
	modified.critical_multiplier = maxf(modified.critical_multiplier + crit_multiplier_add(), 1.0)
	modified.knockback = maxf(modified.knockback * knockback_mult(), 0.0)
	# 时间轴统一交给 apply_weapon_cards 结算：它先叠武器卡的绝对值，再整体除攻速，
	# 所以“迅捷”对旋风那类写死时间的卡同样有效。
	UpgradePool.apply_weapon_cards(modified, cards_taken, attack_speed_mult())
	return modified