extends SceneTree

## 局内成长系统的端到端验证：经验曲线、三选一、加成聚合、武器改造、经验球、击杀与炼金结算。
## 运行：godot --headless --path . --script tests/test_run_progression.gd

const LONGSWORD: SwingWeaponDefinition = preload("res://resources/weapons/longsword.tres")
const LONG_STAFF: DepthStrikeWeaponDefinition = preload("res://resources/weapons/long_staff.tres")
const YOYO: YoyoWeaponDefinition = preload("res://resources/weapons/yoyo.tres")
const PLAYER_SCENE: PackedScene = preload("res://scenes/game/player.tscn")
const GIVE_MONSTER: PackedScene = preload("res://scenes/monsters/give_monster.tscn")
const PANEL_SCENE: PackedScene = preload("res://scenes/ui/upgrade/upgrade_panel.tscn")

var _checks: int = 0
var _failures: int = 0
var _progress: Node = null
var _arena: Node2D = null
var _player: PlayerCharacter = null


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _take(card_id: StringName, times: int = 1) -> void:
	for _index: int in times:
		_check(_progress.take_card(card_id), "take_card(%s)" % card_id)


func _make_player() -> void:
	if is_instance_valid(_player):
		_arena.remove_child(_player)
		_player.free()
		_player = null
	_player = PLAYER_SCENE.instantiate() as PlayerCharacter
	_arena.add_child(_player)
	_player.set_physics_process(false)
	_player.weapon_controller.set_physics_process(false)


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


func _controller_accepts(weapon: WeaponDefinition) -> bool:
	var holder: Node2D = Node2D.new()
	_arena.add_child(holder)
	var controller: WeaponController = WeaponController.new()
	holder.add_child(controller)
	controller.set_physics_process(false)
	var accepted: bool = controller.equip(weapon)
	holder.free()
	return accepted


func _run() -> void:
	_progress = root.get_node_or_null("RunProgress")
	_check(_progress != null, "RunProgress autoload exists")
	_arena = Node2D.new()
	root.add_child(_arena)
	if _progress == null:
		quit(1)
		return

	_test_curve()
	_test_card_pool()
	_test_take_card()
	_test_player_aggregates()
	_test_weapon_cards()
	await _test_experience_orb()
	_test_kill_and_alchemy()
	_test_monster_hooks()
	await _test_orbit_ball()
	await _test_upgrade_flow()
	await _test_hud_readout()
	_test_scene_wiring()
	_test_reset()

	if is_instance_valid(_player):
		_arena.remove_child(_player)
		_player.free()
		_player = null
	_arena.free()
	await process_frame
	print("RUN PROGRESSION TESTS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


# --- 经验曲线 -------------------------------------------------------------

func _test_curve() -> void:
	_progress.reset()
	_check(_progress.level == 1, "reset returns to level 1")
	_check(is_equal_approx(_progress.experience_required(), 8.0), "level 1 needs 8 exp")
	_check(is_equal_approx(_progress.experience_ratio(), 0.0), "a fresh run starts at 0 ratio")
	_progress.add_experience(3.0)
	_check(is_equal_approx(_progress.experience, 3.0), "exp accumulates")
	_check(is_equal_approx(_progress.experience_ratio(), 3.0 / 8.0), "ratio tracks progress")
	_progress.add_experience(5.0)
	_check(_progress.level == 2, "8 exp levels up")
	_check(_progress.pending_choices == 1, "each level queues one choice")
	_check(is_equal_approx(_progress.experience, 0.0), "exp carries the remainder")
	_check(is_equal_approx(_progress.experience_required(), 12.0), "level 2 needs 12 exp")
	_progress.add_experience(12.0 + 16.0 + 1.0)
	_check(_progress.level == 4, "one grant can cross several levels")
	_check(_progress.pending_choices == 3, "every level queues its own choice")
	_check(_progress.add_experience(0.0) == null, "zero exp is a no-op")


# --- 卡池规则 -------------------------------------------------------------

func _test_card_pool() -> void:
	_progress.reset()
	var sword_cards: Array[UpgradeCard] = UpgradePool.candidates({}, &"longsword", 1.0)
	var leaked: bool = false
	var saw_gale: bool = false
	var saw_yoyo: bool = false
	for card: UpgradeCard in sword_cards:
		if card.scope == UpgradeCard.Scope.WEAPON:
			leaked = leaked or card.weapon_id != &"longsword"
			saw_yoyo = saw_yoyo or card.weapon_id == &"yoyo"
		saw_gale = saw_gale or card.id == &"sword_gale"
	_check(not leaked, "weapon cards never leak a different weapon")
	_check(saw_gale, "longsword cards are offered while holding the longsword")
	_check(not saw_yoyo, "yoyo cards are hidden while holding the longsword")

	var yoyo_cards: Array[UpgradeCard] = UpgradePool.candidates({}, &"yoyo", 1.0)
	var saw_orbit: bool = false
	var foreign_weapon: bool = false
	for card: UpgradeCard in yoyo_cards:
		if card.scope == UpgradeCard.Scope.WEAPON and card.weapon_id != &"yoyo":
			foreign_weapon = true
		saw_orbit = saw_orbit or card.id == &"yoyo_orbit"
	_check(saw_orbit, "the orbit ball card is offered while holding the yoyo")
	_check(not foreign_weapon, "no other weapon cards appear for the yoyo")

	var low_cards: Array[UpgradeCard] = UpgradePool.candidates({}, &"longsword", 0.5)
	var high_cards: Array[UpgradeCard] = UpgradePool.candidates({}, &"longsword", 0.9)
	var low_cost: bool = false
	var high_cost: bool = false
	for card: UpgradeCard in low_cards:
		low_cost = low_cost or card.scope == UpgradeCard.Scope.COST
	for card: UpgradeCard in high_cards:
		high_cost = high_cost or card.scope == UpgradeCard.Scope.COST
	_check(not low_cost, "cost cards are hidden below their health gate")
	_check(high_cost, "cost cards appear above their health gate")

	var capped: Array[UpgradeCard] = UpgradePool.candidates({&"constitution": 4}, &"longsword", 1.0)
	var still_offered: bool = false
	for card: UpgradeCard in capped:
		still_offered = still_offered or card.id == &"constitution"
	_check(not still_offered, "maxed cards leave the pool")

	var choices: Array[UpgradeCard] = _progress.roll_choices(&"longsword", 1.0)
	_check(choices.size() == 3, "a roll offers three cards")
	_check(choices[0].id != choices[1].id and choices[1].id != choices[2].id and choices[0].id != choices[2].id,
		"a roll never repeats a card")
	var weapon_only: bool = true
	for card: UpgradeCard in choices:
		if card.scope == UpgradeCard.Scope.WEAPON:
			weapon_only = weapon_only and card.weapon_id == &"longsword"
	_check(weapon_only, "rolled weapon cards match the equipped weapon")

	_progress.rolls_since_rare = UpgradePool.PITY_ROLLS
	var pity: Array[UpgradeCard] = _progress.roll_choices(&"longsword", 1.0)
	_check(UpgradePool.contains_rare(pity), "pity forces a rare card")


# --- 选卡与层数 -----------------------------------------------------------

func _test_take_card() -> void:
	_progress.reset()
	_progress.pending_choices = 1
	_check(_progress.take_card(&"sharp"), "a valid card can be taken")
	_check(_progress.stacks_of(&"sharp") == 1, "the card stack is recorded")
	_check(_progress.pending_choices == 0, "taking a card spends the pending choice")
	_check(not _progress.take_card(&"not_a_real_card"), "unknown cards are rejected")
	for _index: int in 4:
		_progress.take_card(&"sharp")
	_check(_progress.stacks_of(&"sharp") == 5, "a card reaches its max stacks")
	_check(not _progress.take_card(&"sharp"), "a card cannot exceed its max stacks")
	_check(is_equal_approx(_progress.damage_mult(), 1.6), "five sharp cards give +60% damage")


# --- 数值加成落到玩家身上 -------------------------------------------------

func _test_player_aggregates() -> void:
	_progress.reset()
	_make_player()
	_check(is_equal_approx(_player.max_health, 100.0), "baseline max health is 100")
	_check(is_equal_approx(_player.health, 100.0), "baseline current health is 100")
	_check(is_equal_approx(_player.health_component.defense, 0.0), "baseline defense is 0")
	_check(_player.weapon_controller.equipped_weapon == null, "no weapon without an inventory")

	_take(&"constitution", 4)
	_player.apply_progress()
	_check(is_equal_approx(_player.max_health, 160.0), "4x constitution raises max health to 160")
	_check(is_equal_approx(_player.health_component.max_health, 160.0), "the health component follows the aggregate")
	_check(is_equal_approx(_player.health, 160.0), "new max health tops up current health immediately")

	_take(&"ironhide", 3)
	_player.apply_progress()
	_check(is_equal_approx(_player.defense, 12.0), "3x ironhide adds 12 flat defense")
	_check(is_equal_approx(_player.health_component.defense, 12.0), "flat defense reaches the health component")

	_take(&"toughness", 3)
	_check(is_equal_approx(_progress.damage_taken_mult(), 0.82), "3x toughness cuts incoming damage by 18%")

	var before: float = _player.health
	_player.take_damage(100.0)
	_check(is_equal_approx(before - _player.health, 70.0), "incoming damage applies the ratio then the flat defense")

	_take(&"swift", 2)
	_check(is_equal_approx(_player._move_speed(), 220.0 * 1.16), "swift raises move speed")

	_take(&"sharp", 2)
	_check(is_equal_approx(_progress.damage_mult(), 1.24), "sharp raises outgoing damage")

	_take(&"mighty", 2)
	_check(is_equal_approx(_progress.knockback_mult(), 1.5), "mighty raises knockback")

	_take(&"scavenger", 2)
	_check(is_equal_approx(_player.pickup_radius_tiles(), 3.5), "scavenger widens the pickup radius")

	_take(&"keen", 2)
	_take(&"lethal", 2)
	var sword: WeaponDefinition = _progress.build_weapon(LONGSWORD)
	_check(is_equal_approx(sword.critical_chance, 0.04 + 0.06), "keen adds crit chance to the weapon")
	_check(is_equal_approx(sword.critical_multiplier, 2.0 + 0.6), "lethal adds crit damage to the weapon")

	_take(&"haste", 2)
	var hasted: WeaponDefinition = _progress.build_weapon(LONGSWORD)
	var speed: float = 1.16
	_check(is_equal_approx(hasted.windup_seconds, LONGSWORD.windup_seconds / speed), "haste shortens the windup")
	_check(is_equal_approx(hasted.recovery_seconds, LONGSWORD.recovery_seconds / speed), "haste shortens the recovery")
	_check(is_equal_approx(hasted.reuse_delay, LONGSWORD.reuse_delay / speed), "haste shortens the reuse delay")
	_check(hasted.attacks_per_second() > LONGSWORD.attacks_per_second(), "haste raises the attack rate")
	_check(is_equal_approx(LONGSWORD.windup_seconds, 0.08), "build_weapon never mutates the base windup")
	_check(is_equal_approx(LONGSWORD.critical_chance, 0.04), "build_weapon never mutates the base crit chance")
	_check(is_equal_approx(LONGSWORD.knockback, 110.0), "build_weapon never mutates the base knockback")

	var regen_player: float = _player.health
	_take(&"regen", 2)
	_player._combat_lockout = 0.0
	_player._tick_progress(1.0)
	_check(_player.health > regen_player, "regen heals out of combat")
	_player._combat_lockout = 4.0
	var locked: float = _player.health
	_player._tick_progress(1.0)
	_check(is_equal_approx(_player.health, locked), "regen stays off while in combat")

	_take(&"last_stand")
	_player.health = _player.max_health * 0.2
	var low: float = _player.health
	_player.take_damage(100.0)
	var low_damage: float = low - _player.health
	_player.health = _player.max_health
	var full: float = _player.health
	_player.take_damage(100.0)
	_check(low_damage < full - _player.health, "last stand softens damage below 30% health")


# --- 武器卡改造 -----------------------------------------------------------

func _test_weapon_cards() -> void:
	_progress.reset()
	_take(&"sword_gale")
	var sword: SwingWeaponDefinition = _progress.build_weapon(LONGSWORD) as SwingWeaponDefinition
	_check(sword != null, "gale still builds a swing weapon")
	_check(is_equal_approx(sword.arc_degrees, 210.0), "gale widens the longsword arc by 60 degrees")
	_check(is_equal_approx(sword.damage, LONGSWORD.damage * 0.85), "gale trades 15% damage for the wider arc")
	_check(sword.validation_errors().is_empty(), "the widened longsword stays valid")
	_check(_controller_accepts(sword), "the widened longsword can be equipped")

	_progress.reset()
	_take(&"sword_heavy")
	var heavy: SwingWeaponDefinition = _progress.build_weapon(LONGSWORD) as SwingWeaponDefinition
	_check(is_equal_approx(heavy.damage, LONGSWORD.damage * 1.5), "heavy strike adds 50% damage")
	_check(is_equal_approx(heavy.windup_seconds, LONGSWORD.windup_seconds + 0.12), "heavy strike adds windup")

	_progress.reset()
	_take(&"sword_combo")
	_check(is_equal_approx(_progress.build_weapon(LONGSWORD).combo_window, 0.15), "combo window reaches the weapon")

	_progress.reset()
	_take(&"sword_press")
	var press: WeaponDefinition = _progress.build_weapon(LONGSWORD)
	_check(is_equal_approx(press.knockback, LONGSWORD.knockback * 2.0), "sword press doubles knockback")
	_check(is_equal_approx(press.lunge_tiles, 1.0), "sword press adds a lunge")

	_progress.reset()
	_take(&"staff_reach")
	var reach: DepthStrikeWeaponDefinition = _progress.build_weapon(LONG_STAFF) as DepthStrikeWeaponDefinition
	_check(is_equal_approx(reach.shaft_length, LONG_STAFF.shaft_length * 1.4), "staff reach lengthens the shaft")
	_check(is_equal_approx(reach.hit_width, LONG_STAFF.hit_width + 2.0), "staff reach widens the hit box")
	_check(_controller_accepts(reach), "the longer staff can be equipped")

	_progress.reset()
	_take(&"staff_reverse")
	var reverse: DepthStrikeWeaponDefinition = _progress.build_weapon(LONG_STAFF) as DepthStrikeWeaponDefinition
	_check(reverse.reverse_strike, "reverse strike flips the staff sweep")
	_check(is_equal_approx(reverse.damage, LONG_STAFF.damage * 1.25), "reverse strike adds 25% damage")

	_progress.reset()
	_take(&"staff_whirl")
	var whirl: DepthStrikeWeaponDefinition = _progress.build_weapon(LONG_STAFF) as DepthStrikeWeaponDefinition
	_check(is_equal_approx(whirl.arc_degrees, 360.0), "whirl turns the staff into a full circle")
	_check(is_equal_approx(whirl.active_seconds, 0.45), "whirl extends the active sweep")
	_check(is_equal_approx(whirl.reuse_delay, 0.20), "whirl slows the recovery loop")
	_check(whirl.validation_errors().is_empty(), "the 360 degree staff passes validation")
	_check(_controller_accepts(whirl), "the 360 degree staff can actually be equipped")
	_check(whirl.attacks_per_second() < LONG_STAFF.attacks_per_second(), "whirl attacks slower than the base staff")

	# 迅捷必须对旋风写死的绝对值同样有效，不能被绝对赋值吃掉。
	_progress.reset()
	_take(&"staff_whirl")
	_take(&"haste", 4)
	var fast_whirl: DepthStrikeWeaponDefinition = _progress.build_weapon(LONG_STAFF) as DepthStrikeWeaponDefinition
	var haste_speed: float = 1.32
	_check(is_equal_approx(fast_whirl.reuse_delay, 0.20 / haste_speed), "haste still shortens the whirl reuse delay")
	_check(is_equal_approx(fast_whirl.active_seconds, 0.45 / haste_speed), "haste still shortens the whirl sweep")
	_check(fast_whirl.attacks_per_second() > whirl.attacks_per_second(), "haste makes the whirl staff faster")
	_check(fast_whirl.validation_errors().is_empty(), "the hasted whirl staff stays valid")
	_check(_controller_accepts(fast_whirl), "the hasted whirl staff can be equipped")

	_progress.reset()
	_take(&"yoyo_long", 1)
	_take(&"haste", 4)
	var fast_yoyo: YoyoWeaponDefinition = _progress.build_weapon(YOYO) as YoyoWeaponDefinition
	_check(fast_yoyo.recovery_seconds >= fast_yoyo.return_seconds(), "haste never breaks the yoyo recovery invariant")
	_check(fast_yoyo.validation_errors().is_empty(), "the hasted long-string yoyo stays valid")
	_check(_controller_accepts(fast_yoyo), "the hasted long-string yoyo can be equipped")

	_progress.reset()
	_take(&"staff_bind")
	var bind: WeaponDefinition = _progress.build_weapon(LONG_STAFF)
	_check(is_equal_approx(bind.slow_ratio, 0.40), "bind carries its slow ratio")
	_check(is_equal_approx(bind.slow_seconds, 1.5), "bind carries its slow duration")

	_progress.reset()
	_take(&"yoyo_long")
	var long_yoyo: YoyoWeaponDefinition = _progress.build_weapon(YOYO) as YoyoWeaponDefinition
	_check(is_equal_approx(long_yoyo.max_range, YOYO.max_range * 1.6), "long string extends the yoyo range")
	_check(long_yoyo.recovery_seconds >= long_yoyo.return_seconds(), "long string keeps recovery covering the return")
	_check(long_yoyo.validation_errors().is_empty(), "the longer yoyo stays valid")
	_check(_controller_accepts(long_yoyo), "the longer yoyo can be equipped")

	_progress.reset()
	_take(&"yoyo_orbit")
	_check(_progress.build_weapon(YOYO).orbit_balls == 1, "the orbit card adds one orbiting ball")
	_check(YOYO.orbit_balls == 0, "the base yoyo resource stays clean")
	_check(_progress.build_weapon(LONGSWORD).orbit_balls == 0, "the longsword never gains an orbit ball")

	# 武器卡不能串味：已选卡里混入别的武器的改造时，只作用在自己的武器上
	_progress.reset()
	_take(&"yoyo_orbit")
	_take(&"staff_reach")
	_take(&"sword_gale")
	var isolated_sword: SwingWeaponDefinition = _progress.build_weapon(LONGSWORD) as SwingWeaponDefinition
	var isolated_staff: DepthStrikeWeaponDefinition = _progress.build_weapon(LONG_STAFF) as DepthStrikeWeaponDefinition
	var isolated_yoyo: YoyoWeaponDefinition = _progress.build_weapon(YOYO) as YoyoWeaponDefinition
	_check(is_equal_approx(isolated_sword.arc_degrees, 210.0), "the longsword only takes its own arc card")
	_check(is_equal_approx(isolated_staff.arc_degrees, LONG_STAFF.arc_degrees), "the staff ignores the sword arc card")
	_check(is_equal_approx(isolated_staff.shaft_length, LONG_STAFF.shaft_length * 1.4), "the staff still gets its own reach card")
	_check(is_equal_approx(isolated_yoyo.max_range, YOYO.max_range), "the yoyo ignores every other weapon card")
	_check(isolated_yoyo.orbit_balls == 1, "the yoyo still gets its own orbit ball")
	_check(isolated_sword.orbit_balls == 0 and isolated_staff.orbit_balls == 0, "orbit balls stay on the yoyo")


# --- 经验球 ---------------------------------------------------------------

func _test_experience_orb() -> void:
	_progress.reset()
	_make_player()
	_player.global_position = Vector2.ZERO
	var orb: ExperienceOrb = ExperienceOrb.new()
	orb.bind(5.0, _player)
	_arena.add_child(orb)
	orb.global_position = Vector2(200.0, 0.0)
	_check(is_equal_approx(orb.amount, 5.0), "the orb stores its value")
	orb._process(0.4)
	_check(orb.global_position.distance_to(Vector2(200.0, 0.0)) < 1.0, "the orb pauses where the monster died")
	_check(is_equal_approx(_progress.experience, 0.0), "a paused orb grants no experience")
	orb._process(0.1)
	_check(is_equal_approx(_progress.experience, 0.0), "the orb is still on its way")
	var guard: int = 0
	while _progress.experience < 5.0 and guard < 200:
		guard += 1
		orb._process(0.05)
	_check(is_equal_approx(_progress.experience, 5.0), "the orb flies in and grants its experience")


# --- 击杀与炼金经验 -------------------------------------------------------

func _test_kill_and_alchemy() -> void:
	_progress.reset()
	_check(is_equal_approx(_progress.kill_experience(10, 0), 10.0), "floor 0 kills give the base experience")
	_check(is_equal_approx(_progress.kill_experience(10, 2), 12.4), "kill experience scales with the floor")
	_take(&"blood_knowledge")
	_check(is_equal_approx(_progress.kill_experience(10, 0), 12.5), "the kill experience bonus applies")
	_check(is_equal_approx(_progress.heal_mult(), 0.7), "blood knowledge cuts healing by 30%")

	_progress.reset()
	_check(is_equal_approx(_progress.alchemy_experience("1-2", 1), 18.0), "the first craft of a recipe pays the discovery bonus")
	_check(is_equal_approx(_progress.alchemy_experience("1-2", 1), 6.0), "repeating a recipe only pays the base")
	_check(is_equal_approx(_progress.alchemy_experience("3-4", 2), 26.0), "high level products pay the level bonus")
	_take(&"alchemy_study")
	_check(is_equal_approx(_progress.alchemy_experience("5-6", 1), 27.0), "material study raises alchemy experience")


# --- 怪物侧钩子 -----------------------------------------------------------

func _test_monster_hooks() -> void:
	_progress.reset()
	_make_player()
	_player.global_position = Vector2.ZERO
	_player.health = _player.max_health
	var monster: BaseMonster = GIVE_MONSTER.instantiate() as BaseMonster
	_arena.add_child(monster)
	monster.global_position = Vector2(30.0, 0.0)
	monster.set_physics_process(false)
	var monster_health: HealthComponent = monster.get_node("Health") as HealthComponent
	var base_speed: float = monster.movement_speed()
	_check(base_speed > 0.0, "monsters have a baseline speed")
	monster.apply_slow(0.4, 1.5)
	_check(is_equal_approx(monster.movement_speed(), base_speed * 0.6), "bind slows the monster by 40%")
	monster.apply_slow(0.2, 1.0)
	_check(is_equal_approx(monster.movement_speed(), base_speed * 0.6), "the stronger slow wins")

	_take(&"lifesteal", 2)
	_player.health = 50.0
	_player.on_monster_killed(monster, 0.0)
	_check(is_equal_approx(_player.health, 60.0), "lifesteal heals on kill")

	_progress.reset()
	_take(&"chain")
	var neighbour: BaseMonster = GIVE_MONSTER.instantiate() as BaseMonster
	_arena.add_child(neighbour)
	neighbour.global_position = Vector2(40.0, 0.0)
	neighbour.set_physics_process(false)
	var neighbour_health: HealthComponent = neighbour.get_node("Health") as HealthComponent
	var neighbour_before: float = neighbour_health.current_health
	_player.on_monster_killed(monster, 20.0)
	_check(is_equal_approx(neighbour_before - neighbour_health.current_health, 10.0), "chain damage hits a nearby monster")
	_check(is_equal_approx(monster_health.current_health, monster_health.max_health), "chain damage never hits the killed monster")

	_arena.remove_child(monster)
	monster.free()
	_arena.remove_child(neighbour)
	neighbour.free()


# --- 环绕球 ---------------------------------------------------------------

func _test_orbit_ball() -> void:
	_progress.reset()
	_make_player()
	_player.global_position = Vector2.ZERO
	_take(&"yoyo_orbit")
	var yoyo: YoyoWeaponDefinition = _progress.build_weapon(YOYO) as YoyoWeaponDefinition
	yoyo.critical_chance = 0.0
	var controller: WeaponController = _player.weapon_controller
	_check(controller.equip(yoyo), "the orbit yoyo equips")
	var target: HealthComponent = _target(Vector2(40.0, 0.0))
	await _sync_physics()

	controller.set_aim(Vector2.RIGHT * 40.0)
	controller.set_trigger_pressed(true)
	controller._physics_process(0.01)
	var attack: WeaponAttack = null
	for child: Node in controller.get_children():
		if child is WeaponAttack:
			attack = child as WeaponAttack
	_check(attack != null, "holding the trigger starts a yoyo attack")
	if attack == null:
		return
	attack.set_physics_process(false)
	var ball: OrbitBall = null
	for child: Node in attack.get_children():
		if child is OrbitBall:
			ball = child as OrbitBall
	_check(ball != null, "an orbit ball spawns while the yoyo is out")
	if ball == null:
		return
	ball.set_physics_process(false)

	var before: float = target.current_health
	ball._physics_process(0.01)
	_check(is_equal_approx(before - target.current_health, 12.0 * 0.6), "the orbit ball deals its share of weapon damage")

	controller.cancel_attack()
	await process_frame
	_check(not is_instance_valid(ball), "the orbit ball disappears when the attack ends")

	# 长剑没有环绕球卡，不会凭空长出球
	_progress.reset()
	var sword: WeaponDefinition = _progress.build_weapon(LONGSWORD)
	_check(controller.equip(sword), "the plain longsword equips")
	controller.set_trigger_pressed(true)
	controller._physics_process(0.01)
	var sword_attack: WeaponAttack = null
	for child: Node in controller.get_children():
		if child is WeaponAttack:
			sword_attack = child as WeaponAttack
	var sword_balls: int = 0
	if sword_attack != null:
		sword_attack.set_physics_process(false)
		for child: Node in sword_attack.get_children():
			if child is OrbitBall:
				sword_balls += 1
	_check(sword_balls == 0, "no orbit ball appears for weapons without the card")
	controller.cancel_attack()


# --- 升级流程串联 ---------------------------------------------------------

func _test_upgrade_flow() -> void:
	_progress.reset()
	paused = false
	var scene_root: Node2D = Node2D.new()
	root.add_child(scene_root)
	var hud: CanvasLayer = CanvasLayer.new()
	hud.name = "GameHUD"
	hud.add_to_group("game_hud")
	scene_root.add_child(hud)
	var panel: UpgradePanel = PANEL_SCENE.instantiate() as UpgradePanel
	hud.add_child(panel)
	var manager: UpgradeManager = UpgradeManager.new()
	manager.name = "UpgradeManager"
	hud.add_child(manager)
	var player: PlayerCharacter = PLAYER_SCENE.instantiate() as PlayerCharacter
	player.add_to_group("player")
	scene_root.add_child(player)
	player.set_physics_process(false)
	await process_frame
	await process_frame
	_check(not panel.visible, "the panel starts hidden")

	_progress.add_experience(8.0)
	await process_frame
	await process_frame
	_check(panel.visible, "a level up opens the choice panel")
	_check(paused, "the panel pauses the tree")
	_check(panel._cards.size() == 3, "the panel shows three choices")

	var chosen: StringName = panel._cards[0].id
	panel._on_card_pressed(chosen)
	await process_frame
	await process_frame
	_check(_progress.pending_choices == 0, "the pending choice is spent")
	_check(_progress.stacks_of(chosen) == 1, "the chosen card is recorded")
	_check(not panel.visible, "the panel closes after the last choice")
	_check(not paused, "the tree resumes after the last choice")

	# 连升两级：面板应连续弹出两次
	_progress.add_experience(12.0 + 16.0)
	await process_frame
	await process_frame
	_check(panel.visible and _progress.pending_choices == 2, "a double level up queues two panels")
	panel._on_card_pressed(panel._cards[0].id)
	await process_frame
	await process_frame
	_check(panel.visible, "the second choice is offered right away")
	_check(paused, "the tree stays paused between the two choices")
	panel._on_card_pressed(panel._cards[0].id)
	await process_frame
	await process_frame
	_check(not panel.visible and not paused, "the tree resumes once both choices are made")

	paused = false
	scene_root.free()
	_progress.reset()


# --- HUD 等级与经验条 -----------------------------------------------------

func _test_hud_readout() -> void:
	_progress.reset()
	var hud_scene: PackedScene = load("res://scenes/ui/hud.tscn") as PackedScene
	_check(hud_scene != null, "the HUD scene loads")
	var hud: Control = hud_scene.instantiate() as Control
	root.add_child(hud)
	await process_frame
	var level_label: Label = hud.get_node_or_null("LevelLabel") as Label
	var fill: ColorRect = hud.get_node_or_null("XpBarBackground/XpBarFill") as ColorRect
	_check(level_label != null, "the HUD builds a level label")
	_check(fill != null, "the HUD builds an experience bar")
	if level_label == null or fill == null:
		hud.free()
		return
	_check(level_label.text.contains("等级 1"), "the HUD shows the current level")
	_check(is_equal_approx(fill.offset_right, 0.0), "the experience bar starts empty")
	_progress.add_experience(4.0)
	_check(is_equal_approx(fill.offset_right, 240.0 * 0.5), "the bar tracks the experience ratio")
	_progress.add_experience(4.0)
	_check(level_label.text.contains("等级 2"), "the HUD updates on level up")
	_check(is_equal_approx(fill.offset_right, 0.0), "the bar resets for the next level")
	hud.free()
	await process_frame


# --- 场景接线 -------------------------------------------------------------

func _test_scene_wiring() -> void:
	var world_scene: PackedScene = load("res://scenes/game/game_world.tscn") as PackedScene
	_check(world_scene != null, "the game world scene loads")
	var world: Node = world_scene.instantiate()
	var hud: Node = world.get_node_or_null("GameHUD")
	_check(hud != null, "GameHUD exists in the game world")
	if hud != null:
		_check(hud.get_node_or_null("UpgradePanel") is UpgradePanel, "the upgrade panel is wired into the HUD")
		_check(hud.get_node_or_null("UpgradeManager") is UpgradeManager, "the upgrade manager is wired into the HUD")
	world.free()


# --- 开新局重置 -----------------------------------------------------------

func _test_reset() -> void:
	_progress.reset()
	_progress.add_experience(500.0)
	_take(&"sharp")
	_check(_progress.level > 1 and not _progress.cards_taken.is_empty(), "the run has progress to clear")
	_progress.reset()
	_check(_progress.level == 1, "reset clears the level")
	_check(is_equal_approx(_progress.experience, 0.0), "reset clears experience")
	_check(_progress.pending_choices == 0, "reset clears pending choices")
	_check(_progress.cards_taken.is_empty(), "reset clears taken cards")
	_check(is_equal_approx(_progress.damage_mult(), 1.0), "reset clears aggregated bonuses")
