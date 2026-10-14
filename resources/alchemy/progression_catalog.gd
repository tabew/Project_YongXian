class_name ProgressionCatalog
extends RefCounted

## 升级与遗物配置表（唯一真源）。新增升级 / 遗物只改这里。
##
## 每条 {"id": StringName, "name": 中文名, "desc": 说明, "max_level": 可叠加层数,
##       "modifier": {修正键: 每层数值}}。
## 遗物只有 1 层，max_level 固定为 1。
## 修正键与 AlchemyProgression 的派生字段一一对应，聚合时同名键相加；
## 布尔类键（true/false）聚合时取「或」；slow_motion_scale 取最小值（越小越慢）。

## 布尔型修正键：聚合时任一来源为真即为真。
const FLAG_KEYS: Array[StringName] = [
	&"uninterruptible", &"fire_guaranteed", &"poison_safe", &"random_mutation",
	&"overload_material_safe", &"overload_no_weapon_disable", &"interrupt_no_heat",
	&"no_stun", &"chaos_random", &"living_safe", &"no_time_cost",
]
## 取最小值而非相加的修正键。
const MIN_KEYS: Array[StringName] = [&"slow_motion_scale"]

const UPGRADES: Array[Dictionary] = [
	{"id": &"slot_plus", "name": "素材槽 +1", "desc": "素材槽 +1（最多 2 层）",
		"max_level": 2, "modifier": {&"slot_plus": 1}},
	{"id": &"bag_expand", "name": "背包扩容", "desc": "背包 +2 格（最多 4 层）",
		"max_level": 4, "modifier": {&"bag_plus": 2}},
	{"id": &"stack_plus", "name": "堆叠上限", "desc": "材料堆叠上限 +20%（最多 3 层）",
		"max_level": 3, "modifier": {&"stack_multiplier_plus": 0.20}},
	{"id": &"preset_plus", "name": "快速预设 +1", "desc": "快速预设 +1（最多 3 层）",
		"max_level": 3, "modifier": {&"preset_plus": 1}},
	{"id": &"weapon_slot_plus", "name": "武器炼金槽 +1", "desc": "武器临时炼金槽 +1（最多 1 层）",
		"max_level": 1, "modifier": {&"weapon_slot_plus": 1}},
	{"id": &"auto_stabilizer", "name": "自动稳定剂", "desc": "炼金稳定 +10%",
		"max_level": 1, "modifier": {&"stability_bonus": 0.10}},
	{"id": &"heat_cooldown", "name": "热量冷却", "desc": "热量冷却 +20%（最多 3 层）",
		"max_level": 3, "modifier": {&"heat_cooldown_plus": 0.20}},
	{"id": &"magnet_range", "name": "吸附范围", "desc": "吸附范围 +1 格（最多 3 层）",
		"max_level": 3, "modifier": {&"adsorb_tiles_plus": 1.0}},
	{"id": &"brew_uninterruptible", "name": "炼金不打断", "desc": "炼金过程中不被受击打断",
		"max_level": 1, "modifier": {&"uninterruptible": true}},
	{"id": &"brew_invuln", "name": "炼金无敌", "desc": "炼金瞬间获得 0.3 秒无敌",
		"max_level": 1, "modifier": {&"invuln_seconds": 0.30}},
	{"id": &"slow_motion", "name": "慢动作 15%", "desc": "长按 E 轮盘降到 15% 慢动作",
		"max_level": 1, "modifier": {&"slow_motion_scale": 0.15}},
	{"id": &"fire_guaranteed", "name": "火炼金必爆", "desc": "火系炼金必定触发爆炸",
		"max_level": 1, "modifier": {&"fire_guaranteed": true}},
	{"id": &"poison_safe", "name": "毒不伤己", "desc": "毒系炼金不再自伤",
		"max_level": 1, "modifier": {&"poison_safe": true}},
	{"id": &"random_mutation", "name": "随机变异", "desc": "炼金有概率额外产生一个随机词条",
		"max_level": 1, "modifier": {&"random_mutation": true}},
	{"id": &"burst_boost", "name": "爆发强化", "desc": "替换爆发强度 75%",
		"max_level": 1, "modifier": {&"burst_bonus": 0.75}},
	{"id": &"burst_master", "name": "爆发大师", "desc": "替换爆发强度 100%",
		"max_level": 1, "modifier": {&"burst_bonus": 1.00}},
	{"id": &"heat_slow", "name": "热量减缓", "desc": "热量积累 -50%（最多 2 层）",
		"max_level": 2, "modifier": {&"heat_slow": 0.50}},
	{"id": &"overload_protect", "name": "过热保护", "desc": "过载时不再损失材料",
		"max_level": 1, "modifier": {&"overload_material_safe": true}},
	{"id": &"overload_shorten", "name": "过热缩短", "desc": "过载武器失效 / 锁定 -50%（最多 2 层）",
		"max_level": 2, "modifier": {&"overload_shorten": 0.50}},
]

const RELICS: Array[Dictionary] = [
	{"id": &"alchemy_heart", "name": "炼金之心", "desc": "素材槽 +1",
		"modifier": {&"slot_plus": 1}},
	{"id": &"endless_bag", "name": "无尽背包", "desc": "背包 +4 格",
		"modifier": {&"bag_plus": 4}},
	{"id": &"stability_amulet", "name": "稳定护符", "desc": "副作用 -30%",
		"modifier": {&"side_effect_reduction": 0.30}},
	{"id": &"crit_eye", "name": "暴击之眼", "desc": "暴击率 +15%",
		"modifier": {&"crit_bonus": 0.15}},
	{"id": &"elemental_affinity", "name": "元素亲和", "desc": "元素词条 +1 级",
		"modifier": {&"element_level_plus": 1}},
	{"id": &"reaction_master", "name": "反应大师", "desc": "反应效果 +30%",
		"modifier": {&"reaction_bonus": 0.30}},
	{"id": &"time_hourglass", "name": "时间沙漏", "desc": "持续时间 +25%",
		"modifier": {&"duration_bonus": 0.25}},
	{"id": &"heat_core", "name": "热量核心", "desc": "热量冷却 +50%",
		"modifier": {&"heat_cooldown_plus": 0.50}},
	{"id": &"overload_engine", "name": "过载引擎", "desc": "过载后武器不失效",
		"modifier": {&"overload_no_weapon_disable": true}},
	{"id": &"decoy_straw", "name": "替身草人", "desc": "受击打断不加热量",
		"modifier": {&"interrupt_no_heat": true}},
	{"id": &"fast_hand", "name": "快速之手", "desc": "短按 E 无硬直",
		"modifier": {&"no_stun": true}},
	{"id": &"slow_motion_chip", "name": "慢动作芯片", "desc": "长按 E 轮盘降到 15% 慢动作",
		"modifier": {&"slow_motion_scale": 0.15}},
	{"id": &"burst_rune", "name": "爆发符文", "desc": "替换爆发强度 75%",
		"modifier": {&"burst_bonus": 0.75}},
	{"id": &"annihilation_seed", "name": "湮灭之种", "desc": "光 + 暗反应 +100%",
		"modifier": {&"annihilation_bonus": 1.00}},
	{"id": &"chaos_stone", "name": "混沌石", "desc": "炼金随机词条 +1 级",
		"modifier": {&"chaos_random": true}},
	{"id": &"world_tree", "name": "世界树苗", "desc": "活体炼金不伤己",
		"modifier": {&"living_safe": true}},
	{"id": &"time_sand", "name": "时之沙", "desc": "炼金不消耗时间",
		"modifier": {&"no_time_cost": true}},
	# 各元素 +1 级遗物（火 / 毒 / 冰 / 电 / 酸 / 磁 / 灵魂 / 骨 / 血 / 风 / 沙 / 光 / 暗）
	{"id": &"relic_fire", "name": "烈焰之心", "desc": "火词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"fire"}},
	{"id": &"relic_poison", "name": "腐毒之种", "desc": "毒词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"poison"}},
	{"id": &"relic_ice", "name": "寒霜之核", "desc": "冰词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"ice"}},
	{"id": &"relic_electric", "name": "雷鸣之石", "desc": "电词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"electric"}},
	{"id": &"relic_acid", "name": "蚀骨之液", "desc": "酸词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"acid"}},
	{"id": &"relic_magnet", "name": "引磁之石", "desc": "磁词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"magnet"}},
	{"id": &"relic_soul", "name": "幽魂之尘", "desc": "灵魂词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"soul"}},
	{"id": &"relic_bone", "name": "白骨之粉", "desc": "骨词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"bone"}},
	{"id": &"relic_blood", "name": "血髓之石", "desc": "血词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"blood"}},
	{"id": &"relic_wind", "name": "风灵之羽", "desc": "风词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"wind"}},
	{"id": &"relic_sand", "name": "沙皇之砾", "desc": "沙词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"sand"}},
	{"id": &"relic_light", "name": "光辉之核", "desc": "光词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"light"}},
	{"id": &"relic_dark", "name": "深渊之晶", "desc": "暗词条 +1 级",
		"modifier": {&"element_level_plus": 1, &"element_id": &"dark"}},
]

static var _upgrade_table: Dictionary = {}
static var _relic_table: Dictionary = {}


static func _ensure_tables() -> void:
	if not _upgrade_table.is_empty() or not _relic_table.is_empty():
		return
	for entry: Dictionary in UPGRADES:
		_upgrade_table[entry["id"]] = entry
	for entry: Dictionary in RELICS:
		_relic_table[entry["id"]] = entry


static func upgrade_of(id: StringName) -> Dictionary:
	_ensure_tables()
	return _upgrade_table.get(id, {})


static func relic_of(id: StringName) -> Dictionary:
	_ensure_tables()
	return _relic_table.get(id, {})


static func has_upgrade(id: StringName) -> bool:
	return not upgrade_of(id).is_empty()


static func has_relic(id: StringName) -> bool:
	return not relic_of(id).is_empty()


static func max_level_of(id: StringName) -> int:
	return maxi(int(upgrade_of(id).get("max_level", 1)), 1)


static func all_upgrade_ids() -> Array[StringName]:
	_ensure_tables()
	var ids: Array[StringName] = []
	for entry: Dictionary in UPGRADES:
		ids.append(entry["id"])
	return ids


static func all_relic_ids() -> Array[StringName]:
	_ensure_tables()
	var ids: Array[StringName] = []
	for entry: Dictionary in RELICS:
		ids.append(entry["id"])
	return ids


static func display_name_of(id: StringName) -> String:
	var entry: Dictionary = relic_of(id)
	if entry.is_empty():
		entry = upgrade_of(id)
	return String(entry.get("name", String(id)))
