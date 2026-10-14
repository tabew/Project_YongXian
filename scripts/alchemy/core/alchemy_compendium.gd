class_name AlchemyCompendium
extends RefCounted

## 词条图鉴：记录已发现的词条 / 反应 / 冲突 / 材料，并给出完成度。
## 纯数据、不依赖场景树；可 to_dict / from_dict 存档。
##
## 分类与配置表一一对应：元素 / 行为 / 触发 / 修饰来自 TraitCatalog，反应来自 ReactionCatalog。
## 未发现的条目一律显示「？？？」，已发现的显示已见最高等级与该等级的数值摘要。

## 未发现条目的占位文本。
const UNKNOWN_TEXT: String = "？？？"

## 图鉴分类（比 TraitCategory 多出反应 / 冲突 / 材料三栏）。
enum Section { ELEMENT, BEHAVIOR, TRIGGER, MODIFIER, REACTION, CONFLICT, MATERIAL }

const SECTION_NAMES: Dictionary = {
	Section.ELEMENT: "元素",
	Section.BEHAVIOR: "行为",
	Section.TRIGGER: "触发",
	Section.MODIFIER: "修饰",
	Section.REACTION: "反应",
	Section.CONFLICT: "冲突",
	Section.MATERIAL: "材料",
}

## 数值键 → 中文标签；缺失时直接显示键名，保证新增词条不会漏。
const KEY_LABELS: Dictionary = {
	&"damage": "伤害", &"dps": "每秒伤害", &"ignite": "点燃", &"duration": "时长",
	&"stacks": "叠层", &"slow": "减速", &"freeze_chance": "冻结率", &"freeze_duration": "冻结",
	&"shock": "感电", &"chain": "连锁", &"sunder": "破甲", &"pool": "酸池", &"pool_stacks": "酸池层数",
	&"pull": "吸附", &"drag": "拉拽", &"magnetize": "磁化", &"spawn_chance": "生成率", &"count": "数量",
	&"kill_heal": "击杀回复", &"crit_heal": "暴击回复", &"shield_cap": "护盾上限",
	&"shield_duration": "护盾时长", &"knockback": "击退", &"attack_speed": "攻速", &"blind": "致盲",
	&"blind_duration": "致盲时长", &"vs_dark": "对暗增伤", &"vs_light": "对光增伤", &"lifesteal": "吸血",
	&"chance": "触发", &"radius": "范围", &"targets": "目标", &"bounces": "弹射", &"bounce_chance": "弹射率",
	&"pierce": "穿透", &"falloff": "伤害衰减", &"bonus": "追加", &"hits": "攻击次数",
	&"crit_chance": "暴击率", &"crit_damage": "暴击伤害", &"power": "强度", &"heat": "额外热量",
	&"curses": "随机负面", &"side_effect": "副作用", &"self_damage": "自伤", &"spread": "扩散",
	&"shards": "骨片", &"spikes": "骨刺",
}

## 以百分比显示的 0~1 比值键（duration 因词条而异，单独处理）。
const PERCENT_KEYS: Array[StringName] = [
	&"ignite", &"shock", &"slow", &"sunder", &"blind", &"lifesteal", &"crit_chance", &"crit_heal",
	&"bounce_chance", &"spawn_chance", &"freeze_chance", &"side_effect", &"falloff", &"chance",
	&"bonus", &"power", &"knockback", &"vs_dark", &"vs_light", &"attack_speed",
]

## 布尔标志键 → 说明文本。
const FLAG_LABELS: Dictionary = {
	&"ground": "留火焰地面", &"cloud": "留毒雾", &"shatter": "冻结碎裂", &"corrode_weapon": "腐蚀武器",
	&"death_spread": "死亡扩散", &"wet_guarantee": "潮湿必感电", &"metal_collide": "金属互撞",
	&"homing": "自动索敌", &"wall_bounce": "可弹墙", &"through_walls": "可穿墙", &"refresh": "可刷新",
	&"explode": "可爆炸", &"form_switch": "可切换形态", &"element_infuse": "附带元素",
	&"free_switch": "自由切换", &"immune": "免疫副作用", &"kill_heal": "击杀回血", &"split": "可分裂",
	&"permanent": "不可移除", &"reassemble": "可重聚", &"shatter_bounce": "碎裂弹射", &"double": "二次",
	&"earthquake": "引发地震", &"dust_storm": "留尘暴", &"spikes": "留骨刺", &"skeleton": "召唤骷髅",
	&"break_heat_cap": "突破热量上限",
}

## 材料标签 → 中文名；反应配对里标签和元素词条同等重要。
const TAG_LABELS: Dictionary = {
	&"metal": "金属", &"machine": "机械", &"oil": "油", &"wood": "木", &"water": "水",
	&"phase": "相位", &"time": "时间", &"space": "空间", &"random": "随机", &"haste": "急速",
	&"self_harm": "自伤", &"reflect": "反射", &"lifesteal": "吸血",
}

## 反应配对里的标识符显示名：先查元素词条，再查材料标签，最后退回原始 id。
static func identifier_name(id: StringName) -> String:
	var definition: Dictionary = TraitCatalog.definition_of(id)
	if not definition.is_empty():
		return String(definition.get("name", id))
	return String(TAG_LABELS.get(id, id))

## 已发现词条：id → 已见到的最高等级。
var discovered_traits: Dictionary = {}
## 已发现反应 id 集合。
var discovered_reactions: Dictionary = {}
## 已发现冲突名集合。
var discovered_conflicts: Dictionary = {}
## 已发现材料 id 集合。
var discovered_materials: Dictionary = {}

## ── 记录发现 ────────────────────────────────────────────────────────────

## 记录词条；返回是否刷新了记录（首次发现或更高等级）。
func discover_trait(id: StringName, level: int = 1) -> bool:
	if id == &"":
		return false
	var clamped: int = AlchemyRules.clamp_level(level)
	var seen: int = int(discovered_traits.get(id, 0))
	if clamped <= seen:
		return false
	discovered_traits[id] = clamped
	return true

func discover_reaction(id: StringName) -> bool:
	if id == &"" or discovered_reactions.has(id):
		return false
	discovered_reactions[id] = true
	return true

func discover_conflict(name: String) -> bool:
	if name.is_empty() or discovered_conflicts.has(name):
		return false
	discovered_conflicts[name] = true
	return true

func discover_material(id: int) -> bool:
	if id < 0 or discovered_materials.has(id):
		return false
	discovered_materials[id] = true
	return true

## 炼金成功时一次性登记：材料 + 词条 + 反应 + 冲突。返回是否有新发现。
func discover_combo(combo: BrewCombo, materials: Array[AlchemyMaterial] = []) -> bool:
	var changed: bool = false
	for material: AlchemyMaterial in materials:
		if material != null and discover_material(material.id):
			changed = true
	if combo == null:
		return changed
	for trait_instance: TraitInstance in combo.traits:
		if discover_trait(trait_instance.id, trait_instance.level):
			changed = true
	for reaction: Dictionary in combo.reactions:
		if discover_reaction(reaction.get("id", &"")):
			changed = true
	for conflict: Dictionary in combo.conflicts:
		if discover_conflict(String(conflict.get("name", ""))):
			changed = true
	return changed

## ── 查询 ────────────────────────────────────────────────────────────────

func is_trait_discovered(id: StringName) -> bool:
	return int(discovered_traits.get(id, 0)) > 0

## 已见最高等级；未发现返回 0。
func trait_level_seen(id: StringName) -> int:
	return int(discovered_traits.get(id, 0))

func is_reaction_discovered(id: StringName) -> bool:
	return discovered_reactions.has(id)

func is_material_discovered(id: int) -> bool:
	return discovered_materials.has(id)

## 图鉴总条目数：全部词条 + 全部反应（完成度以此为分母）。
func total_entries() -> int:
	return TraitCatalog.TRAITS.size() + ReactionCatalog.REACTIONS.size()

## 已发现条目数：只统计仍存在于配置表里的 id，避免脏数据虚增完成度。
func discovered_count() -> int:
	var count: int = 0
	for definition: Dictionary in TraitCatalog.TRAITS:
		if is_trait_discovered(definition.get("id", &"")):
			count += 1
	for reaction: Dictionary in ReactionCatalog.REACTIONS:
		if discovered_reactions.has(reaction.get("id", &"")):
			count += 1
	return count

func completion_ratio() -> float:
	var total: int = total_entries()
	return float(discovered_count()) / float(total) if total > 0 else 0.0

## 某一栏的全部条目视图；未发现的 name 为「？？？」。
func entries_of(section: int) -> Array[Dictionary]:
	match section:
		Section.ELEMENT:
			return _trait_entries(TraitCategory.Kind.ELEMENT)
		Section.BEHAVIOR:
			return _trait_entries(TraitCategory.Kind.BEHAVIOR)
		Section.TRIGGER:
			return _trait_entries(TraitCategory.Kind.TRIGGER)
		Section.MODIFIER:
			return _trait_entries(TraitCategory.Kind.MODIFIER)
		Section.REACTION:
			return _reaction_entries()
		Section.CONFLICT:
			return _conflict_entries()
		Section.MATERIAL:
			return _material_entries()
	return []

func section_name(section: int) -> String:
	return String(SECTION_NAMES.get(section, "未知"))

## 全部词条栏（元素 / 行为 / 触发 / 修饰）的扁平列表，供一次性渲染。
func trait_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind: int in TraitCategory.all_kinds():
		result.append_array(_trait_entries(kind))
	return result

## 把某个词条在某等级的效果渲染成一行可读文本。
static func describe_level(definition: Dictionary, level: int) -> String:
	var levels: Array = definition.get("levels", [])
	if levels.is_empty():
		return ""
	var index: int = clampi(level, 1, levels.size()) - 1
	var entry: Variant = levels[index]
	if not (entry is Dictionary):
		return ""
	var parts: PackedStringArray = []
	for key: Variant in (entry as Dictionary).keys():
		var name: StringName = StringName(key)
		var value: Variant = (entry as Dictionary)[key]
		if value is bool:
			if value:
				parts.append(String(FLAG_LABELS.get(name, name)))
			continue
		parts.append("%s %s" % [_label_of(name), _format_value(name, value)])
	return " · ".join(parts)

static func _label_of(key: StringName) -> String:
	return String(KEY_LABELS.get(key, key))

## duration 既可能是「秒」也可能是「修正比例」，按数值大小自动选择写法。
static func _format_value(key: StringName, value: Variant) -> String:
	var number: float = float(value)
	if key == &"duration":
		return "%.0fs" % number if absf(number) >= 1.0 else "%+.0f%%" % (number * 100.0)
	if PERCENT_KEYS.has(key):
		return "%+.0f%%" % (number * 100.0) if number < 0.0 else "%.0f%%" % (number * 100.0)
	if is_equal_approx(number, roundf(number)):
		return "%d" % int(roundf(number))
	return "%.2f" % number

## ── 存档 ────────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var traits: Dictionary = {}
	for id: StringName in discovered_traits:
		traits[String(id)] = int(discovered_traits[id])
	var reactions: Array[String] = []
	for id: StringName in discovered_reactions:
		reactions.append(String(id))
	var conflicts: Array[String] = []
	for name: String in discovered_conflicts:
		conflicts.append(name)
	var materials: Array[int] = []
	for id: int in discovered_materials:
		materials.append(id)
	return {
		"traits": traits,
		"reactions": reactions,
		"conflicts": conflicts,
		"materials": materials,
	}

func from_dict(data: Dictionary) -> void:
	discovered_traits.clear()
	discovered_reactions.clear()
	discovered_conflicts.clear()
	discovered_materials.clear()
	for key: Variant in data.get("traits", {}):
		discovered_traits[StringName(key)] = int((data["traits"] as Dictionary)[key])
	for id: Variant in data.get("reactions", []):
		discovered_reactions[StringName(id)] = true
	for name: Variant in data.get("conflicts", []):
		discovered_conflicts[String(name)] = true
	for id: Variant in data.get("materials", []):
		discovered_materials[int(id)] = true

func reset() -> void:
	discovered_traits.clear()
	discovered_reactions.clear()
	discovered_conflicts.clear()
	discovered_materials.clear()

## ── 内部 ────────────────────────────────────────────────────────────────

func _trait_entries(kind: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in TraitCatalog.TRAITS:
		if int(definition.get("category", -1)) != kind:
			continue
		var id: StringName = definition.get("id", &"")
		var seen: int = trait_level_seen(id)
		var discovered: bool = seen > 0
		result.append({
			"id": id,
			"category": kind,
			"discovered": discovered,
			"level": seen,
			"name": String(definition.get("name", "")) if discovered else UNKNOWN_TEXT,
			"notes": String(definition.get("notes", "")) if discovered else "",
			"effect": describe_level(definition, seen) if discovered else "",
		})
	return result

func _reaction_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reaction: Dictionary in ReactionCatalog.REACTIONS:
		var id: StringName = reaction.get("id", &"")
		var discovered: bool = is_reaction_discovered(id)
		result.append({
			"id": id,
			"discovered": discovered,
			"name": String(reaction.get("name", "")) if discovered else UNKNOWN_TEXT,
			"a": reaction.get("a", &""),
			"b": reaction.get("b", &""),
		})
	return result

func _conflict_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for conflict: Dictionary in ReactionCatalog.CONFLICTS:
		var name: String = String(conflict.get("name", ""))
		var discovered: bool = discovered_conflicts.has(name)
		result.append({
			"name": name if discovered else UNKNOWN_TEXT,
			"discovered": discovered,
			"a": conflict.get("a", &""),
			"b": conflict.get("b", &""),
			"severity": float(conflict.get("severity", 1.0)),
		})
	return result

func _material_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in MaterialCatalog.all_ids():
		var definition: Dictionary = MaterialCatalog.definition_of(id)
		var discovered: bool = is_material_discovered(id)
		result.append({
			"id": id,
			"discovered": discovered,
			"name": String(definition.get("name", "")) if discovered else UNKNOWN_TEXT,
			"quality": int(definition.get("quality", 0)),
		})
	return result
