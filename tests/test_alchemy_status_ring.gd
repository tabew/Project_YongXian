extends SceneTree

## 武器旁常驻状态环：元素取色、主导元素、倒计时弧度与 HUD 接线。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## 用若干条词条造一个组合；效果标签按 TraitPool 的规则取元素词条 id，
## 这样手工组合与炼金产出的组合在 is_empty() 判定上一致。
static func _combo(entries: Array) -> BrewCombo:
	var combo: BrewCombo = BrewCombo.new()
	for entry: Array in entries:
		var instance: TraitInstance = TraitCatalog.create(entry[0], entry[1], 1)
		if instance == null:
			continue
		combo.traits.append(instance)
		if instance.category == TraitCategory.Kind.ELEMENT and not combo.effect_tags.has(instance.id):
			combo.effect_tags.append(instance.id)
	return combo


func _run() -> void:
	# ── 颜色表覆盖全部 13 元素 ──────────────────────────────────────────
	var elements: Array[StringName] = []
	for trait_id: StringName in TraitCatalog.all_ids():
		if int(TraitCatalog.definition_of(trait_id).get("category", -1)) == TraitCategory.Kind.ELEMENT:
			elements.append(trait_id)
	_check(elements.size() == 13, "元素词条共 13 条")
	for element: StringName in elements:
		_check(AlchemyStatusRing.ELEMENT_COLORS.has(element), "元素 %s 有图标颜色" % element)

	# ── 主导元素：等级最高者胜出 ────────────────────────────────────────
	_check(AlchemyStatusRing.dominant_element(null) == &"", "空组合没有主导元素")
	_check(AlchemyStatusRing.dominant_element(BrewCombo.new()) == &"", "无词条组合没有主导元素")
	var low_fire: BrewCombo = _combo([[&"fire", 2]])
	_check(AlchemyStatusRing.dominant_element(low_fire) == &"fire", "只有火时主导元素是火")
	var mixed: BrewCombo = _combo([[&"fire", 2], [&"poison", 5]])
	_check(AlchemyStatusRing.dominant_element(mixed) == &"poison", "等级更高的元素主导")
	var tie: BrewCombo = _combo([[&"fire", 3], [&"ice", 3]])
	_check(AlchemyStatusRing.dominant_element(tie) == &"fire", "等级相同时取先出现的元素")
	var behavior_only: BrewCombo = _combo([[&"explode", 5], [&"chain", 5]])
	_check(AlchemyStatusRing.dominant_element(behavior_only) == &"", "纯行为词条没有主导元素")

	# ── 图标颜色 ────────────────────────────────────────────────────────
	_check(AlchemyStatusRing.effect_color(null) == AlchemyStatusRing.IDLE_COLOR, "空组合用中性色")
	_check(AlchemyStatusRing.effect_color(low_fire) == AlchemyStatusRing.ELEMENT_COLORS[&"fire"], "火组合用火色")
	_check(AlchemyStatusRing.effect_color(mixed) == AlchemyStatusRing.ELEMENT_COLORS[&"poison"], "混色时用主导元素色")
	_check(AlchemyStatusRing.effect_color(behavior_only) == AlchemyStatusRing.IDLE_COLOR, "纯行为组合用中性色")

	# ── 是否激活 ────────────────────────────────────────────────────────
	_check(not AlchemyStatusRing.is_active(null), "空引用未激活")
	_check(not AlchemyStatusRing.is_active(BrewCombo.new()), "空组合未激活")
	_check(AlchemyStatusRing.is_active(low_fire), "有词条的组合已激活")

	# ── 倒计时弧度 ──────────────────────────────────────────────────────
	_check(is_equal_approx(AlchemyStatusRing.sweep_radians(0.0), 0.0), "剩余 0% 不画弧")
	_check(is_equal_approx(AlchemyStatusRing.sweep_radians(0.5), PI), "剩余 50% 画半圈")
	_check(is_equal_approx(AlchemyStatusRing.sweep_radians(1.0), TAU), "剩余 100% 画整圈")
	_check(is_equal_approx(AlchemyStatusRing.sweep_radians(2.0), TAU), "超过 100% 被夹到整圈")
	_check(is_equal_approx(AlchemyStatusRing.sweep_radians(-1.0), 0.0), "负比例被夹到 0")
	_check(is_equal_approx(AlchemyStatusRing.end_angle(0.25), AlchemyStatusRing.START_ANGLE + PI * 0.5), "结束角从 12 点方向起算")
	_check(is_equal_approx(AlchemyStatusRing.START_ANGLE, -PI * 0.5), "起始角在正上方")

	# ── 收尾淡出 ────────────────────────────────────────────────────────
	_check(is_equal_approx(AlchemyStatusRing.ring_alpha(1.0), 1.0), "满时长不透明")
	_check(is_equal_approx(AlchemyStatusRing.ring_alpha(0.2), 1.0), "剩 20% 仍不透明")
	_check(is_equal_approx(AlchemyStatusRing.ring_alpha(0.1), 0.5), "剩 10% 淡到一半")
	_check(is_equal_approx(AlchemyStatusRing.ring_alpha(0.0), 0.25), "归零时保留最低可见度")

	# ── HUD 接线：状态环跟随当前组合 ────────────────────────────────────
	var station: AlchemyStation = AlchemyStation.new()
	root.add_child(station)
	var hud: AlchemyHud = (load("res://scenes/ui/alchemy/alchemy_hud.tscn") as PackedScene).instantiate() as AlchemyHud
	root.add_child(hud)
	hud.bind(station)
	await process_frame
	await process_frame
	_check(hud._status_ring != null, "武器旁常驻状态环已创建")
	_check(not hud._status_ring.active, "没有组合时状态环未激活")
	_check(hud._status_ring.color == AlchemyStatusRing.IDLE_COLOR, "没有组合时状态环用中性色")

	# 用硝石（火 + 爆炸）炼出组合，状态环应变成火色并按剩余时长扫弧。
	station.absorb_material(1002, 2)
	station.fill_first_free_slot(1002)
	_check(station.brew_from_slots() != null, "硝石炼出组合")
	await process_frame
	await process_frame
	_check(hud._status_ring.active, "有组合时状态环激活")
	_check(hud._status_ring.color == AlchemyStatusRing.ELEMENT_COLORS[&"fire"], "火系组合的状态环用火色")
	_check(hud._status_ring.ratio > 0.0 and hud._status_ring.ratio <= 1.0, "状态环比例在 (0, 1] 内")
	_check(is_equal_approx(hud._status_ring.ratio, station.duration_ratio()), "状态环比例等于剩余时长比例")

	station.free()
	hud.free()
	print("ALCHEMY STATUS RING: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)