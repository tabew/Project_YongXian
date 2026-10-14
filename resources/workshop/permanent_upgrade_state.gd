class_name PermanentUpgradeState
extends RefCounted

## 永久升级的存档状态与购买逻辑（纯逻辑）。
## 永久灵感池与局内灵感分开：局内灵感死亡会损失，永久池只增不减。

## 永久灵感池。
var inspiration: int = 0
## upgrade_id -> 已购等级。
var levels: Dictionary = {}
## 累计通关次数（用于难度解锁）。
var clears: int = 0


func level_of(id: StringName) -> int:
	return int(levels.get(id, 0))


func is_maxed(id: StringName) -> bool:
	var upgrade: PermanentUpgrade = PermanentUpgradeCatalog.find(id)
	if upgrade == null:
		return true
	return level_of(id) >= upgrade.max_level


## 升到下一级的花费；已满级返回 -1。
func cost_of(id: StringName) -> int:
	var upgrade: PermanentUpgrade = PermanentUpgradeCatalog.find(id)
	if upgrade == null:
		return -1
	return upgrade.cost_for_level(level_of(id))


func prerequisite_met(id: StringName) -> bool:
	var upgrade: PermanentUpgrade = PermanentUpgradeCatalog.find(id)
	if upgrade == null:
		return false
	if upgrade.prerequisite_id == &"":
		return true
	return level_of(upgrade.prerequisite_id) >= upgrade.prerequisite_level


func can_purchase(id: StringName) -> bool:
	var upgrade: PermanentUpgrade = PermanentUpgradeCatalog.find(id)
	if upgrade == null:
		return false
	if is_maxed(id) or not prerequisite_met(id):
		return false
	var cost: int = upgrade.cost_for_level(level_of(id))
	return cost >= 0 and inspiration >= cost


func purchase(id: StringName) -> bool:
	if not can_purchase(id):
		return false
	var cost: int = cost_of(id)
	inspiration -= cost
	levels[id] = level_of(id) + 1
	return true


func add_inspiration(amount: int) -> void:
	inspiration += maxi(amount, 0)


## 已花掉的灵感总量。
func total_spent() -> int:
	var total: int = 0
	for upgrade: PermanentUpgrade in PermanentUpgradeCatalog.all():
		var owned: int = level_of(upgrade.id)
		for index: int in owned:
			total += upgrade.cost_for_level(index)
	return total


## 某条升级的累计效果值。
func total_effect(id: StringName) -> float:
	var upgrade: PermanentUpgrade = PermanentUpgradeCatalog.find(id)
	if upgrade == null:
		return 0.0
	return upgrade.total_effect(level_of(id))


## 按效果键聚合的累计效果（元素词条除外，见 element_level）。
func effect_value(kind: StringName) -> float:
	var total: float = 0.0
	for upgrade: PermanentUpgrade in PermanentUpgradeCatalog.all():
		if upgrade.effect_kind == kind and upgrade.effect_kind != PermanentUpgradeCatalog.EFFECT_ELEMENT_LEVEL:
			total += upgrade.total_effect(level_of(upgrade.id))
	return total


## 某个元素词条的额外等级。
func element_level(trait_id: StringName) -> int:
	return level_of(StringName("element_" + String(trait_id)))


func retention_level() -> int:
	return level_of(&"retention")


func retention_ratio() -> float:
	return InspirationRules.retention_ratio(retention_level())


func register_clear() -> void:
	clears += 1


func unlocked_difficulty() -> int:
	return DifficultyTier.unlocked_max_tier(clears)


func to_dict() -> Dictionary:
	return {"inspiration": inspiration, "levels": levels.duplicate(), "clears": clears}


func from_dict(data: Dictionary) -> void:
	inspiration = int(data.get("inspiration", 0))
	levels.clear()
	for id: StringName in data.get("levels", {}):
		levels[StringName(id)] = int(data["levels"][id])
	clears = int(data.get("clears", 0))
