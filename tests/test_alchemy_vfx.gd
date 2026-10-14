extends SceneTree

## 炼金表现层：替换爆发 / 词条反应 / 过载爆炸的节点生成、配色与伤害半径。

var _checks: int = 0
var _failures: int = 0


## 记录受到伤害的假怪物，验证替换爆发的范围判定。
class StubMonster extends Node2D:
	var damage_taken: int = 0

	func take_damage(amount: int) -> void:
		damage_taken += amount


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var vfx: AlchemyVfx = AlchemyVfx.new()
	root.add_child(vfx)
	await process_frame

	# 反应配色：不同反应颜色不同，未知反应回退默认色。
	_check(AlchemyVfx.reaction_color(&"poison_smoke") != AlchemyVfx.reaction_color(&"steam_burst"), "不同反应不同颜色")
	_check(AlchemyVfx.reaction_color(&"not_a_reaction") == AlchemyVfx.DEFAULT_COLOR, "未知反应回退默认色")
	_check(AlchemyVfx.reaction_color(&"annihilation") == AlchemyVfx.REACTION_COLORS[&"annihilation"], "已知反应取表内颜色")

	# 爆发主色：优先反应色，其次效果标签色，最后默认色。
	var combo: BrewCombo = BrewCombo.new()
	var tags: Array[StringName] = [&"fire"]
	combo.effect_tags = tags
	var reactions: Array = [{"id": &"poison_smoke", "name": "毒烟", "level": 2}]
	_check(AlchemyVfx.burst_color(combo, reactions) == AlchemyVfx.reaction_color(&"poison_smoke"), "有反应时取反应色")
	_check(AlchemyVfx.burst_color(combo, []) == AlchemyVfx.TAG_COLORS[&"fire"], "无反应时取标签色")
	var empty_combo: BrewCombo = BrewCombo.new()
	_check(AlchemyVfx.burst_color(empty_combo, []) == AlchemyVfx.DEFAULT_COLOR, "无标签无反应用默认色")
	_check(AlchemyVfx.burst_color(null, []) == AlchemyVfx.DEFAULT_COLOR, "空组合用默认色")

	# 替换爆发：一个圆环 + 每个反应一团粒子。
	_check(vfx.active_effect_count() == 0, "初始没有表现节点")
	vfx.burst(combo, 0.5, reactions)
	_check(vfx.active_effect_count() == 2, "一次爆发 = 圆环 + 反应粒子")
	vfx.burst(combo, 1.0, [{"id": &"a"}, {"id": &"b"}])
	_check(vfx.active_effect_count() == 2 + 3, "两个反应生成三个节点")

	# 过载爆炸：圆环 + 冲击粒子。
	var before: int = vfx.active_effect_count()
	vfx.overload_blast(48.0)
	_check(vfx.active_effect_count() == before + 2, "过载爆炸生成两个节点")

	# 表现节点到时自动回收。
	var deadline: int = Time.get_ticks_msec() + 3000
	while vfx.active_effect_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(vfx.active_effect_count() == 0, "表现节点自动回收")

	# 替换爆发伤害：半径内吃伤害，半径外不吃。
	var player: PlayerCharacter = (load("res://scenes/game/player.tscn") as PackedScene).instantiate() as PlayerCharacter
	root.add_child(player)
	player.global_position = Vector2.ZERO
	var near: StubMonster = StubMonster.new()
	near.global_position = Vector2(8.0, 0.0)
	near.add_to_group("monsters")
	root.add_child(near)
	var far: StubMonster = StubMonster.new()
	far.global_position = Vector2(400.0, 0.0)
	far.add_to_group("monsters")
	root.add_child(far)
	await process_frame

	# 0.5 强度 → roundi(0.5 × 10) = 5 点伤害。
	player._apply_replacement_burst(0.5)
	_check(near.damage_taken == 5, "半径内的敌人吃替换爆发伤害")
	_check(far.damage_taken == 0, "半径外的敌人不受影响")
	_check(player.get_node_or_null("AlchemyVfx") != null, "玩家节点挂载了表现层")

	Engine.time_scale = 1.0
	paused = false
	player.free()
	vfx.free()
	print("ALCHEMY VFX: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
