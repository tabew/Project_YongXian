class_name ReactionCatalog
extends RefCounted

## 反应与冲突配置表（唯一真源）。
## a / b 既可以是元素词条 id，也可以是材料标签（metal / machine / oil / water…）。
## level_mode 决定反应等级：average 平均、max 最高、min 最低、a / b 取指定一侧。
## 同一对词条可以既是反应又是冲突：火+冰出蒸汽爆炸，同时反噬。
## 可选字段 self_damage：该反应每秒给玩家的自伤（例如毒血把吸血变成自伤）。

const REACTIONS: Array[Dictionary] = [
	{"a": &"fire", "b": &"poison", "id": &"poison_smoke", "name": "毒烟", "level_mode": &"average"},
	{"a": &"fire", "b": &"ice", "id": &"steam_burst", "name": "蒸汽爆炸", "level_mode": &"max"},
	{"a": &"electric", "b": &"magnet", "id": &"magnetic_field", "name": "磁场拉拽", "level_mode": &"average"},
	{"a": &"acid", "b": &"metal", "id": &"corrosive_sunder", "name": "腐蚀破甲", "level_mode": &"a"},
	{"a": &"soul", "b": &"bone", "id": &"skeleton_summon", "name": "召唤骷髅", "level_mode": &"min"},
	{"a": &"light", "b": &"dark", "id": &"annihilation", "name": "湮灭", "level_mode": &"max"},
	{"a": &"wind", "b": &"sand", "id": &"dust_storm", "name": "尘暴致盲", "level_mode": &"average"},
	{"a": &"fire", "b": &"oil", "id": &"deflagration", "name": "爆燃", "level_mode": &"max"},
	{"a": &"fire", "b": &"wind", "id": &"fire_storm", "name": "火风暴", "level_mode": &"average"},
	{"a": &"ice", "b": &"wind", "id": &"blizzard", "name": "暴风雪", "level_mode": &"average"},
	{"a": &"electric", "b": &"wind", "id": &"thunderstorm", "name": "雷暴", "level_mode": &"max"},
	{"a": &"ice", "b": &"water", "id": &"ice_sheet", "name": "冰面", "level_mode": &"average"},
	{"a": &"light", "b": &"fire", "id": &"holy_flame", "name": "圣火", "level_mode": &"max"},
	{"a": &"dark", "b": &"poison", "id": &"dark_venom", "name": "暗毒", "level_mode": &"average"},
	{"a": &"poison", "b": &"blood", "id": &"toxic_blood", "name": "毒血", "level_mode": &"min",
		"self_damage": 2.0},
	{"a": &"ice", "b": &"blood", "id": &"frostbite_bleed", "name": "碎冰流血", "level_mode": &"average"},
	{"a": &"poison", "b": &"bone", "id": &"parasite_spur", "name": "寄生骨刺", "level_mode": &"average"},
	{"a": &"soul", "b": &"blood", "id": &"soul_drain", "name": "灵魂吸血", "level_mode": &"average"},
	{"a": &"soul", "b": &"dark", "id": &"soul_devour", "name": "灵魂吞噬", "level_mode": &"max"},
	{"a": &"soul", "b": &"machine", "id": &"soul_disorder", "name": "灵魂紊乱", "level_mode": &"min"},
	{"a": &"fire", "b": &"bone", "id": &"bone_char", "name": "骨炭", "level_mode": &"average"},
	{"a": &"blood", "b": &"bone", "id": &"blood_bone", "name": "血骨", "level_mode": &"average"},
	{"a": &"acid", "b": &"poison", "id": &"acid_venom", "name": "酸毒", "level_mode": &"average"},
	{"a": &"acid", "b": &"bone", "id": &"bone_dissolve", "name": "溶骨", "level_mode": &"average"},
	{"a": &"magnet", "b": &"bone", "id": &"magnetic_bone", "name": "磁骨", "level_mode": &"average"},
	{"a": &"magnet", "b": &"soul", "id": &"soul_magnet", "name": "灵魂吸附", "level_mode": &"average"},
	{"a": &"sand", "b": &"fire", "id": &"glass_forge", "name": "玻璃", "level_mode": &"max"},
	{"a": &"sand", "b": &"acid", "id": &"acid_etch", "name": "蚀沙", "level_mode": &"average"},
	{"a": &"sand", "b": &"bone", "id": &"sand_bone", "name": "沙骨", "level_mode": &"average"},
	{"a": &"light", "b": &"soul", "id": &"purify", "name": "净化", "level_mode": &"average"},
	{"a": &"light", "b": &"blood", "id": &"holy_blood", "name": "圣血", "level_mode": &"average"},
	{"a": &"dark", "b": &"blood", "id": &"dark_blood", "name": "暗血", "level_mode": &"average"},
]

## 冲突词条：命中即触发反噬（旧效果强度爆发、自伤、额外热量）。
const CONFLICTS: Array[Dictionary] = [
	{"a": &"fire", "b": &"ice", "name": "冰火反噬", "severity": 1.0},
	{"a": &"acid", "b": &"fire", "name": "酸火反噬", "severity": 1.0},
	{"a": &"soul", "b": &"machine", "name": "灵魂紊乱", "severity": 1.0},
	{"a": &"light", "b": &"dark", "name": "光暗湮灭", "severity": 1.0},
]

## 最小可玩原型要求的 5 种反应。
const PROTOTYPE_REACTION_IDS: Array[StringName] = [
	&"poison_smoke", &"steam_burst", &"magnetic_field", &"corrosive_sunder", &"skeleton_summon",
]

static var _reaction_table: Dictionary = {}
static var _conflict_table: Dictionary = {}

## 无序对键：a+b 与 b+a 命中同一条配置。
static func pair_key(a: StringName, b: StringName) -> String:
	var left: String = String(a)
	var right: String = String(b)
	return "%s+%s" % [left, right] if left <= right else "%s+%s" % [right, left]

static func _ensure_tables() -> void:
	if not _reaction_table.is_empty() or not _conflict_table.is_empty():
		return
	for entry: Dictionary in REACTIONS:
		_reaction_table[pair_key(entry["a"], entry["b"])] = entry
	for entry: Dictionary in CONFLICTS:
		_conflict_table[pair_key(entry["a"], entry["b"])] = entry

static func reaction_of(a: StringName, b: StringName) -> Dictionary:
	_ensure_tables()
	return _reaction_table.get(pair_key(a, b), {})

static func conflict_of(a: StringName, b: StringName) -> Dictionary:
	_ensure_tables()
	return _conflict_table.get(pair_key(a, b), {})

## 按 level_mode 求出反应等级：average 平均、max 最高、min 最低、a / b 取指定一侧。
static func reaction_level(mode: StringName, level_a: int, level_b: int) -> int:
	match mode:
		&"max":
			return maxi(level_a, level_b)
		&"min":
			return mini(level_a, level_b)
		&"a":
			return level_a
		&"b":
			return level_b
	return roundi((float(level_a) + float(level_b)) * 0.5)

static func all_reactions() -> Array[Dictionary]:
	return REACTIONS

static func all_conflicts() -> Array[Dictionary]:
	return CONFLICTS
