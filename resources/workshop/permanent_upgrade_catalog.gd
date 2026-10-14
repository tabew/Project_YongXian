class_name PermanentUpgradeCatalog
extends RefCounted

## 永久升级配置表（唯一真源）。全部升满总消耗 29100 灵感，落在 25000~30000 区间。
## 元素词条升级每种元素一条，各 1 级。

const EFFECT_MATERIAL_SLOTS: StringName = &"material_slots"
const EFFECT_BAG_CAPACITY: StringName = &"bag_capacity"
const EFFECT_STACK_BONUS: StringName = &"stack_bonus"
const EFFECT_BASE_DURATION: StringName = &"base_duration"
const EFFECT_BURST_RATIO: StringName = &"burst_ratio"
const EFFECT_HEAT_COOLDOWN: StringName = &"heat_cooldown"
const EFFECT_HEAT_MAX: StringName = &"heat_max"
const EFFECT_ADSORB_RADIUS: StringName = &"adsorb_radius"
const EFFECT_ELEMENT_LEVEL: StringName = &"element_level"
const EFFECT_REACTION_BONUS: StringName = &"reaction_bonus"
const EFFECT_OVERLOAD_LOSS: StringName = &"overload_loss"
const EFFECT_OVERLOAD_DISABLE: StringName = &"overload_disable"
const EFFECT_PRESET_SLOTS: StringName = &"preset_slots"
const EFFECT_RETENTION: StringName = &"retention"

## 元素升级覆盖的词条（与 trait_catalog 的元素词条一一对应）。
const ELEMENT_TRAITS: Array[StringName] = [
	&"fire", &"poison", &"ice", &"electric", &"acid", &"magnet", &"soul",
	&"bone", &"blood", &"wind", &"sand", &"light", &"dark",
]

const UPGRADES: Array[Dictionary] = [
	{"id": &"material_slots", "name": "素材槽 +1", "max_level": 2, "costs": [400, 900],
		"effects": [1.0, 1.0], "effect_kind": EFFECT_MATERIAL_SLOTS,
		"description": "炼金台素材槽 +1（2 → 4）。"},
	{"id": &"bag_capacity", "name": "背包 +2 格", "max_level": 3, "costs": [300, 600, 1200],
		"effects": [2.0, 2.0, 2.0], "effect_kind": EFFECT_BAG_CAPACITY,
		"description": "炼金材料背包 +2 格。"},
	{"id": &"stack_bonus", "name": "堆叠 +20%", "max_level": 3, "costs": [250, 500, 1000],
		"effects": [0.2, 0.2, 0.2], "effect_kind": EFFECT_STACK_BONUS,
		"description": "材料堆叠上限 +20%。"},
	{"id": &"base_duration", "name": "基础时长 +2s", "max_level": 2, "costs": [500, 1100],
		"effects": [2.0, 2.0], "effect_kind": EFFECT_BASE_DURATION,
		"description": "炼金效果基础持续时间 +2 秒。"},
	{"id": &"burst_ratio", "name": "替换爆发 +10%", "max_level": 2, "costs": [450, 950],
		"effects": [0.1, 0.1], "effect_kind": EFFECT_BURST_RATIO,
		"description": "替换爆发强度 +10%。"},
	{"id": &"heat_cooldown", "name": "热量冷却 +10%", "max_level": 3, "costs": [300, 650, 1300],
		"effects": [0.1, 0.1, 0.1], "effect_kind": EFFECT_HEAT_COOLDOWN,
		"description": "热量冷却速度 +10%。"},
	{"id": &"heat_max", "name": "热量上限 +10", "max_level": 2, "costs": [350, 800],
		"effects": [10.0, 10.0], "effect_kind": EFFECT_HEAT_MAX,
		"description": "热量上限 +10。"},
	{"id": &"adsorb_radius", "name": "吸附范围 +1", "max_level": 2, "costs": [400, 900],
		"effects": [1.0, 1.0], "effect_kind": EFFECT_ADSORB_RADIUS,
		"description": "材料吸附范围 +1 格。"},
	{"id": &"reaction_bonus", "name": "反应效果 +10%", "max_level": 2, "costs": [400, 900],
		"effects": [0.1, 0.1], "effect_kind": EFFECT_REACTION_BONUS,
		"description": "炼金反应效果 +10%。"},
	{"id": &"overload_loss", "name": "过热损失 -50%", "max_level": 1, "costs": [1200],
		"effects": [0.5], "effect_kind": EFFECT_OVERLOAD_LOSS,
		"description": "过载时材料损失减半。"},
	{"id": &"overload_disable", "name": "过热失效 -2s", "max_level": 1, "costs": [1000],
		"effects": [2.0], "effect_kind": EFFECT_OVERLOAD_DISABLE,
		"prerequisite_id": &"overload_loss", "prerequisite_level": 1,
		"description": "过载武器失效时间 -2 秒。"},
	{"id": &"preset_slots", "name": "快速预设 +1", "max_level": 3, "costs": [350, 700, 1400],
		"effects": [1.0, 1.0, 1.0], "effect_kind": EFFECT_PRESET_SLOTS,
		"description": "快速预设槽 +1（1 → 4）。"},
	{"id": &"retention", "name": "灵感留存", "max_level": 5, "costs": [200, 500, 1000, 2000, 4000],
		"effects": [0.05, 0.05, 0.05, 0.05, 0.05], "effect_kind": EFFECT_RETENTION,
		"description": "死亡时保留 5%/10%/15%/20%/25% 局内灵感。"},
]

static var _by_id: Dictionary = {}
static var _all: Array[PermanentUpgrade] = []


static func _ensure() -> void:
	if not _all.is_empty():
		return
	for entry: Dictionary in UPGRADES:
		_all.append(PermanentUpgrade.create(entry))
	for trait_id: StringName in ELEMENT_TRAITS:
		var element_entry: Dictionary = {
			"id": StringName("element_" + String(trait_id)),
			"name": "元素词条 +1 级（%s）" % String(trait_id),
			"max_level": 1,
			"costs": [200],
			"effects": [1.0],
			"effect_kind": EFFECT_ELEMENT_LEVEL,
			"trait_id": trait_id,
			"description": "该元素词条等级 +1。",
		}
		_all.append(PermanentUpgrade.create(element_entry))
	for upgrade: PermanentUpgrade in _all:
		_by_id[upgrade.id] = upgrade


static func all() -> Array[PermanentUpgrade]:
	_ensure()
	return _all


static func find(id: StringName) -> PermanentUpgrade:
	_ensure()
	return _by_id.get(id, null)


static func has(id: StringName) -> bool:
	_ensure()
	return _by_id.has(id)


## 全部升满的总消耗。
static func total_cost() -> int:
	_ensure()
	var total: int = 0
	for upgrade: PermanentUpgrade in _all:
		total += upgrade.total_cost()
	return total


## 需要某个前置升级的升级项。
static func dependents_of(id: StringName) -> Array[PermanentUpgrade]:
	_ensure()
	var result: Array[PermanentUpgrade] = []
	for upgrade: PermanentUpgrade in _all:
		if upgrade.prerequisite_id == id:
			result.append(upgrade)
	return result
