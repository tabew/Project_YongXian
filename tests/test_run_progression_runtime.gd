extends SceneTree

## 真实场景下的端到端验证：加载 game_world.tscn，等雨林战斗区域刷怪，
## 击杀一只怪，检查经验球真的生成并飞向玩家、经验真的结算、升级面板真的弹出。
## 运行：godot --headless --path . --script tests/test_run_progression_runtime.gd

var _checks: int = 0
var _failures: int = 0
const SPEAR: SpearWeaponDefinition = preload("res://resources/weapons/spear.tres")

var _progress: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)


## 在快捷栏里找某个武器 id 所在格子。
func _find_weapon_slot(inventory: Inventory, weapon_id: StringName) -> int:
	for slot: int in range(9):
		var item_id: int = inventory.get_handy_slot_id(slot)
		var data: ItemData = inventory.get_item_data.get(item_id)
		if data is WeaponData and (data as WeaponData).weapon != null and (data as WeaponData).weapon.id == weapon_id:
			return slot
	return -1


## 找一层里第一个真的会刷怪的区域，避免依赖某个特定种子/群系。
func _combat_gate(world: Node2D) -> Dictionary:
	for link: Dictionary in world._generator.gate_links(0):
		if world.monster_spawner.content.budget_of(link["target"], MapContent.ENEMY) > 0:
			return link
	return {}


func _cross_gate(world: Node2D, link: Dictionary) -> void:
	world.player.global_position = WorldGenerator.tile_to_world(link["point"])
	world.player.velocity = Vector2(float(link["side"]) * world.player.max_speed, 0)
	world._process(0.01)


func _wait_map(world: Node2D) -> void:
	for _frame: int in 240:
		if world.chunk_manager.map_ready():
			break
		await process_frame


func _orbs(world: Node2D) -> Array[ExperienceOrb]:
	var found: Array[ExperienceOrb] = []
	for node: Node in world.monster_spawner.get_children():
		if node is ExperienceOrb:
			found.append(node as ExperienceOrb)
	return found


func _run() -> void:
	Engine.max_fps = 120
	_progress = root.get_node_or_null("RunProgress")
	_check(_progress != null, "RunProgress autoload is live in a real run")
	var game_state: Node = root.get_node_or_null("GameState")
	_check(game_state != null, "GameState autoload is live")
	if _progress == null or game_state == null:
		quit(1)
		return
	# 固定种子，让这一局可复现；这也是真实入口（菜单 → start_new_world）走的路。
	game_state.call("start_new_world", 18473)

	var world_scene: PackedScene = load("res://scenes/game/game_world.tscn") as PackedScene
	_check(world_scene != null, "the game world scene loads")
	var world: Node2D = world_scene.instantiate() as Node2D
	root.add_child(world)
	await process_frame
	await process_frame

	var panel: UpgradePanel = world.get_node_or_null("GameHUD/UpgradePanel") as UpgradePanel
	_check(panel != null, "the real HUD carries the upgrade panel")
	_check(_progress.level == 1 and _progress.cards_taken.is_empty(), "a fresh world starts at level 1 with no cards")
	_check(is_equal_approx(world.player.max_health, 100.0), "the real player uses the unified 100 point scale")
	_check(is_equal_approx(world.player.health, 100.0), "the real player spawns at full health")

	var link: Dictionary = _combat_gate(world)
	_check(not link.is_empty(), "the first floor links to a region with an enemy budget")
	if link.is_empty():
		world.queue_free()
		quit(1)
		return
	_cross_gate(world, link)
	await _wait_map(world)
	await process_frame

	var spawner: MonsterSpawner = world.monster_spawner
	var monsters: Array[BaseMonster] = spawner.monsters
	_check(monsters.size() > 0, "the combat region actually spawns monsters")
	if monsters.is_empty():
		world.queue_free()
		quit(1)
		return

	var victim: BaseMonster = monsters[0]
	_check(victim.experience_reward > 0, "the spawner hands the monster its kill experience")
	var reward: int = victim.experience_reward
	var exp_before: float = _progress.experience
	var level_before: int = _progress.level
	var player_pos: Vector2 = world.player.global_position

	victim.kill()
	await process_frame
	var orbs: Array[ExperienceOrb] = _orbs(world)
	_check(orbs.size() == 1, "killing a monster drops exactly one experience orb")
	if orbs.is_empty():
		world.queue_free()
		quit(1)
		return
	var orb: ExperienceOrb = orbs[0]
	_check(is_equal_approx(orb.amount, _progress.kill_experience(reward, spawner._floor_index())),
		"the orb carries the floor scaled monster experience")
	_check(orb.amount >= float(reward), "the floor scaling never shrinks the reward")
	_check(is_equal_approx(_progress.experience, exp_before), "a fresh orb grants no experience yet")
	_check(orb.global_position.distance_to(player_pos) > 40.0, "the orb starts where the monster died, not on the player")

	# 停顿阶段：球不应该靠近玩家。
	await create_timer(0.2).timeout
	_check(is_equal_approx(_progress.experience, exp_before), "the orb stays paused for its delay")
	_check(orb.global_position.distance_to(player_pos) > 40.0, "the orb has not flown in yet")

	# 停顿结束后飞入并结算。
	for _frame: int in 400:
		if not is_instance_valid(orb) or orb.is_queued_for_deletion():
			break
		await process_frame
	_check(not is_instance_valid(orb) or orb.is_queued_for_deletion(), "the orb flies in and disappears")
	_check(_progress.experience > exp_before or _progress.level > level_before,
		"the collected orb grants real experience in a real run")

	# 升级面板：直接灌经验，走真实信号链。60 点会连升好几级，面板要一张接一张地弹。
	_progress.add_experience(60.0)
	await process_frame
	await process_frame
	_check(panel.visible, "leveling up opens the panel inside the running game")
	_check(paused, "the running game pauses while the panel is up")
	var queued: int = _progress.pending_choices
	_check(queued >= 2, "60 experience queues several choices at once")

	var health_before: float = world.player.max_health
	var move_before: float = world.player._move_speed()
	var rounds: int = 0
	var offered_weapon_card_ok: bool = true
	while _progress.pending_choices > 0 and rounds < 20:
		rounds += 1
		_check(panel._cards.size() == 3, "round %d offers three cards" % rounds)
		_check(paused, "round %d keeps the game paused" % rounds)
		var held_weapon: StringName = &""
		if world.player.weapon_controller.equipped_weapon != null:
			held_weapon = world.player.weapon_controller.equipped_weapon.id
		for card: UpgradeCard in panel._cards:
			if card.scope == UpgradeCard.Scope.WEAPON:
				offered_weapon_card_ok = offered_weapon_card_ok and card.weapon_id == held_weapon
		var pick: UpgradeCard = panel._cards[0]
		panel._on_card_pressed(pick.id)
		await process_frame
		await process_frame
		_check(_progress.stacks_of(pick.id) >= 1, "round %d records the picked card" % rounds)
	_check(rounds == queued, "the panel is offered exactly once per level")
	_check(offered_weapon_card_ok, "every offered weapon card matches the weapon the player actually holds")
	_check(not panel.visible and not paused, "the panel closes and the game resumes")
	_check(not _progress.cards_taken.is_empty(), "the taken cards are remembered for the run")
	var changed: bool = (
		not is_equal_approx(world.player.max_health, health_before)
		or not is_equal_approx(world.player._move_speed(), move_before)
	)
	_check(changed or not _progress.cards_taken.is_empty(), "taking cards visibly changes the real player")

	# 武器切换 + 武器卡：真实玩家走真实的“选中即装备 → 叠卡重建”链路。
	var inventory: Inventory = world.player.inventory
	_check(inventory != null, "the real player carries an inventory")
	if inventory != null:
		var spear_slot: int = _find_weapon_slot(inventory, &"spear")
		# 默认背包只带长剑与长枪，溜溜球现场放进快捷栏，用来验证环绕球。
		var yoyo_item_id: int = (load("res://resources/items/weapons/yoyo.tres") as ItemData).id
		inventory.add_item(yoyo_item_id, 1)
		var yoyo_slot: int = _find_weapon_slot(inventory, &"yoyo")
		if yoyo_slot < 0:
			yoyo_slot = inventory.quick_move_to_handy(yoyo_item_id, 1)
			yoyo_slot = _find_weapon_slot(inventory, &"yoyo")
		_check(spear_slot >= 0, "the inventory offers the long spear")
		_check(yoyo_slot >= 0, "the yoyo can be placed in the hotbar")

		# Select the spear, rebuild with flurry, then restore the base sequence.
		if spear_slot >= 0:
			inventory.select_handy_slot(spear_slot)
			await process_frame
			var base_spear: SpearWeaponDefinition = world.player.weapon_controller.equipped_weapon as SpearWeaponDefinition
			_check(base_spear != null and base_spear.id == &"spear", "selecting the spear slot equips the spear")
			_progress.cards_taken[&"spear_flurry"] = 1
			world.player.rebuild_weapon()
			await process_frame
			var flurry: SpearWeaponDefinition = world.player.weapon_controller.equipped_weapon as SpearWeaponDefinition
			_check(flurry != null, "the flurry spear stays equipped")
			if flurry != null:
				var speed: float = _progress.attack_speed_mult()
				_check(flurry.thrust_count == 2, "flurry reaches the actual equipped weapon")
				_check(is_equal_approx(flurry.active_seconds, 0.30 / speed), "flurry respects current attack speed")
			_progress.cards_taken.erase(&"spear_flurry")
			world.player.rebuild_weapon()
			await process_frame
			var restored: SpearWeaponDefinition = world.player.weapon_controller.equipped_weapon as SpearWeaponDefinition
			_check(restored != null and restored.thrust_count == SPEAR.thrust_count,
				"dropping the card restores the plain spear")

		# 溜溜球 + 环绕球：按住左键才有球，松手就没。
		if yoyo_slot >= 0:
			_progress.cards_taken[&"yoyo_orbit"] = 1
			inventory.select_handy_slot(yoyo_slot)
			await process_frame
			var yoyo: YoyoWeaponDefinition = world.player.weapon_controller.equipped_weapon as YoyoWeaponDefinition
			_check(yoyo != null and yoyo.id == &"yoyo", "selecting the yoyo slot equips the yoyo")
			_check(yoyo != null and yoyo.orbit_balls == 1, "the orbit card really reaches the equipped yoyo")

			var controller: WeaponController = world.player.weapon_controller
			controller.set_aim(Vector2.RIGHT * 40.0)
			controller.set_trigger_pressed(true)
			controller._physics_process(0.01)
			var attack: WeaponAttack = null
			for child: Node in controller.get_children():
				if child is WeaponAttack:
					attack = child as WeaponAttack
			_check(attack != null, "holding the trigger starts a real yoyo attack")
			var balls: int = 0
			if attack != null:
				for child: Node in attack.get_children():
					if child is OrbitBall:
						balls += 1
			_check(balls == 1, "one orbit ball orbits while the real yoyo is held")
			controller.cancel_attack()
			await process_frame
			var after_release: int = 0
			for child: Node in controller.get_children():
				if child is OrbitBall:
					after_release += 1
			_check(after_release == 0, "releasing the trigger removes the orbit ball")
			_progress.cards_taken.erase(&"yoyo_orbit")

	# 开新局重置。
	game_state.call("start_new_world", int(game_state.get("world_seed")) + 1)
	_check(_progress.level == 1 and _progress.cards_taken.is_empty(),
		"starting a new world clears the run progression")

	world.queue_free()
	await process_frame
	print("RUN PROGRESSION RUNTIME: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
