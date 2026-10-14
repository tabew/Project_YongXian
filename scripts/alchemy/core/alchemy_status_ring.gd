class_name AlchemyStatusRing
extends RefCounted

## 武器旁常驻状态环的纯逻辑：把「当前炼金组合 + 剩余时长比例」折算成
## 图标颜色 / 倒计时弧角度 / 是否显示，UI 只负责画。
##
## 放在 core 里是为了可单测：颜色与弧度的换算不依赖场景树。

## 13 元素 → 图标颜色；没有元素时用中性灰。
const ELEMENT_COLORS: Dictionary = {
	&"fire": Color("ff7a3c"),
	&"poison": Color("8fd14f"),
	&"ice": Color("6fd8ff"),
	&"electric": Color("ffd84a"),
	&"acid": Color("c6ff4a"),
	&"magnet": Color("ff6fd8"),
	&"soul": Color("a98cff"),
	&"bone": Color("e6e0c8"),
	&"blood": Color("ff4a5e"),
	&"wind": Color("b8f0e0"),
	&"sand": Color("e0c07a"),
	&"light": Color("fff4c2"),
	&"dark": Color("7a5cff"),
}
## 没有激活组合时的图标色。
const IDLE_COLOR: Color = Color("5a6069")
## 倒计时环的起始角（12 点方向）。
const START_ANGLE: float = -PI * 0.5


## 组合里的主导元素：等级最高的元素词条，等级相同取先出现的那个。
## 没有元素词条时返回空 StringName。
static func dominant_element(combo: BrewCombo) -> StringName:
	if combo == null:
		return &""
	var best_id: StringName = &""
	var best_level: int = 0
	for trait_instance: TraitInstance in combo.traits:
		if trait_instance.category != TraitCategory.Kind.ELEMENT:
			continue
		if trait_instance.level > best_level:
			best_level = trait_instance.level
			best_id = trait_instance.id
	return best_id


## 图标颜色：按主导元素取色，没有元素时退回中性色。
static func effect_color(combo: BrewCombo) -> Color:
	var element: StringName = dominant_element(combo)
	if element == &"":
		return IDLE_COLOR
	return ELEMENT_COLORS.get(element, IDLE_COLOR)


## 组合是否处于生效状态（有组合且非空）。
static func is_active(combo: BrewCombo) -> bool:
	return combo != null and not combo.is_empty()


## 剩余时长比例 → 倒计时弧扫过的弧度（0~TAU）。
static func sweep_radians(ratio: float) -> float:
	return clampf(ratio, 0.0, 1.0) * TAU


## 倒计时弧的结束角（配合 draw_arc 使用）。
static func end_angle(ratio: float) -> float:
	return START_ANGLE + sweep_radians(ratio)


## 剩余比例 → 环的透明度：最后 20% 逐渐变淡，提醒即将结束。
static func ring_alpha(ratio: float) -> float:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	if clamped >= 0.2:
		return 1.0
	return clampf(clamped / 0.2, 0.25, 1.0)