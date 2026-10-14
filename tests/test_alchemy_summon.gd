extends SceneTree

## 炼金召唤物接线：命中召唤（召唤词条 / 骨 V 骷髅）、击杀召唤（灵魂游魂）、
## 活体 V 分裂、击杀加速热量冷却。召唤物是真实节点，索敌 / 出手 / 自爆都走真实物理查询。

const LONGSWORD: SwingWeaponDefinition = preload("res://resources/weapons/longsword.tres")
const PLAYER_SCENE: PackedScene = preload("res://scenes/game/player.tscn")

var _checks: int = 0
var _failures: int = 0
var _arena: Node2D
var _actor: Node2D
var _controller: WeaponController
var _data: WeaponDefinition


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


# ── 夹具 ────────────────────────────────────────────────────────────────

## 与 test_weapons 一致的最小竞技场：一个持械者 + 若干受击盒。
func _fixture() -> void:
	if is_instance_valid(_arena):
		_arena.free()
	_arena = Node2D.new()
	root.add_child(_arena)
	_actor = Node2D.new()
	_arena.add_child(_actor)
	_controller = WeaponController.new()
	_actor.add_child(_controller)
	_controller.set_physics_process(false)
	_data = LONGSWORD.duplicate(true) as WeaponDefinition
	_data.critical_chance = 0.0
	_check(_controller.equip(_data), "武器可以装备")


## 受击盒：默认 team 2、层 4（与武器命中遮罩一致），血量固定 1000 便于比对。
func _target(at: Vector2, team: int = 2, layer: int = 4) -> HealthComponent:
	var target: Node2D = Node2D.new()
	target.position = at
	var health: HealthComponent = HealthComponent.new()
	health.max_health = 1000.0
	target.add_child(health)
	var hurtbox: CombatHurtbox = CombatHurtbox.new()
	hurtbox.health = health
	hurtbox.team = team
	hurtbox.collision_layer = layer
	hurtbox.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 3.0
	shape_node.shape = shape
	hurtbox.add_child(shape_node)
	target.add_child(hurtbox)
	_arena.add_child(target)
	return health


func _sync_physics() -> void:
	await physics_frame
	await physics_frame


func _start() -> WeaponAttack:
	_controller.set_aim(Vector2.RIGHT)
	_check(_controller.try_attack(), "攻击可以起手")
	for child: Node in _controller.get_children():
		if child is WeaponAttack and not child.is_queued_for_deletion():
			(child as WeaponAttack).set_physics_process(false)
			return child as WeaponAttack
	return null


func _make_hit(position: Vector2) -> CombatHit:
	var hit: CombatHit = CombatHit.new()
	hit.source = _actor
	hit.weapon_id = _data.id
	hit.damage = _data.damage
	hit.position = position
	return hit


## 手动推进的召唤物：关掉自动 _physics_process，保证断言不受帧率影响。
func _make_summon(at: Vector2, damage: float, lifetime: float = 30.0) -> AlchemySummon:
	var summon: AlchemySummon = AlchemySummon.new()
	summon.damage = damage
	summon.lifetime = lifetime
	summon.owner_actor = _actor
	_arena.add_child(summon)
	summon.set_physics_process(false)
	summon.global_position = at
	return summon


func _summons() -> Array[AlchemySummon]:
	var found: Array[AlchemySummon] = []
	for child: Node in _arena.get_children():
		if child is AlchemySummon:
			found.append(child as AlchemySummon)
	return found


## 行为词条效果表：只填要测的条目，其余保持空表默认值。
func _effects_table(entries: Dictionary) -> Dictionary:
	var table: Dictionary = AlchemyHitEffects.empty_profile()
	for key: StringName in entries:
		table[key] = entries[key]
	table["has_any"] = AlchemyHitEffects.has_any(table)
	return table


## 只有一条词条的组合。
static func _combo(trait_id: StringName, level: int, stacks: int = 1) -> BrewCombo:
	var combo: BrewCombo = BrewCombo.new()
	combo.traits = [TraitCatalog.create(trait_id, level, stacks)]
	combo.effect_tags = [trait_id]
	return combo


# ── 命中召唤 ────────────────────────────────────────────────────────────

## 召唤词条 / 骨 V 骷髅都由 WeaponAttack._spawn_summons 落地成真实节点。
func _test_hit_summon_wiring() -> void:
	# ── 召唤词条：命中时按数量生成召唤物 ──────────────────────────────
	_fixture()
	_controller.hit_effects = _effects_table({
		"summon": {"chance": 1.0, "count": 2, "duration": 5.0, "explode": true},
	})
	var attack: WeaponAttack = _start()
	attack.damage_multiplier = 2.0
	attack._spawn_summons(_make_hit(Vector2(20, 4)))
	var summons: Array[AlchemySummon] = _summons()
	_check(summons.size() == 2, "命中召唤按数量生成召唤物")
	if summons.size() == 2:
		_check(is_equal_approx(summons[0].damage, _data.damage * 2.0 * AlchemyRules.SUMMON_DAMAGE_RATIO), "召唤物伤害 = 武器伤害 × 倍率 × 30%")
		_check(is_equal_approx(summons[0].lifetime, 5.0), "召唤物寿命取词条时长")
		_check(summons[0].explodes, "召唤 V 的召唤物带自爆标记")
		_check(summons[0].tint == AlchemyHitEffects.flavor_color(&"summon"), "召唤物颜色取来源色")
		_check(summons[0].owner_actor == _actor, "召唤物的伤害来源是持械者")
		_check(summons[0].get_parent() == _arena, "召唤物挂在持械者所在的世界节点下")
		_check(summons[0].global_position.is_equal_approx(Vector2(14, -2)), "召唤物生成在命中点附近")
		_check(summons[1].global_position.is_equal_approx(Vector2(26, -2)), "多个召唤物错开排布")

	# ── 触发概率不满足时不生成 ────────────────────────────────────────
	_fixture()
	_controller.hit_effects = _effects_table({
		"summon": {"chance": 0.0, "count": 2, "duration": 5.0, "explode": false},
	})
	attack = _start()
	attack._spawn_summons(_make_hit(Vector2(20, 0)))
	_check(_summons().is_empty(), "触发概率为 0 时不生成召唤物")

	# ── 骨 V「可召唤骷髅」：真实词条表按配置概率生成骷髅 ──────────────
	_fixture()
	var bone: Dictionary = AlchemyHitEffects.profile(_combo(&"bone", 5))
	_check(bool(bone["skeleton"]), "骨 V 解锁骷髅召唤")
	_check(AlchemyHitEffects.summon_specs(bone).size() == 1, "骨 V 只透出一条召唤来源")
	_controller.hit_effects = bone
	attack = _start()
	for _attempt: int in range(100):
		attack._spawn_summons(_make_hit(Vector2(20, 0)))
		if not _summons().is_empty():
			break
	_check(not _summons().is_empty(), "骨 V 在 100 次命中内至少召唤一次骷髅")
	if not _summons().is_empty():
		var skeleton: AlchemySummon = _summons()[0]
		_check(is_equal_approx(skeleton.lifetime, AlchemyRules.SKELETON_DURATION), "骷髅寿命取配置值")
		_check(skeleton.tint == AlchemyHitEffects.flavor_color(&"bone"), "骷髅用骨系颜色")
		_check(not skeleton.explodes, "骷髅不带自爆标记")


# ── 召唤物行为 ──────────────────────────────────────────────────────────

## 索敌、出手间隔、移动、同队 / 遮罩过滤。
func _test_summon_combat() -> void:
	# ── 出手：射程内按间隔打最近的敌人 ────────────────────────────────
	_fixture()
	var summon: AlchemySummon = _make_summon(Vector2.ZERO, 10.0)
	var target: HealthComponent = _target(Vector2(10, 0))
	var other: HealthComponent = _target(Vector2(0, 40))
	var hits: Array[CombatHit] = []
	target.damaged.connect(func(hit: CombatHit, _amount: float) -> void: hits.append(hit))
	await _sync_physics()
	summon._physics_process(0.016)
	_check(target.current_health == 990.0, "召唤物对索敌半径内的敌人出手")
	_check(other.current_health == 1000.0, "召唤物只打最近的一个目标")
	_check(hits.size() == 1 and hits[0].source == _actor, "召唤伤害的来源是召唤者")
	_check(hits[0].weapon_id == &"alchemy_summon", "召唤伤害带自己的武器标记")
	summon._physics_process(0.1)
	_check(target.current_health == 990.0, "出手间隔内不会重复伤害")
	summon._physics_process(AlchemyRules.SUMMON_ATTACK_INTERVAL)
	_check(target.current_health == 980.0, "间隔结束后再次出手")

	# ── 移动：超出出手距离但在索敌半径内会主动靠近 ────────────────────
	_fixture()
	var walker: AlchemySummon = _make_summon(Vector2.ZERO, 10.0)
	var walk_target: HealthComponent = _target(Vector2(40, 0))
	await _sync_physics()
	walker._physics_process(0.1)
	_check(walker.global_position.x > 0.0, "召唤物朝索敌半径内的目标移动")
	_check(walk_target.current_health == 1000.0, "还没走进出手距离时不出手")
	walker._physics_process(0.1)
	walker._physics_process(0.1)
	_check(walk_target.current_health == 990.0, "走进出手距离后开始攻击")

	# ── 索敌半径外不追 ────────────────────────────────────────────────
	_fixture()
	var idle: AlchemySummon = _make_summon(Vector2.ZERO, 10.0)
	var distant: HealthComponent = _target(Vector2(AlchemyRules.SUMMON_SEARCH_RADIUS_TILES * 16.0 + 16.0, 0))
	await _sync_physics()
	idle._physics_process(0.5)
	_check(idle.global_position.is_zero_approx(), "索敌半径外的敌人不追")
	_check(distant.current_health == 1000.0, "索敌半径外的敌人不受伤")

	# ── 同队与遮罩外的目标不算敌人 ────────────────────────────────────
	_fixture()
	var picky: AlchemySummon = _make_summon(Vector2.ZERO, 10.0)
	var ally: HealthComponent = _target(Vector2(10, 0), 1)
	var other_layer: HealthComponent = _target(Vector2(-10, 0), 2, 2)
	await _sync_physics()
	picky._physics_process(0.016)
	_check(ally.current_health == 1000.0, "召唤物不打同队目标")
	_check(other_layer.current_health == 1000.0, "召唤物不打命中遮罩外的目标")
	_check(picky.global_position.is_zero_approx(), "没有敌人时召唤物原地待命")


# ── 消散 ────────────────────────────────────────────────────────────────

## 寿命到期回收自己；带自爆标记时对范围内敌人再来一次范围伤害。
func _test_summon_expire() -> void:
	_fixture()
	var bomber: AlchemySummon = _make_summon(Vector2.ZERO, 20.0, 0.5)
	bomber.explodes = true
	var blast_target: HealthComponent = _target(Vector2(10, 0))
	var outside: HealthComponent = _target(Vector2(40, 0))
	await _sync_physics()
	var expired: Array[AlchemySummon] = []
	bomber.expired.connect(func(node: AlchemySummon) -> void: expired.append(node))
	bomber._physics_process(0.6)
	_check(expired.size() == 1 and expired[0] == bomber, "寿命到期发出 expired 信号")
	_check(is_equal_approx(blast_target.current_health, 1000.0 - 20.0 * AlchemyRules.SUMMON_EXPLODE_DAMAGE_RATIO), "自爆按 60% 伤害结算")
	_check(outside.current_health == 1000.0, "自爆半径外的目标安全")
	_check(bomber.is_queued_for_deletion(), "消散后回收自己")

	# ── 不带自爆标记：消散时静默 ──────────────────────────────────────
	_fixture()
	var quiet: AlchemySummon = _make_summon(Vector2.ZERO, 20.0, 0.5)
	var quiet_target: HealthComponent = _target(Vector2(10, 0))
	await _sync_physics()
	quiet._physics_process(0.6)
	_check(quiet_target.current_health == 1000.0, "不带自爆标记的召唤物消散时不造成伤害")
	_check(quiet.is_queued_for_deletion(), "静默消散同样回收自己")

	# ── 剩余寿命比例供表现层淡出 ──────────────────────────────────────
	_fixture()
	var fading: AlchemySummon = _make_summon(Vector2.ZERO, 1.0, 4.0)
	_check(is_equal_approx(fading.lifetime_ratio(), 1.0), "刚生成时寿命比例为 1")
	fading._physics_process(1.0)
	_check(is_equal_approx(fading.lifetime_ratio(), 0.75), "过掉四分之一寿命后比例为 0.75")


# ── 炼金台击杀接线 ──────────────────────────────────────────────────────

## register_kill 同时驱动击杀加速冷却、活体分裂与召唤来源表。
func _test_station_kill_wiring() -> void:
	var station: AlchemyStation = AlchemyStation.new()
	root.add_child(station)
	_check(station.kills_this_frame == 0, "初始本帧击杀数为 0")
	_check(station.register_kill() == 0, "没有活体组合时击杀不分裂")
	_check(station.kills_this_frame == 1, "register_kill 累积本帧击杀数")
	station.register_kill()
	_check(station.kills_this_frame == 2, "多次击杀累加")

	# ── 击杀加速热量冷却 ──────────────────────────────────────────────
	var heat: HeatSystem = station.session.heat
	station.in_combat = true
	station.kills_this_frame = 0
	heat.heat = 60.0
	station.tick(0.5)
	var slow_drop: float = 60.0 - heat.heat
	_check(station.kills_this_frame == 0, "tick 读走本帧击杀数")
	heat.heat = 60.0
	station.register_kill()
	station.register_kill()
	station.tick(0.5)
	var fast_drop: float = 60.0 - heat.heat
	_check(fast_drop > slow_drop, "击杀加速热量冷却")
	_check(is_equal_approx(fast_drop - slow_drop, 2.0 * AlchemyRules.HEAT_COOLDOWN_KILL_BONUS * 0.5 * heat.cooldown_multiplier), "每次击杀多降固定值")

	# ── 召唤来源表 ────────────────────────────────────────────────────
	station.session.active_combo = _combo(&"soul", 5)
	var kills: Array[Dictionary] = station.kill_summons()
	_check(kills.size() == 1, "灵魂组合给出一条击杀召唤来源")
	_check(is_equal_approx(float(kills[0]["chance"]), 0.25), "灵魂 V 生成概率 25%")
	_check(int(kills[0]["count"]) == 3, "灵魂 V 生成 3 个游魂")
	_check(bool(kills[0]["explode"]), "灵魂 V 的游魂可爆炸")
	_check(kills[0]["flavor"] == &"soul", "游魂用灵魂外观")
	_check(station.hit_summons().is_empty(), "灵魂组合不产生命中召唤")

	station.session.active_combo = _combo(&"summon", 5)
	var hits: Array[Dictionary] = station.hit_summons()
	_check(hits.size() == 1 and hits[0]["flavor"] == &"summon", "召唤词条给出一条命中召唤来源")
	_check(is_equal_approx(float(hits[0]["duration"]), 12.0), "召唤 V 时长 12 秒")
	_check(bool(hits[0]["explode"]), "召唤 V 的召唤物可爆炸")
	_check(station.kill_summons().is_empty(), "召唤词条不产生击杀召唤")

	station.session.active_combo = _combo(&"bone", 5)
	hits = station.hit_summons()
	_check(hits.size() == 1 and hits[0]["flavor"] == &"bone", "骨 V 给出一条骷髅召唤来源")
	_check(is_equal_approx(float(hits[0]["chance"]), AlchemyRules.SKELETON_CHANCE), "骷髅生成概率取配置值")

	station.session.active_combo = null
	_check(station.kill_summons().is_empty() and station.hit_summons().is_empty(), "没有激活组合时没有召唤来源")
	station.free()


# ── 主角击杀接线 ────────────────────────────────────────────────────────

## 击杀 → 热量加速冷却 / 活体 V 分裂 / 灵魂游魂，全部由主角转成召唤物节点。
func _test_player_kill_wiring() -> void:
	_fixture()
	var player: PlayerCharacter = PLAYER_SCENE.instantiate() as PlayerCharacter
	player.set_physics_process(false)
	player.set_process(false)
	_arena.add_child(player)
	var station: AlchemyStation = player.alchemy_station
	station.set_process(false)
	_check(station != null, "主角自带随身炼金台")
	_check(player.weapon_controller.equipped_weapon != null, "主角起手带武器")

	# ── 玩家侧生成：伤害 = 武器基础伤害 × 组合强度 × 比例 ──────────────
	player._spawn_summons([{
		"count": 2,
		"chance": 1.0,
		"duration": 6.0,
		"explode": false,
		"flavor": &"split",
		"damage_ratio": 0.6,
	}], Vector2(30, 0))
	var summons: Array[AlchemySummon] = _summons()
	_check(summons.size() == 2, "玩家按来源表生成召唤物")
	if summons.size() == 2:
		_check(is_equal_approx(summons[0].damage, player.weapon_controller.equipped_weapon.damage * 0.6), "分身伤害 = 武器伤害 × 强度 × 60%")
		_check(is_equal_approx(summons[0].lifetime, 6.0), "分身寿命取来源时长")
		_check(summons[0].tint == AlchemyHitEffects.flavor_color(&"split"), "分身用活体颜色")
		_check(summons[0].get_parent() == _arena, "玩家召唤物挂在世界节点下")
		_check(summons[0].owner_actor == player, "玩家召唤物的伤害来源是主角")

	# ── 活体 V：第 3 次击杀分裂出分身 ─────────────────────────────────
	station.session.active_combo = _combo(&"living", 5)
	player.on_monster_killed(Vector2(10, 0))
	player.on_monster_killed(Vector2(10, 0))
	_check(station.kills_this_frame == 2, "击杀累积到炼金台")
	var before_split: int = _summons().size()
	player.on_monster_killed(Vector2(10, 0))
	_check(_summons().size() == before_split + 1, "活体 V 第 3 次击杀分裂出 1 个分身")

	# ── 灵魂 V：击杀概率生成游魂 ──────────────────────────────────────
	station.session.active_combo = _combo(&"soul", 5)
	var before_soul: int = _summons().size()
	for _attempt: int in range(60):
		player.on_monster_killed(Vector2(50, 0))
		if _summons().size() > before_soul:
			break
	_check(_summons().size() > before_soul, "灵魂 V 击杀生成游魂")
	if _summons().size() > before_soul:
		var soul_summon: AlchemySummon = _summons()[before_soul]
		_check(soul_summon.tint == AlchemyHitEffects.flavor_color(&"soul"), "游魂用灵魂颜色")
		_check(is_equal_approx(soul_summon.lifetime, AlchemyRules.SOUL_BURST_DURATION), "游魂寿命取配置值")


func _run() -> void:
	await _test_hit_summon_wiring()
	await _test_summon_combat()
	await _test_summon_expire()
	_test_station_kill_wiring()
	await _test_player_kill_wiring()
	print("ALCHEMY SUMMON: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
