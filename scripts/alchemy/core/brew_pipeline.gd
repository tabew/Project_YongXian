class_name BrewPipeline
extends RefCounted

## 材料 → 词条池 → 炼金组合（纯逻辑，可单元测试）。
## 伤害 / 时长公式统一走 AlchemyRules，这里只把池子里的修正项聚合起来。

static func evaluate(materials: Array[AlchemyMaterial], limit: int = AlchemyRules.POOL_LIMIT_FULL) -> BrewCombo:
	return from_pool(TraitPool.build(materials, limit))

static func from_pool(pool: TraitPoolResult) -> BrewCombo:
	var combo: BrewCombo = BrewCombo.new()
	combo.traits = pool.traits
	combo.reactions = pool.reactions
	combo.conflicts = pool.conflicts
	combo.effect_tags = pool.effect_tags
	combo.quality = pool.quality
	combo.strength_modifier = pool.strength_modifier()
	# 稳定词条按比例削减自伤；V 级免疫即减免 100%。
	combo.self_damage = pool.self_damage_per_second() * (1.0 - pool.side_effect_reduction())
	combo.overload_heat_bonus = pool.overload_heat_bonus()
	combo.curse_multiplier = pool.curse_multiplier()
	combo.base_duration = AlchemyRules.final_duration(
		pool.duration_modifier(),
		pool.stability_modifier(),
		pool.living_modifier(),
		pool.curse_modifier(),
		pool.quality)
	combo.power = _power(pool)
	return combo

## 以基础伤害 1.0 代入最终伤害公式，得到相对倍率，再叠加强度修正。
static func _power(pool: TraitPoolResult) -> float:
	var base: float = AlchemyRules.final_damage(
		1.0, pool.max_level(), pool.max_stacks(), pool.duration_modifier(), pool.reaction_multiplier(), pool.quality)
	return base * (1.0 + pool.strength_modifier())
