class_name TraitPoolResult
extends RefCounted

## 词条池计算输出：叠加后的词条、材料标签、命中的反应与冲突、最终效果标签。
## 只读数据；聚合修正值由这里的辅助函数算好，炼金流程直接取用。

var traits: Array[TraitInstance] = []
## 因词条池上限被裁掉的词条，供 UI 提示“已溢出”。
var dropped: Array[TraitInstance] = []
## 材料提供的额外标签（金属 / 机械 / 油 / 木…）。
var tags: Array[StringName] = []
## 命中的反应：[{id, name, level, a, b, mode}]
var reactions: Array[Dictionary] = []
## 命中的冲突：[{name, a, b, severity}]
var conflicts: Array[Dictionary] = []
## 最终效果标签：元素词条 id + 反应 id，排序去重，用于判定“相同组合”。
var effect_tags: Array[StringName] = []
## 素材中的最高品质。
var quality: int = 0
var pool_limit: int = AlchemyRules.POOL_LIMIT_FULL

func is_empty() -> bool:
	return traits.is_empty()

func has_trait(id: StringName) -> bool:
	return trait_of(id) != null

func trait_of(id: StringName) -> TraitInstance:
	for trait_instance: TraitInstance in traits:
		if trait_instance.id == id:
			return trait_instance
	return null

func has_tag(tag: StringName) -> bool:
	return tags.has(tag)

## 反应与冲突共用的标识符集合：元素词条 id + 材料标签。
func identifiers() -> Array[StringName]:
	var result: Array[StringName] = []
	for trait_instance: TraitInstance in traits:
		if trait_instance.category == TraitCategory.Kind.ELEMENT:
			result.append(trait_instance.id)
	result.append_array(tags)
	return result

func max_level() -> int:
	var level: int = 1
	for trait_instance: TraitInstance in traits:
		level = maxi(level, trait_instance.level)
	return level

func max_stacks() -> int:
	var stacks: int = 1
	for trait_instance: TraitInstance in traits:
		stacks = maxi(stacks, trait_instance.stacks)
	return stacks

## 按词条 id 求和某个数值键，缺失按 0 计。
func sum_of(trait_id: StringName, key: StringName) -> float:
	var trait_instance: TraitInstance = trait_of(trait_id)
	return trait_instance.value_of(key) if trait_instance != null else 0.0

## 持续时间修正：行为“持续”与修饰“挥发”叠加。
func duration_modifier() -> float:
	return sum_of(&"duration", &"duration") + sum_of(&"volatile", &"duration")

## 稳定修正：副作用减免词条同时小幅延长时长。
func stability_modifier() -> float:
	return sum_of(&"stability", &"duration")

## 活体修正。
func living_modifier() -> float:
	return sum_of(&"living", &"duration")

## 诅咒修正（同时提高强度与时长）。
func curse_modifier() -> float:
	return sum_of(&"curse", &"duration")

## 强度修正：挥发 / 诅咒 / 易碎带来的直接增伤。
func strength_modifier() -> float:
	return sum_of(&"volatile", &"power") + sum_of(&"curse", &"power") + sum_of(&"fragile", &"damage")

## 诅咒倍率：影响热量增加。
func curse_multiplier() -> float:
	return 1.0 + sum_of(&"curse", &"power")

## 过载词条带来的额外热量。
func overload_heat_bonus() -> float:
	return sum_of(&"overload", &"heat")

## 反应倍率：每个反应按自身等级倍率贡献加成。
func reaction_multiplier() -> float:
	var multiplier: float = 1.0
	for reaction: Dictionary in reactions:
		multiplier += 0.15 * AlchemyRules.level_multiplier(int(reaction.get("level", 1)))
	return multiplier

## 每秒自伤：活体 / 易碎 / 反噬冲突 / 毒血一类自带自伤的反应。
func self_damage_per_second() -> float:
	var damage: float = sum_of(&"living", &"self_damage") + sum_of(&"fragile", &"self_damage")
	for conflict: Dictionary in conflicts:
		damage += 2.0 * float(conflict.get("severity", 1.0))
	for reaction: Dictionary in reactions:
		damage += float(reaction.get("self_damage", 0.0))
	return damage

## 稳定词条对副作用（自伤 / 反噬）的减免，1.0 表示完全免疫。
func side_effect_reduction() -> float:
	var reduction: float = -sum_of(&"stability", &"side_effect")
	return clampf(reduction, 0.0, 1.0)
