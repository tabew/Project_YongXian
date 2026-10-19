class_name ItemTooltip
extends RefCounted

## 物品悬浮提示。武器额外显示基础伤害、当前附魔效果与伤害结算说明。

static func build(item: ItemData) -> String:
	if item == null:
		return ""

	var lines: Array[String] = []
	lines.append(item.name if not item.name.is_empty() else "物品")

	var base_attributes: Array[AlchemicalData] = item.alchemical_attribute

	if item is WeaponData:
		var weapon_data: WeaponData = item as WeaponData
		var definition: WeaponDefinition = weapon_data.weapon

		if definition != null:
			lines.append("基础伤害：%s" % _number(definition.damage))
			lines.append("暴击：%d%% ×%s" % [
				roundi(definition.critical_chance * 100.0),
				_number(definition.critical_multiplier),
			])

		if not base_attributes.is_empty():
			lines.append("")
			lines.append("炼金属性：")
			lines.append(_attribute_lines(base_attributes))

		lines.append("")
		var enchant_text: String = _enchant_lines(weapon_data)

		if enchant_text.is_empty():
			lines.append("附魔：无")
		else:
			lines.append("附魔效果：")
			lines.append(enchant_text)
			lines.append("")
			lines.append("附魔伤害独立结算，不乘武器伤害/暴击。")
	else:
		lines.append("")

		if base_attributes.is_empty():
			lines.append("无属性")
		else:
			lines.append("炼金属性：")
			lines.append(_attribute_lines(base_attributes))

	return "\n".join(lines)


static func _attribute_lines(attributes: Array[AlchemicalData]) -> String:
	var result: Array[String] = []

	for attribute: AlchemicalData in attributes:
		if attribute != null:
			result.append(_attribute_label(attribute, false))

	return "\n".join(result)


static func _enchant_lines(weapon_data: WeaponData) -> String:
	if weapon_data == null or weapon_data.weapon == null:
		return ""

	var result: Array[String] = []

	for attribute: AlchemicalData in weapon_data.weapon.enchant_attributes:
		if attribute != null:
			result.append("• " + _enchant_line(attribute))

	return "\n".join(result)


static func _enchant_line(attribute: AlchemicalData) -> String:
	var label: String = _attribute_label(attribute, true)

	if attribute is Explosive:
		var explosive: Explosive = attribute as Explosive
		var edge_knockback: float = explosive.knockback * 0.3
		return "%s：范围多目标，半径 %s，敌人伤害 %s，玩家伤害 %s；击退 %s→%s" % [
			label,
			_number(explosive.blast_radius()),
			_number(explosive.enemy_damage()),
			_number(explosive.player_damage_total()),
			_number(explosive.knockback),
			_number(edge_knockback),
		]

	if attribute is ContinuousHeal:
		var continuous_heal: ContinuousHeal = attribute as ContinuousHeal
		var buff_level: int = maxi(continuous_heal.level, 1)
		var instant_percent: int = roundi(ContinuousHeal.INSTANT_RATIO * 100.0)
		var buff: BuffData = continuous_heal.buff

		if buff == null or buff.tick_interval <= 0.0:
			return "%s（命中时对自己）：立即回复 %d%% 最大生命，并附加持续回复" % [
				label,
				instant_percent,
			]

		var per_tick: float = buff.heal_amount(buff_level)
		var ticks: int = maxi(1, roundi(buff.duration / maxf(buff.tick_interval, 0.001)))
		var total: float = per_tick * float(ticks)
		return "%s（命中时对自己）：立即回复 %d%% 最大生命；随后 %s 秒每秒回复 %s（共约 %s）" % [
			label,
			instant_percent,
			_number(buff.duration),
			_number(per_tick),
			_number(total),
		]

	if attribute is Holy:
		return "%s：当前作为武器附魔没有命中效果（只参与炼金反应）" % label

	if attribute is Heal:
		var heal: Heal = attribute as Heal
		return "%s：命中时回复 %d%% 最大生命" % [label, roundi(heal.heal_ratio() * 100.0)]

	var target_text: String = "持武器者" if attribute.enchant_target == AlchemicalData.EnchantTarget.WIELDER else "命中目标"
	return "%s：命中时对%s触发该属性效果" % [label, target_text]


static func _attribute_label(attribute: AlchemicalData, show_zero_level: bool) -> String:
	if attribute.level > 0 or show_zero_level:
		return "%s Lv%d" % [attribute.name, attribute.level]
	return attribute.name


static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.1f" % value