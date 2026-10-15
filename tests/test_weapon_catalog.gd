extends SceneTree

## 武器扩展：配置表有效性、手感差异、玩家轮换接入与真实挥砍命中。

var _checks: int = 0
var _failures: int = 0
var _arena: Node2D
var _actor: Node2D
var _controller: WeaponController


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	# ── 配置表 ──────────────────────────────────────────────────────────
	var ids: Array[StringName] = WeaponCatalog.all_ids()
	_check(ids.size() == 9, "扩展武器共 9 种")
	for expected: StringName in [&"axe", &"hammer", &"spear", &"dagger", &"scythe", &"gauntlet",
			&"whip", &"shield", &"greatsword"]:
		_check(ids.has(expected), "包含武器：%s" % expected)
		_check(WeaponCatalog.has_weapon(expected), "可查询武器：%s" % expected)
	_check(not WeaponCatalog.has_weapon(&"nope"), "未知武器返回 false")
	_check(WeaponCatalog.definition_of(&"nope").id.is_empty(), "未知武器返回空定义")

	# ── 每条定义都合法 ──────────────────────────────────────────────────
	for id: StringName in ids:
		var definition: SwingWeaponDefinition = WeaponCatalog.definition_of(id)
		_check(definition.validation_errors().is_empty(),
			"武器 %s 定义合法：%s" % [id, "; ".join(definition.validation_errors())])
		_check(definition.attack_scene != null, "武器 %s 有攻击场景" % id)
		_check(definition.texture != null, "武器 %s 有刀身贴图" % id)
		_check(definition.damage > 0.0, "武器 %s 伤害为正" % id)
		_check(definition.attacks_per_second() > 0.0, "武器 %s 攻速为正" % id)
		if definition.texture != null:
			var size: Vector2 = definition.texture.get_size()
			_check(definition.texture_grip.x >= 0.0 and definition.texture_grip.x < size.x, "武器 %s 握把横向在贴图内" % id)
			_check(definition.texture_grip.y >= 0.0 and definition.texture_grip.y < size.y, "武器 %s 握把纵向在贴图内" % id)
		_check(definition.blade_inset < definition.blade_length, "武器 %s 无效段短于刀身" % id)

	# ── 手感差异 ────────────────────────────────────────────────────────
	var spear: SwingWeaponDefinition = WeaponCatalog.definition_of(&"spear")
	var dagger: SwingWeaponDefinition = WeaponCatalog.definition_of(&"dagger")
	var greatsword: SwingWeaponDefinition = WeaponCatalog.definition_of(&"greatsword")
	var shield: SwingWeaponDefinition = WeaponCatalog.definition_of(&"shield")
	var whip: SwingWeaponDefinition = WeaponCatalog.definition_of(&"whip")
	var scythe: SwingWeaponDefinition = WeaponCatalog.definition_of(&"scythe")
	var gauntlet: SwingWeaponDefinition = WeaponCatalog.definition_of(&"gauntlet")
	_check(spear.blade_length > dagger.blade_length, "长矛比匕首更长")
	_check(spear.arc_degrees < greatsword.arc_degrees, "长矛突刺弧小于巨剑横扫")
	_check(greatsword.damage > dagger.damage, "巨剑单次伤害高于匕首")
	_check(dagger.attacks_per_second() > greatsword.attacks_per_second(), "匕首攻速高于巨剑")
	_check(shield.knockback > dagger.knockback, "盾击退强于匕首")
	_check(whip.blade_length > greatsword.blade_length, "鞭比巨剑更长")
	# 斧 / 锤：慢而重，锤比斧更慢更重、范围更大。
	var axe: SwingWeaponDefinition = WeaponCatalog.definition_of(&"axe")
	var hammer: SwingWeaponDefinition = WeaponCatalog.definition_of(&"hammer")
	_check(hammer.damage > axe.damage, "锤单次伤害高于斧")
	_check(hammer.attacks_per_second() < axe.attacks_per_second(), "锤攻速低于斧")
	_check(hammer.arc_degrees > axe.arc_degrees, "锤范围大于斧")
	_check(hammer.knockback > axe.knockback, "锤击退强于斧")
	_check(axe.damage > dagger.damage, "斧伤害高于匕首")
	_check(scythe.arc_degrees > shield.arc_degrees, "镰刀扫弧大于盾")
	_check(gauntlet.blade_length < dagger.blade_length, "拳套比匕首更短")

	# ── 玩家轮换接入 ────────────────────────────────────────────────────
	var player: PlayerCharacter = (load("res://scenes/game/player.tscn") as PackedScene).instantiate() as PlayerCharacter
	root.add_child(player)
	await process_frame
	var loadout_size: int = player.weapon_loadout.size()
	_check(loadout_size >= 7, "玩家武器列表包含扩展武器")
	_check(player.install_weapon_catalog() == 0, "重复接入不会重复添加")
	_check(player.weapon_loadout.size() == loadout_size, "重复接入不改变列表长度")
	var installed_ids: Array[StringName] = []
	for equipped: WeaponDefinition in player.weapon_loadout:
		if equipped != null:
			installed_ids.append(equipped.id)
	for id: StringName in ids:
		_check(installed_ids.has(id), "玩家可轮换到 %s" % id)
	# Q 轮换已删除：武器改为按 id 装备（出发门选择后套用同一条路径）。
	_check(player.equip_weapon_by_id(&"long_staff"), "按 id 装备武器接口可用")
	_check(player.weapon_controller.equipped_weapon.id == &"long_staff", "按 id 装备后控制器同步")
	_check(not player.equip_weapon_by_id(&"not_a_weapon"), "未知武器 id 装备失败")
	_check(not player.equip_weapon_by_id(&""), "空武器 id 装备失败")
	_check(player.weapon_controller.equipped_weapon.id == &"long_staff", "装备失败时保持原武器")
	player.free()

	# ── 真实挥砍命中 ────────────────────────────────────────────────────
	_arena = Node2D.new()
	root.add_child(_arena)
	_actor = Node2D.new()
	_arena.add_child(_actor)
	_controller = WeaponController.new()
	_actor.add_child(_controller)
	_controller.set_physics_process(false)
	var weapon: SwingWeaponDefinition = WeaponCatalog.definition_of(&"greatsword").duplicate(true) as SwingWeaponDefinition
	weapon.critical_chance = 0.0
	_check(_controller.equip(weapon), "扩展武器可装备")

	var target: Node2D = Node2D.new()
	target.position = Vector2(30.0, 0.0)
	var health: HealthComponent = HealthComponent.new()
	health.max_health = 1000.0
	target.add_child(health)
	var hurtbox: CombatHurtbox = CombatHurtbox.new()
	hurtbox.health = health
	hurtbox.team = 2
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 5.0
	shape_node.shape = shape
	hurtbox.add_child(shape_node)
	target.add_child(hurtbox)
	_arena.add_child(target)
	await physics_frame
	await physics_frame

	_controller.set_aim(Vector2.RIGHT)
	_check(_controller.try_attack(), "扩展武器可以起手")
	var attack: WeaponAttack = null
	for child: Node in _controller.get_children():
		if child is WeaponAttack and not child.is_queued_for_deletion():
			child.set_physics_process(false)
			attack = child as WeaponAttack
			break
	_check(attack != null, "拿到挥砍实例")
	attack._physics_process(0.22)
	attack._physics_process(0.30)
	_check(health.current_health < 1000.0, "巨剑挥砍命中目标造成伤害")

	_arena.free()
	print("WEAPON CATALOG: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
