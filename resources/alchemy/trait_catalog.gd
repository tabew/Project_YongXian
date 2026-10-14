class_name TraitCatalog
extends RefCounted

## 词条配置表（唯一真源）。新增词条只改这里：id / 类别 / 名称 / 每级数值表。
## levels 的索引 0 对应等级 I，依次到 V；数值含义由各词条自己的键名决定。
## 反应与冲突判定只认元素词条 id 和材料标签，行为/触发/修饰词条不参与配对。

const TRAITS: Array[Dictionary] = [
	# ══ 元素词条（13）══
	{"id": &"fire", "category": TraitCategory.Kind.ELEMENT, "name": "火",
		"notes": "IV 起扩散 1~2 格，V 留火焰地面",
		"levels": [
			{"damage": 3.0, "ignite": 0.05, "duration": 2.0},
			{"damage": 5.0, "ignite": 0.10, "duration": 2.0},
			{"damage": 8.0, "ignite": 0.15, "duration": 3.0},
			{"damage": 12.0, "ignite": 0.20, "duration": 4.0, "spread": 1.0},
			{"damage": 18.0, "ignite": 0.25, "duration": 5.0, "spread": 2.0, "ground": true},
		]},
	{"id": &"poison", "category": TraitCategory.Kind.ELEMENT, "name": "毒",
		"notes": "IV 死亡扩散，V 留毒雾",
		"levels": [
			{"stacks": 1, "dps": 2.0, "duration": 3.0},
			{"stacks": 1, "dps": 3.0, "duration": 4.0},
			{"stacks": 1, "dps": 4.0, "duration": 5.0},
			{"stacks": 2, "dps": 6.0, "duration": 6.0, "death_spread": true},
			{"stacks": 3, "dps": 8.0, "duration": 8.0, "death_spread": true, "cloud": true},
		]},
	{"id": &"ice", "category": TraitCategory.Kind.ELEMENT, "name": "冰",
		"notes": "III 起冻结，V 冻结碎裂",
		"levels": [
			{"slow": 0.10, "duration": 2.0},
			{"slow": 0.15, "duration": 2.5},
			{"slow": 0.25, "duration": 3.0, "freeze_chance": 0.05, "freeze_duration": 1.0},
			{"slow": 0.35, "duration": 4.0, "freeze_chance": 0.10, "freeze_duration": 1.5},
			{"slow": 0.50, "duration": 5.0, "freeze_chance": 0.15, "freeze_duration": 2.0, "shatter": true},
		]},
	{"id": &"electric", "category": TraitCategory.Kind.ELEMENT, "name": "电",
		"notes": "III 起连锁，V 潮湿必感电",
		"levels": [
			{"damage": 3.0, "shock": 0.05, "duration": 2.0},
			{"damage": 5.0, "shock": 0.10, "duration": 2.0},
			{"damage": 8.0, "shock": 0.15, "duration": 3.0, "chain": 1},
			{"damage": 12.0, "shock": 0.20, "duration": 4.0, "chain": 2},
			{"damage": 18.0, "shock": 0.25, "duration": 5.0, "chain": 3, "wet_guarantee": true},
		]},
	{"id": &"acid", "category": TraitCategory.Kind.ELEMENT, "name": "酸",
		"notes": "III 腐蚀武器，IV 留酸池 1 格，V 留酸池 2 格可叠 2 层",
		"levels": [
			{"sunder": 0.10, "duration": 3.0},
			{"sunder": 0.15, "duration": 4.0},
			{"sunder": 0.25, "duration": 5.0, "corrode_weapon": true},
			{"sunder": 0.35, "duration": 6.0, "pool": 1},
			{"sunder": 0.50, "duration": 8.0, "pool": 2, "pool_stacks": 2},
		]},
	{"id": &"magnet", "category": TraitCategory.Kind.ELEMENT, "name": "磁",
		"notes": "II 起轻微拉拽，IV 拉拽 2 格磁化 3s，V 拉拽 3 格磁化 5s 金属互撞",
		"levels": [
			{"pull": 1.0},
			{"pull": 2.0, "drag": 1.0},
			{"pull": 3.0, "drag": 1.0},
			{"pull": 4.0, "drag": 2.0, "magnetize": 3.0},
			{"pull": 5.0, "drag": 3.0, "magnetize": 5.0, "metal_collide": true},
		]},
	{"id": &"soul", "category": TraitCategory.Kind.ELEMENT, "name": "灵魂",
		"notes": "III 起自动索敌，V 可爆炸",
		"levels": [
			{"spawn_chance": 0.05, "count": 1},
			{"spawn_chance": 0.10, "count": 1},
			{"spawn_chance": 0.15, "count": 1, "homing": true},
			{"spawn_chance": 0.20, "count": 2, "homing": true},
			{"spawn_chance": 0.25, "count": 3, "homing": true, "explode": true},
		]},
	{"id": &"bone", "category": TraitCategory.Kind.ELEMENT, "name": "骨",
		"notes": "III 起穿刺，IV 留骨刺，V 可召唤骷髅",
		"levels": [
			{"bounce_chance": 0.05, "shards": 1},
			{"bounce_chance": 0.10, "shards": 1},
			{"bounce_chance": 0.15, "shards": 2, "pierce": true},
			{"bounce_chance": 0.20, "shards": 3, "pierce": true, "spikes": true},
			{"bounce_chance": 0.25, "shards": 4, "pierce": true, "spikes": true, "skeleton": true},
		]},
	{"id": &"blood", "category": TraitCategory.Kind.ELEMENT, "name": "血",
		"notes": "III 起暴击回复，V 溢出变护盾（上限 20，持续 10s）",
		"levels": [
			{"kill_heal": 1.0},
			{"kill_heal": 2.0},
			{"kill_heal": 3.0, "crit_heal": 1.0},
			{"kill_heal": 4.0, "crit_heal": 2.0},
			{"kill_heal": 6.0, "crit_heal": 3.0, "shield_cap": 20.0, "shield_duration": 10.0},
		]},
	{"id": &"wind", "category": TraitCategory.Kind.ELEMENT, "name": "风",
		"notes": "III 起攻速提升，V 留尘暴",
		"levels": [
			{"knockback": 0.5},
			{"knockback": 1.0},
			{"knockback": 1.5, "attack_speed": 0.05},
			{"knockback": 2.0, "attack_speed": 0.10},
			{"knockback": 3.0, "attack_speed": 0.15, "dust_storm": true},
		]},
	{"id": &"sand", "category": TraitCategory.Kind.ELEMENT, "name": "沙",
		"notes": "IV 范围 1 格，V 范围 2 格",
		"levels": [
			{"blind": 0.05, "duration": 1.0},
			{"blind": 0.10, "duration": 1.5},
			{"blind": 0.15, "duration": 2.0},
			{"blind": 0.20, "duration": 3.0, "radius": 1.0},
			{"blind": 0.25, "duration": 4.0, "radius": 2.0},
		]},
	{"id": &"light", "category": TraitCategory.Kind.ELEMENT, "name": "光",
		"notes": "III 起致盲",
		"levels": [
			{"vs_dark": 0.10},
			{"vs_dark": 0.20},
			{"vs_dark": 0.30, "blind_duration": 1.0},
			{"vs_dark": 0.40, "blind_duration": 2.0},
			{"vs_dark": 0.60, "blind_duration": 3.0},
		]},
	{"id": &"dark", "category": TraitCategory.Kind.ELEMENT, "name": "暗",
		"notes": "III 起吸血",
		"levels": [
			{"vs_light": 0.10},
			{"vs_light": 0.20},
			{"vs_light": 0.30, "lifesteal": 0.05},
			{"vs_light": 0.40, "lifesteal": 0.10},
			{"vs_light": 0.60, "lifesteal": 0.15},
		]},

	# ══ 行为词条（9）══
	{"id": &"explode", "category": TraitCategory.Kind.BEHAVIOR, "name": "爆炸",
		"notes": "V 可连锁",
		"levels": [
			{"chance": 0.10, "radius": 1.0, "damage": 0.50},
			{"chance": 0.15, "radius": 1.5, "damage": 0.60},
			{"chance": 0.20, "radius": 2.0, "damage": 0.70},
			{"chance": 0.25, "radius": 2.5, "damage": 0.80},
			{"chance": 0.30, "radius": 3.0, "damage": 1.00, "chain": true},
		]},
	{"id": &"chain", "category": TraitCategory.Kind.BEHAVIOR, "name": "连锁",
		"notes": "V 可回弹",
		"levels": [
			{"chance": 0.10, "targets": 1, "damage": 0.50},
			{"chance": 0.15, "targets": 1, "damage": 0.60},
			{"chance": 0.20, "targets": 2, "damage": 0.70},
			{"chance": 0.25, "targets": 3, "damage": 0.80},
			{"chance": 0.30, "targets": 4, "damage": 1.00, "rebound": true},
		]},
	{"id": &"whirl", "category": TraitCategory.Kind.BEHAVIOR, "name": "回旋",
		"notes": "III 起回旋伤害，V 可二次回旋",
		"levels": [
			{"chance": 0.20},
			{"chance": 0.30},
			{"chance": 0.40, "damage": 0.60},
			{"chance": 0.50, "damage": 0.80},
			{"chance": 0.60, "damage": 1.00, "double": true},
		]},
	{"id": &"pierce", "category": TraitCategory.Kind.BEHAVIOR, "name": "穿透",
		"notes": "pierce = -1 表示无限穿透",
		"levels": [
			{"pierce": 1, "falloff": -0.30},
			{"pierce": 1, "falloff": -0.20},
			{"pierce": 2, "falloff": -0.15},
			{"pierce": 3, "falloff": -0.10},
			{"pierce": -1, "falloff": -0.05},
		]},
	{"id": &"bounce", "category": TraitCategory.Kind.BEHAVIOR, "name": "弹射",
		"notes": "V 可弹墙",
		"levels": [
			{"bounces": 1, "damage": 0.50},
			{"bounces": 1, "damage": 0.60},
			{"bounces": 2, "damage": 0.70},
			{"bounces": 3, "damage": 0.80},
			{"bounces": 4, "damage": 1.00, "wall_bounce": true},
		]},
	{"id": &"spread", "category": TraitCategory.Kind.BEHAVIOR, "name": "扩散",
		"notes": "V 可穿墙",
		"levels": [
			{"radius": 1.0},
			{"radius": 1.5},
			{"radius": 2.0},
			{"radius": 2.5},
			{"radius": 3.0, "through_walls": true},
		]},
	{"id": &"duration", "category": TraitCategory.Kind.BEHAVIOR, "name": "持续",
		"notes": "V 可刷新",
		"levels": [
			{"duration": 0.20},
			{"duration": 0.30},
			{"duration": 0.45},
			{"duration": 0.60},
			{"duration": 0.80, "refresh": true},
		]},
	{"id": &"summon", "category": TraitCategory.Kind.BEHAVIOR, "name": "召唤",
		"notes": "V 可爆炸",
		"levels": [
			{"chance": 0.05, "count": 1, "duration": 3.0},
			{"chance": 0.10, "count": 1, "duration": 5.0},
			{"chance": 0.15, "count": 1, "duration": 5.0},
			{"chance": 0.20, "count": 2, "duration": 8.0},
			{"chance": 0.25, "count": 3, "duration": 12.0, "explode": true},
		]},
	{"id": &"transform", "category": TraitCategory.Kind.BEHAVIOR, "name": "变形",
		"notes": "III 可切换形态，IV 附带元素，V 自由切换无冷却",
		"levels": [
			{"radius": 0.10},
			{"radius": 0.20},
			{"radius": 0.30, "form_switch": true},
			{"radius": 0.40, "form_switch": true, "element_infuse": true},
			{"radius": 0.50, "form_switch": true, "element_infuse": true, "free_switch": true},
		]},

	# ══ 触发词条（8）══
	{"id": &"on_hit", "category": TraitCategory.Kind.TRIGGER, "name": "命中",
		"notes": "I 为基础触发，II~V 追加触发概率",
		"levels": [{"bonus": 0.0}, {"bonus": 0.10}, {"bonus": 0.20}, {"bonus": 0.30}, {"bonus": 0.40}]},
	{"id": &"on_crit", "category": TraitCategory.Kind.TRIGGER, "name": "暴击",
		"notes": "I 为基础触发，II~V 追加暴击率",
		"levels": [{"bonus": 0.0}, {"bonus": 0.10}, {"bonus": 0.20}, {"bonus": 0.30}, {"bonus": 0.40}]},
	{"id": &"on_kill", "category": TraitCategory.Kind.TRIGGER, "name": "击杀",
		"notes": "I 为基础触发，II~V 追加范围",
		"levels": [{"bonus": 0.0}, {"bonus": 0.10}, {"bonus": 0.20}, {"bonus": 0.30}, {"bonus": 0.40}]},
	{"id": &"on_block", "category": TraitCategory.Kind.TRIGGER, "name": "格挡",
		"notes": "I 为基础触发，II~V 追加存储",
		"levels": [{"bonus": 0.0}, {"bonus": 0.10}, {"bonus": 0.20}, {"bonus": 0.30}, {"bonus": 0.40}]},
	{"id": &"on_dash", "category": TraitCategory.Kind.TRIGGER, "name": "冲刺",
		"notes": "I 为基础触发，II~V 追加伤害",
		"levels": [{"bonus": 0.0}, {"bonus": 0.10}, {"bonus": 0.20}, {"bonus": 0.30}, {"bonus": 0.40}]},
	{"id": &"backstab", "category": TraitCategory.Kind.TRIGGER, "name": "背刺",
		"notes": "背后命中追加伤害",
		"levels": [{"bonus": 0.0}, {"bonus": 0.20}, {"bonus": 0.40}, {"bonus": 0.60}, {"bonus": 1.00}]},
	{"id": &"charge", "category": TraitCategory.Kind.TRIGGER, "name": "蓄力",
		"notes": "蓄力后追加速度",
		"levels": [{"bonus": 0.0}, {"bonus": 0.10}, {"bonus": 0.20}, {"bonus": 0.30}, {"bonus": 0.50}]},
	{"id": &"combo", "category": TraitCategory.Kind.TRIGGER, "name": "连击",
		"notes": "第 N 下攻击触发",
		"levels": [{"hits": 3}, {"hits": 4}, {"hits": 5}, {"hits": 6}, {"hits": 8}]},

	# ══ 修饰词条（8）══
	{"id": &"stability", "category": TraitCategory.Kind.MODIFIER, "name": "稳定",
		"notes": "V 免疫副作用",
		"levels": [
			{"side_effect": -0.20, "duration": 0.10},
			{"side_effect": -0.35, "duration": 0.15},
			{"side_effect": -0.50, "duration": 0.20},
			{"side_effect": -0.70, "duration": 0.30},
			{"side_effect": -1.00, "duration": 0.40, "immune": true},
		]},
	{"id": &"volatile", "category": TraitCategory.Kind.MODIFIER, "name": "挥发",
		"notes": "时长换强度",
		"levels": [
			{"duration": -0.20, "power": 0.20},
			{"duration": -0.25, "power": 0.35},
			{"duration": -0.30, "power": 0.50},
			{"duration": -0.35, "power": 0.70},
			{"duration": -0.40, "power": 1.00},
		]},
	{"id": &"living", "category": TraitCategory.Kind.MODIFIER, "name": "活体",
		"notes": "IV 击杀回血，V 可分裂",
		"levels": [
			{"duration": 0.50, "self_damage": 1.0},
			{"duration": 0.75, "self_damage": 1.0},
			{"duration": 1.00, "self_damage": 2.0},
			{"duration": 1.50, "self_damage": 2.0, "kill_heal": true},
			{"duration": 2.00, "self_damage": 3.0, "kill_heal": true, "split": true},
		]},
	{"id": &"curse", "category": TraitCategory.Kind.MODIFIER, "name": "诅咒",
		"notes": "强度换随机负面，V 不可移除；同时按 +30%~+120% 延长时长",
		"levels": [
			{"power": 0.30, "duration": 0.30, "curses": 1},
			{"power": 0.50, "duration": 0.50, "curses": 1},
			{"power": 0.80, "duration": 0.80, "curses": 2},
			{"power": 1.20, "duration": 1.00, "curses": 2},
			{"power": 2.00, "duration": 1.20, "curses": 3, "permanent": true},
		]},
	{"id": &"sharp", "category": TraitCategory.Kind.MODIFIER, "name": "锐利",
		"notes": "III 起追加暴击伤害",
		"levels": [
			{"crit_chance": 0.05},
			{"crit_chance": 0.10},
			{"crit_chance": 0.15, "crit_damage": 0.10},
			{"crit_chance": 0.20, "crit_damage": 0.20},
			{"crit_chance": 0.30, "crit_damage": 0.40},
		]},
	{"id": &"heavy", "category": TraitCategory.Kind.MODIFIER, "name": "沉重",
		"notes": "III 起范围提升，V 地震",
		"levels": [
			{"knockback": 0.20, "attack_speed": -0.05},
			{"knockback": 0.35, "attack_speed": -0.05},
			{"knockback": 0.50, "attack_speed": -0.10, "radius": 0.10},
			{"knockback": 0.70, "attack_speed": -0.10, "radius": 0.20},
			{"knockback": 1.00, "attack_speed": -0.15, "radius": 0.30, "earthquake": true},
		]},
	{"id": &"fragile", "category": TraitCategory.Kind.MODIFIER, "name": "易碎",
		"notes": "IV 碎裂弹射，V 可重组",
		"levels": [
			{"damage": 0.20, "self_damage": 1.0},
			{"damage": 0.35, "self_damage": 1.0},
			{"damage": 0.50, "self_damage": 2.0},
			{"damage": 0.70, "self_damage": 2.0, "shatter_bounce": true},
			{"damage": 1.00, "self_damage": 3.0, "shatter_bounce": true, "reassemble": true},
		]},
	{"id": &"overload", "category": TraitCategory.Kind.MODIFIER, "name": "过载",
		"notes": "每次炼金额外加热量，V 可突破热量上限",
		"levels": [
			{"attack_speed": 0.10, "heat": 5.0},
			{"attack_speed": 0.20, "heat": 5.0},
			{"attack_speed": 0.30, "heat": 10.0},
			{"attack_speed": 0.40, "heat": 10.0},
			{"attack_speed": 0.60, "heat": 15.0, "break_heat_cap": true},
		]},
]

## 最小可玩原型的 12 个词条。
const PROTOTYPE_IDS: Array[StringName] = [
	&"fire", &"poison", &"ice", &"electric", &"acid", &"bone", &"magnet",
	&"explode", &"chain", &"duration", &"spread", &"stability",
]

static var _by_id: Dictionary = {}

static func _ensure_table() -> void:
	if not _by_id.is_empty():
		return
	for entry: Dictionary in TRAITS:
		_by_id[entry["id"]] = entry

static func has_trait(id: StringName) -> bool:
	_ensure_table()
	return _by_id.has(id)

static func definition_of(id: StringName) -> Dictionary:
	_ensure_table()
	return _by_id.get(id, {})

static func create(id: StringName, level: int = 1, stacks: int = 1) -> TraitInstance:
	_ensure_table()
	if not _by_id.has(id):
		return null
	return TraitInstance.create(_by_id[id], level, stacks)

static func all_ids() -> Array[StringName]:
	_ensure_table()
	var ids: Array[StringName] = []
	for id: StringName in _by_id:
		ids.append(id)
	return ids

static func ids_of_category(category: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for entry: Dictionary in TRAITS:
		if int(entry.get("category", -1)) == category:
			result.append(entry["id"])
	return result

static func display_name_of(id: StringName) -> String:
	return String(definition_of(id).get("name", "未知词条"))
