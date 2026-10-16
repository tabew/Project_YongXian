class_name UpgradePool
extends RefCounted

## 升级卡池：卡表 + 三选一抽取规则 + 武器改造应用。
##
## 卡表是纯数据；数值类效果由 RunProgress 聚合后应用，机制类效果由各系统读同名键自行实现。

const CHOICE_COUNT: int = 3
const RARITY_WEIGHTS: Array[float] = [60.0, 30.0, 10.0]
## 连续这么多次没出稀有，下一次必出。
const PITY_ROLLS: int = 2

# --- 效果键 ---------------------------------------------------------------

## 生命上限加值（绝对值）。
const KEY_MAX_HEALTH_ADD: StringName = &"max_health_add"
## 固定减伤（绝对值）。
const KEY_DEFENSE_ADD: StringName = &"defense_add"
## 拾取范围加值（格）。
const KEY_PICKUP_ADD: StringName = &"pickup_radius_add"
## 击杀回复生命。
const KEY_LIFESTEAL: StringName = &"lifesteal_on_kill"
## 材料掉落加值。
const KEY_LOOT_BONUS: StringName = &"loot_bonus"
## 暴击倍率加值。
const KEY_CRIT_MULT_ADD: StringName = &"crit_multiplier_add"
## 每秒回血。
const KEY_REGEN: StringName = &"regen_per_second"
## 全武器伤害倍率加值。
const KEY_DAMAGE_MULT: StringName = &"damage_mult"
## 移速倍率加值。
const KEY_MOVE_SPEED_MULT: StringName = &"move_speed_mult"
## 暴击率加值。
const KEY_CRIT_CHANCE_ADD: StringName = &"crit_chance_add"
const KEY_EVENT_CHANCE_MULT: StringName = &"event_chance_mult"
const KEY_YOYO_ULTIMATE: StringName = &"yoyo_ultimate"
## 击退倍率加值。
const KEY_KNOCKBACK_MULT: StringName = &"knockback_mult"
## 攻速倍率加值。
const KEY_ATTACK_SPEED_MULT: StringName = &"attack_speed_mult"
## 受到伤害倍率加值（负数为减伤）。
const KEY_DAMAGE_TAKEN_MULT: StringName = &"damage_taken_mult"
## 连锁伤害比例。
const KEY_CHAIN_MULT: StringName = &"chain_damage_mult"
## 连续命中同一目标的每层伤害加值。
const KEY_COMBO_DAMAGE: StringName = &"combo_damage_per_stack"
## 低生命时的额外减伤。
const KEY_LOW_HEALTH_REDUCTION: StringName = &"low_health_reduction"
## 药水效果强度加值。
const KEY_ALCHEMY_POWER: StringName = &"alchemy_power_mult"
## 药水投掷距离加值。
const KEY_POTION_RANGE: StringName = &"potion_range_mult"
## 装瓶额外产出的概率。
const KEY_ALCHEMY_ECHO: StringName = &"alchemy_echo_chance"
## 炼金经验倍率加值。
const KEY_ALCHEMY_EXP: StringName = &"alchemy_exp_mult"
## 击杀经验倍率加值。
const KEY_KILL_EXP: StringName = &"kill_exp_mult"
## 治疗量倍率加值（负数为削弱）。
const KEY_HEAL_MULT: StringName = &"heal_mult"
## 禁止使用药水。
const KEY_NO_POTION: StringName = &"no_potion"

# --- 武器改造键 -----------------------------------------------------------

const KEY_WEAPON_DAMAGE_MULT: StringName = &"weapon_damage_mult"
const KEY_WEAPON_KNOCKBACK_MULT: StringName = &"weapon_knockback_mult"
const KEY_WEAPON_WINDUP_ADD: StringName = &"weapon_windup_add"
const KEY_WEAPON_ARC_ADD: StringName = &"weapon_arc_add"
const KEY_WEAPON_COMBO_WINDOW: StringName = &"weapon_combo_window"
const KEY_WEAPON_LUNGE: StringName = &"weapon_lunge_tiles"
const KEY_SET_ACTIVE: StringName = &"set_active_seconds"
const KEY_SPEAR_REACH_MULT: StringName = &"spear_reach_mult"
const KEY_THRUST_COUNT_ADD: StringName = &"thrust_count_add"
const KEY_MAX_RANGE_MULT: StringName = &"max_range_mult"
const KEY_SLOW_RATIO: StringName = &"slow_ratio"
const KEY_SLOW_SECONDS: StringName = &"slow_seconds"
const KEY_ORBIT_BALLS: StringName = &"orbit_balls"

static var _catalog: Dictionary = {}


## id -> UpgradeCard。首次访问时建表。
static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_build_catalog()
	return _catalog


static func get_card(id: StringName) -> UpgradeCard:
	return catalog().get(id)


## 当前可出现的卡：未满层、武器卡匹配当前武器、代价卡满足生命门槛。
static func candidates(stacks: Dictionary, current_weapon: StringName, health_ratio: float) -> Array[UpgradeCard]:
	var result: Array[UpgradeCard] = []
	for id: StringName in catalog():
		var card: UpgradeCard = catalog()[id]
		if not can_take(card, stacks):
			continue
		if int(stacks.get(id, 0)) >= card.max_stacks:
			continue
		if card.scope == UpgradeCard.Scope.WEAPON and card.weapon_id != current_weapon:
			continue
		if card.health_ratio_gate > 0.0 and health_ratio < card.health_ratio_gate:
			continue
		result.append(card)
	return result


## 抽 count 张不重复的卡。force_rare 保证结果里至少有一张稀有。
static func can_take(card: UpgradeCard, stacks: Dictionary) -> bool:
	if card == null or int(stacks.get(card.id, 0)) >= card.max_stacks:
		return false
	if not card.exclusive_group.is_empty():
		for id: StringName in stacks:
			var taken: UpgradeCard = get_card(id)
			if int(stacks[id]) > 0 and taken != null and taken.exclusive_group == card.exclusive_group:
				return false
	return true


static func roll(
	count: int,
	stacks: Dictionary,
	current_weapon: StringName,
	health_ratio: float,
	force_rare: bool,
	rng: RandomNumberGenerator
) -> Array[UpgradeCard]:
	var pool: Array[UpgradeCard] = candidates(stacks, current_weapon, health_ratio)
	var result: Array[UpgradeCard] = []
	for index: int in count:
		if pool.is_empty():
			break
		var rarity: int = _pick_rarity(force_rare and index == 0, rng)
		var tier: Array[UpgradeCard] = _of_rarity(pool, rarity)
		if tier.is_empty():
			tier = pool
		var chosen: UpgradeCard = tier[rng.randi_range(0, tier.size() - 1)]
		result.append(chosen)
		pool.erase(chosen)
	return result


static func contains_rare(cards: Array[UpgradeCard]) -> bool:
	for card: UpgradeCard in cards:
		if card.rarity == UpgradeCard.Rarity.RARE:
			return true
	return false


static func _pick_rarity(force_rare: bool, rng: RandomNumberGenerator) -> int:
	if force_rare:
		return UpgradeCard.Rarity.RARE
	var total: float = 0.0
	for weight: float in RARITY_WEIGHTS:
		total += weight
	var target: float = rng.randf() * total
	var cumulative: float = 0.0
	for index: int in RARITY_WEIGHTS.size():
		cumulative += RARITY_WEIGHTS[index]
		if target < cumulative:
			return index
	return UpgradeCard.Rarity.COMMON


static func _of_rarity(pool: Array[UpgradeCard], rarity: int) -> Array[UpgradeCard]:
	var result: Array[UpgradeCard] = []
	for card: UpgradeCard in pool:
		if card.rarity == rarity:
			result.append(card)
	return result


## 已选卡在某效果键上的合计（每层数值 x 层数）。
static func sum_effects(stacks: Dictionary, key: StringName) -> float:
	var total: float = 0.0
	for id: StringName in stacks:
		var card: UpgradeCard = catalog().get(id)
		if card == null or not card.effects.has(key):
			continue
		total += float(card.effects[key]) * float(int(stacks[id]))
	return total


## 把已选的武器卡叠加到一份武器定义上。调用方必须传入副本。
##
## 只叠加“属于这把武器”的武器卡：卡是按武器 id 抽的，如果不过滤，
## 换武器后别的武器的改造会残留（例如长枪拿到溜溜球的环绕球）。
##
## attack_speed 是“迅捷”一类卡算出的攻速倍率。所有时间轴都在这里一次性结算，
## 顺序是“先叠卡的绝对值，再统一除攻速”，连刺的整段时间也受攻速影响。
static func apply_weapon_cards(weapon: WeaponDefinition, stacks: Dictionary, attack_speed: float = 1.0) -> void:
	if weapon == null:
		return
	var speed: float = maxf(attack_speed, 0.01)
	var applicable: Dictionary = weapon_card_stacks(weapon.id, stacks)
	weapon.damage = maxf(weapon.damage * (1.0 + sum_effects(applicable, KEY_WEAPON_DAMAGE_MULT)), 0.0)
	weapon.knockback = maxf(weapon.knockback * (1.0 + sum_effects(applicable, KEY_WEAPON_KNOCKBACK_MULT)), 0.0)
	weapon.combo_window = maxf(sum_effects(applicable, KEY_WEAPON_COMBO_WINDOW), 0.0)
	weapon.lunge_tiles = maxf(sum_effects(applicable, KEY_WEAPON_LUNGE), 0.0)
	weapon.slow_ratio = clampf(sum_effects(applicable, KEY_SLOW_RATIO), 0.0, 0.9)
	weapon.slow_seconds = maxf(sum_effects(applicable, KEY_SLOW_SECONDS), 0.0)
	weapon.orbit_balls = int(sum_effects(applicable, KEY_ORBIT_BALLS))

	# 时间轴：先吃卡的加值 / 绝对值，再统一按攻速缩短。
	var windup: float = weapon.windup_seconds + sum_effects(applicable, KEY_WEAPON_WINDUP_ADD)
	var active: float = weapon.active_seconds
	var reuse: float = weapon.reuse_delay
	var recovery: float = weapon.recovery_seconds
	var set_active: float = sum_effects(applicable, KEY_SET_ACTIVE)
	if set_active > 0.0:
		active = set_active
	weapon.windup_seconds = maxf(windup / speed, 0.0)
	weapon.active_seconds = maxf(active / speed, 0.01)
	weapon.recovery_seconds = maxf(recovery / speed, 0.0)
	weapon.reuse_delay = maxf(reuse / speed, 0.0)

	if weapon is SwingWeaponDefinition:
		var swing := weapon as SwingWeaponDefinition
		swing.arc_degrees = clampf(swing.arc_degrees + sum_effects(applicable, KEY_WEAPON_ARC_ADD), 1.0, 360.0)
	elif weapon is SpearWeaponDefinition:
		var spear := weapon as SpearWeaponDefinition
		var reach: float = maxf(1.0 + sum_effects(applicable, KEY_SPEAR_REACH_MULT), 0.1)
		spear.shaft_length = maxf(spear.shaft_length * reach, 4.0)
		spear.thrust_distance = maxf(spear.thrust_distance * reach, 1.0)
		spear.thrust_count = clampi(spear.thrust_count + int(sum_effects(applicable, KEY_THRUST_COUNT_ADD)), 1, 4)
	elif weapon is YoyoWeaponDefinition:
		var yoyo := weapon as YoyoWeaponDefinition
		yoyo.max_range = maxf(yoyo.max_range * (1.0 + sum_effects(applicable, KEY_MAX_RANGE_MULT)), yoyo.hand_distance + 1.0)
		# 长绳把回收时间推长，后摇必须跟着覆盖，否则校验不通过会静默失效。
		# 这一步必须放在攻速之后：回收时间不受攻速影响，先除后比才是正确的不变量。
		yoyo.recovery_seconds = maxf(yoyo.recovery_seconds, yoyo.return_seconds())
		if yoyo is SwarmYoyoDefinition:
			(yoyo as SwarmYoyoDefinition).apply_ultimate(int(sum_effects(applicable, KEY_YOYO_ULTIMATE)))


## 只保留“能作用在这把武器上”的卡：通用卡与机制卡始终保留，武器卡必须 id 匹配。
static func weapon_card_stacks(weapon_id: StringName, stacks: Dictionary) -> Dictionary:
	var applicable: Dictionary = {}
	for id: StringName in stacks:
		var card: UpgradeCard = catalog().get(id)
		if card == null:
			continue
		if card.scope == UpgradeCard.Scope.WEAPON and card.weapon_id != weapon_id:
			continue
		applicable[id] = stacks[id]
	return applicable


static func _build_catalog() -> void:
	_catalog.clear()
	var common: int = UpgradeCard.Rarity.COMMON
	var uncommon: int = UpgradeCard.Rarity.UNCOMMON
	var rare: int = UpgradeCard.Rarity.RARE
	var general: int = UpgradeCard.Scope.GENERAL
	var weapon_scope: int = UpgradeCard.Scope.WEAPON
	var alchemy: int = UpgradeCard.Scope.ALCHEMY
	var mechanic: int = UpgradeCard.Scope.MECHANIC
	var cost: int = UpgradeCard.Scope.COST
	_add_ultimate(&"thunder_contract", "天罚契约", "落雷必定触发；球体伤害 -60%，命中间隔变为 0.65 秒", &"thunder_yoyo", 1)
	_add_ultimate(&"thunder_core", "雷暴核心", "落雷伤害 +150%、半径 +50%；预警 0.6 秒，冷却 2 秒", &"thunder_yoyo", 2)
	_add_ultimate(&"thunder_beacon", "风暴信标", "原地连续落雷 3 次；首次延迟 0.5 秒，最多 2 个雷区", &"thunder_yoyo", 3)
	_add_ultimate(&"hive_bomb", "蜂巢炸弹", "维持满 1 秒后主动收球释放 8 只蜜蜂；不再命中生蜂", &"hive_yoyo", 4)
	_add_ultimate(&"hive_migration", "迁徙蜂群", "蜜蜂存活 5 秒，每 0.4 秒撕咬；球伤 -40%，生蜂间隔 1.2 秒", &"hive_yoyo", 5)
	_add(&"fortune", "幸运", "已有的武器特效、暴击与炼金回响概率相对提高 20%（10% → 12%）", common, general, 5, {KEY_EVENT_CHANCE_MULT: 0.20})

	_add(&"constitution", "体质", "生命上限 +15", common, general, 4, {KEY_MAX_HEALTH_ADD: 15.0})
	_add(&"toughness", "坚韧", "受到伤害 -6%", common, general, 3, {KEY_DAMAGE_TAKEN_MULT: -0.06})
	_add(&"swift", "疾行", "移动速度 +8%", common, general, 4, {KEY_MOVE_SPEED_MULT: 0.08})
	_add(&"sharp", "利刃", "全武器伤害 +12%", common, general, 5, {KEY_DAMAGE_MULT: 0.12})
	_add(&"keen", "锐眼", "暴击率 +3%", common, general, 5, {KEY_CRIT_CHANCE_ADD: 0.03})
	_add(&"lethal", "致命", "暴击伤害 +0.3 倍", common, general, 4, {KEY_CRIT_MULT_ADD: 0.3})
	_add(&"mighty", "巨力", "击退 +25%", common, general, 3, {KEY_KNOCKBACK_MULT: 0.25})
	_add(&"haste", "迅捷", "攻击速度 +8%", common, general, 4, {KEY_ATTACK_SPEED_MULT: 0.08})
	_add(&"scavenger", "拾荒", "拾取范围 +1 格", common, general, 3, {KEY_PICKUP_ADD: 1.0})

	_add(&"sword_gale", "裂风", "横扫范围 +60 度，伤害 -15%", rare, weapon_scope, 1,
		{KEY_WEAPON_ARC_ADD: 60.0, KEY_WEAPON_DAMAGE_MULT: -0.15}, &"longsword")
	_add(&"sword_heavy", "重斩", "伤害 +50%，前摇 +0.12 秒", rare, weapon_scope, 1,
		{KEY_WEAPON_DAMAGE_MULT: 0.50, KEY_WEAPON_WINDUP_ADD: 0.12}, &"longsword")
	_add(&"sword_combo", "回旋", "命中后立刻缩短后摇，可接下一刀", rare, weapon_scope, 1,
		{KEY_WEAPON_COMBO_WINDOW: 0.15}, &"longsword")
	_add(&"sword_press", "剑压", "击退翻倍，命中时自身前冲 1 格", rare, weapon_scope, 1,
		{KEY_WEAPON_KNOCKBACK_MULT: 1.0, KEY_WEAPON_LUNGE: 1.0}, &"longsword")

	_add(&"spear_reach", "长驱", "枪长与突刺距离 +35%，保持窄幅直刺", rare, weapon_scope, 1,
		{KEY_SPEAR_REACH_MULT: 0.35}, &"spear")
	_add(&"spear_heavy", "重刺", "突刺伤害 +40%，前摇 +0.10 秒", rare, weapon_scope, 1,
		{KEY_WEAPON_DAMAGE_MULT: 0.40, KEY_WEAPON_WINDUP_ADD: 0.10}, &"spear")
	_add(&"spear_flurry", "连刺", "沿出手方向连刺两次，每刺伤害 -20%，刺击阶段变为 0.30 秒", rare, weapon_scope, 1,
		{KEY_THRUST_COUNT_ADD: 1.0, KEY_WEAPON_DAMAGE_MULT: -0.20, KEY_SET_ACTIVE: 0.30}, &"spear")
	_add(&"spear_pin", "钉足", "命中使敌人减速 40%，持续 1.5 秒", rare, weapon_scope, 1,
		{KEY_SLOW_RATIO: 0.40, KEY_SLOW_SECONDS: 1.5}, &"spear")

	_add(&"yoyo_long", "长绳", "绳长 +60%", rare, weapon_scope, 1, {KEY_MAX_RANGE_MULT: 0.60}, &"yoyo")
	_add(&"yoyo_orbit", "环绕球", "攻击期间额外一颗球绕自身旋转", rare, weapon_scope, 1,
		{KEY_ORBIT_BALLS: 1.0}, &"yoyo")

	_add(&"alchemy_power", "药材学", "药水效果强度 +25%", uncommon, alchemy, 3, {KEY_ALCHEMY_POWER: 0.25})
	_add(&"alchemy_throw", "投掷精通", "药水投掷距离 +40%", uncommon, alchemy, 2, {KEY_POTION_RANGE: 0.40})
	_add(&"alchemy_echo", "炼金回响", "装瓶 20% 概率额外产出一瓶", uncommon, alchemy, 2, {KEY_ALCHEMY_ECHO: 0.20})
	_add(&"alchemy_study", "材料学", "炼金经验 +50%", uncommon, alchemy, 3, {KEY_ALCHEMY_EXP: 0.50})
	_add(&"blood_knowledge", "以血换知", "治疗量 -30%，击杀经验 +25%", uncommon, alchemy, 1,
		{KEY_HEAL_MULT: -0.30, KEY_KILL_EXP: 0.25})

	_add(&"lifesteal", "嗜血", "击杀回复 5 点生命", rare, mechanic, 3, {KEY_LIFESTEAL: 5.0})
	_add(&"chain", "连锁", "击杀对 2 格内敌人造成 50% 武器伤害", rare, mechanic, 2, {KEY_CHAIN_MULT: 0.50})
	_add(&"greed", "贪婪", "材料掉落 +1", rare, mechanic, 2, {KEY_LOOT_BONUS: 1.0})
	_add(&"rhythm", "节奏", "连续命中同一目标每层 +10% 伤害（最多 5 层）", rare, mechanic, 2, {KEY_COMBO_DAMAGE: 0.10})
	_add(&"ironhide", "铁皮", "固定减伤 +4", rare, mechanic, 3, {KEY_DEFENSE_ADD: 4.0})
	_add(&"last_stand", "濒死", "生命低于 30% 时受到伤害 -40%", rare, mechanic, 1, {KEY_LOW_HEALTH_REDUCTION: 0.40})
	_add(&"regen", "再生", "脱战 4 秒后每秒回复 1 点生命", rare, mechanic, 3, {KEY_REGEN: 1.0})

	_add(&"all_in", "孤注", "生命上限 -25，全武器伤害 +40%", rare, cost, 1,
		{KEY_MAX_HEALTH_ADD: -25.0, KEY_DAMAGE_MULT: 0.40}, &"", 0.70)
	_add(&"thin_blade", "薄刃", "伤害 +35%，受到伤害 +50%", rare, cost, 1,
		{KEY_DAMAGE_MULT: 0.35, KEY_DAMAGE_TAKEN_MULT: 0.50}, &"", 0.70)
	_add(&"ascetic", "苦行", "无法使用药水，全武器伤害 +45%", rare, cost, 1,
		{KEY_NO_POTION: 1.0, KEY_DAMAGE_MULT: 0.45}, &"", 0.70)


static func _add_ultimate(id: StringName, title: String, description: String, weapon: StringName, mode: int) -> void:
	_add(id, title, description + "。同武器终极改造每局限选一种", UpgradeCard.Rarity.RARE, UpgradeCard.Scope.WEAPON, 1, {KEY_YOYO_ULTIMATE: mode}, weapon)
	var card: UpgradeCard = _catalog[id]
	card.exclusive_group = StringName(str(weapon) + "_ultimate")


static func _add(
	id: StringName,
	name_text: String,
	desc_text: String,
	rarity: int,
	scope: int,
	stacks: int,
	effects: Dictionary,
	weapon_id: StringName = &"",
	gate: float = 0.0
) -> void:
	_catalog[id] = UpgradeCard.make(id, name_text, desc_text, rarity, scope, stacks, effects, weapon_id, gate)
