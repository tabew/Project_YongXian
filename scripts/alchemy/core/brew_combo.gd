class_name BrewCombo
extends RefCounted

## 单一激活炼金组合：一次炼金产出的最终效果快照。
## effect_tags 决定“相同组合”（时间叠加）还是“不同组合”（替换 + 旧效果爆发）。

var effect_tags: Array[StringName] = []
var traits: Array[TraitInstance] = []
var reactions: Array[Dictionary] = []
var conflicts: Array[Dictionary] = []
var quality: int = 0
## 相对武器基础伤害的倍率。
var power: float = 1.0
## 经全部修正后的持续时长（秒）。
var base_duration: float = AlchemyRules.BASE_DURATION
var strength_modifier: float = 0.0
## 每秒自伤（已扣掉稳定减免）。
var self_damage: float = 0.0
var overload_heat_bonus: float = 0.0
var curse_multiplier: float = 1.0

func is_empty() -> bool:
	return effect_tags.is_empty()

## 组合签名：效果标签按序拼接，用来判定两次炼金是不是同一个组合。
func signature() -> String:
	var parts: PackedStringArray = []
	for tag: StringName in effect_tags:
		parts.append(String(tag))
	return "|".join(parts)

func matches(other: BrewCombo) -> bool:
	return other != null and signature() == other.signature()

func describe() -> String:
	if is_empty():
		return "无效果"
	var parts: PackedStringArray = []
	for tag: StringName in effect_tags:
		parts.append(String(tag))
	return " + ".join(parts)

func duplicate_combo() -> BrewCombo:
	var copy: BrewCombo = BrewCombo.new()
	copy.effect_tags = effect_tags.duplicate()
	copy.traits = []
	for trait_instance: TraitInstance in traits:
		copy.traits.append(trait_instance.duplicate_instance())
	copy.reactions = reactions.duplicate(true)
	copy.conflicts = conflicts.duplicate(true)
	copy.quality = quality
	copy.power = power
	copy.base_duration = base_duration
	copy.strength_modifier = strength_modifier
	copy.self_damage = self_damage
	copy.overload_heat_bonus = overload_heat_bonus
	copy.curse_multiplier = curse_multiplier
	return copy

## 替换爆发：旧效果以 50% 强度爆发一次。
func burst_power(ratio: float = AlchemyRules.REPLACEMENT_BURST_RATIO) -> float:
	return power * ratio
