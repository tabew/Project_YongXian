extends SceneTree

const SEED: int = 1
const FINAL_BOSS_SPAWN: MonsterSpawnData = preload("res://resources/monsters/final_boss_spawn_data.tres")
const MAX_GAME_SECONDS: float = 420.0
const MAX_WALL_MILLISECONDS: int = 300000

var _combat_time: float = 0.0
var _player_hits: int = 0
var _rope_hits: int = 0
var _damage_events: int = 0
var _phase_events: Array[String] = []
var _attacks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func bosses_in(spawner: MonsterSpawner) -> Array[FinalBoss]:
	var bosses: Array[FinalBoss] = []
	for monster: BaseMonster in spawner.monsters:
		if monster is FinalBoss:
			bosses.append(monster as FinalBoss)
	return bosses


func pause_ordinary_monsters(spawner: MonsterSpawner) -> void:
	spawner.set_process(false)
	for monster: BaseMonster in spawner.monsters:
		if not monster is FinalBoss:
			monster.process_mode = Node.PROCESS_MODE_DISABLED


func _steer(direction: Vector2) -> void:
	var input: Dictionary[String, bool] = {
		"move_left": direction.x < -0.2,
		"move_right": direction.x > 0.2,
		"move_up": direction.y < -0.2,
		"move_down": direction.y > 0.2,
	}
	for action: String in input:
		if input[action]:
			Input.action_press(action)
		else:
			Input.action_release(action)


func _record_hit(_hit: CombatHit, box: CombatHurtbox, boss: FinalBoss) -> void:
	if box == boss.get_node("Hurtbox"):
		_player_hits += 1
	elif box.get_parent() is BossLasso:
		_rope_hits += 1


func _run() -> void:
	Engine.max_fps = 120
	Engine.time_scale = 1.0
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", SEED)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	var player := world.player as PlayerCharacter
	player.set_physics_process(false)
	var spec: MapSpec = world._generator.map_spec(world._generator.run.final_node())
	world._enter_map(spec.node_id, -1, spec.west_gate_y)
	var spawner := world.monster_spawner as MonsterSpawner
	var bosses: Array[FinalBoss] = bosses_in(spawner)
	if bosses.size() != 1:
		push_error("Expected exactly one fixed Boss for the playthrough")
		quit(1)
		return
	var boss: FinalBoss = bosses[0]
	boss.set_physics_process(false)
	for frame: int in 900:
		for monster: BaseMonster in spawner.monsters:
			if not monster is FinalBoss:
				monster.process_mode = Node.PROCESS_MODE_DISABLED
		if world.chunk_manager.map_ready() and spawner.get_pending_spawn_count() == 0:
			break
		await process_frame
	if bosses_in(spawner).size() != 1 or spawner.monsters.size() <= 1:
		push_error("Expected ordinary monsters alongside the fixed Boss")
		quit(1)
		return
	pause_ordinary_monsters(spawner)
	var boss_spawn_id: String = spawner._spawn_id(FINAL_BOSS_SPAWN, boss.original_spawn_tile)
	var use_spear: bool = OS.get_cmdline_user_args().has("--spear")
	if use_spear:
		player.inventory.select_handy_slot(1)
	var flags: PackedStringArray = OS.get_cmdline_user_args()
	var use_tank: bool = not flags.has("--starter") and not flags.has("--spear") and not flags.has("--ironhide")
	var use_ironhide: bool = use_tank or OS.get_cmdline_user_args().has("--ironhide")
	if use_ironhide:
		var progress: Node = root.get_node("RunProgress")
		progress.set("pending_choices", 10 if use_tank else 3)
		for index: int in 3:
			if not bool(progress.call("take_card", &"ironhide")):
				push_error("Failed to select a legal ironhide upgrade")
				quit(1)
				return
		if use_tank:
			for index: int in 4:
				if not bool(progress.call("take_card", &"constitution")):
					push_error("Failed to select a legal constitution upgrade")
					quit(1)
					return
			for index: int in 3:
				if not bool(progress.call("take_card", &"regen")):
					push_error("Failed to select a legal regen upgrade")
					quit(1)
					return
		player.apply_progress(true)
	var radius: float = 84.0 if use_spear else 58.0
	boss.phase_changed.connect(func(new_phase: int) -> void:
		_phase_events.append("%d@%.1fs" % [new_phase, _combat_time])
		print("BOSS_PLAY_PHASE: phase=%d time=%.1f player_health=%.1f" % [new_phase, _combat_time, player.health])
	)
	boss.attack_started.connect(func(kind: StringName) -> void:
		_attacks[kind] = int(_attacks.get(kind, 0)) + 1
	)
	player.weapon_controller.hit_landed.connect(_record_hit.bind(boss))
	player.health_component.damaged.connect(func(_hit: CombatHit, actual: float) -> void:
		_damage_events += 1
		if _damage_events <= 12:
			print("BOSS_PLAYER_HIT: time=%.1f damage=%.1f hp=%.1f state=%d" % [_combat_time, actual, player.health, boss.attack_state])
	)
	var entry: Vector2 = player.global_position
	for index: int in 16:
		var point: Vector2 = boss.global_position + Vector2.RIGHT.rotated(TAU * float(index) / 16.0) * radius
		if player.can_stand_at(point):
			player.global_position = point
			break
	if not player.can_stand_at(player.global_position) or player.global_position == entry:
		push_error("No nearby walkable arena position for player")
		quit(1)
		return
	var weapon: WeaponDefinition = player.weapon_controller.equipped_weapon
	if weapon == null:
		push_error("Player has no selected weapon in final room")
		quit(1)
		return
	print("BOSS_PLAY_START: seed=%d weapon=%s damage=%.1f health=%.1f defense=%.1f ironhide=%s tank=%s entry_distance=%.1f arena_distance=%.1f" % [SEED, weapon.id, weapon.damage, player.health, player.defense, use_ironhide, use_tank, entry.distance_to(boss.global_position), player.global_position.distance_to(boss.global_position)])
	Engine.time_scale = 4.0
	boss.set_physics_process(true)
	var start_ms: int = Time.get_ticks_msec()
	var last_logged_second: int = -1
	while _combat_time < MAX_GAME_SECONDS and Time.get_ticks_msec() - start_ms < MAX_WALL_MILLISECONDS:
		if player.health <= 0.0 or not is_instance_valid(boss) or boss.is_queued_for_deletion():
			break
		var relative: Vector2 = player.global_position - boss.global_position
		var direction: Vector2
		if relative.length() < radius - 6.0:
			direction = relative.normalized() if not relative.is_zero_approx() else Vector2.RIGHT
		elif relative.length() > radius + 10.0:
			direction = -relative.normalized()
		else:
			direction = relative.orthogonal().normalized()
		if player.fear_remaining > 0.0:
			direction = -direction
		_steer(direction)
		await physics_frame
		if not is_instance_valid(boss) or boss.is_queued_for_deletion() or player.health <= 0.0:
			break
		var delta: float = player.get_physics_process_delta_time()
		_combat_time += delta
		player._physics_process(delta)
		player.weapon_controller.set_aim(boss.global_position - player.global_position)
		player.weapon_controller.set_trigger_pressed(true)
		var elapsed_second: int = int(_combat_time)
		if elapsed_second % 15 == 0 and elapsed_second != last_logged_second:
			last_logged_second = elapsed_second
			print("BOSS_PLAY_TICK: time=%.1f phase=%d boss_hp=%.1f player_hp=%.1f distance=%.1f fear=%.1f stunned=%.1f hits=%d" % [_combat_time, boss.phase, (boss.get_node("Health") as HealthComponent).current_health, player.health, player.global_position.distance_to(boss.global_position), player.fear_remaining, player.stun_remaining, _player_hits])
	_steer(Vector2.ZERO)
	player.weapon_controller.set_trigger_pressed(false)
	var defeated: bool = not is_instance_valid(boss) or boss.is_queued_for_deletion()
	var victory: bool = defeated and player.health > 0.0
	var remaining: float = -1.0 if defeated else (boss.get_node("Health") as HealthComponent).current_health
	print("BOSS_PLAYTHROUGH: victory=%s phase=%d boss_hp=%.1f player_hp=%.1f duration=%.1f hits=%d rope_hits=%d damage_events=%d phases=%s attacks=%s" % [victory, -1 if defeated else boss.phase, remaining, player.health, _combat_time, _player_hits, _rope_hits, _damage_events, _phase_events, _attacks])
	if victory:
		await process_frame
		await process_frame
		var recorded: bool = bosses_in(spawner).is_empty() and spawner._defeated_spawn_ids.has(boss_spawn_id)
		world._enter_map(0)
		world._enter_map(spec.node_id, -1, spec.west_gate_y)
		for frame: int in 900:
			for monster: BaseMonster in spawner.monsters:
				if not monster is FinalBoss:
					monster.process_mode = Node.PROCESS_MODE_DISABLED
			if world.chunk_manager.map_ready() and spawner.get_pending_spawn_count() == 0:
				break
			await process_frame
		var no_respawn: bool = bosses_in(spawner).is_empty() and spawner._defeated_spawn_ids.has(boss_spawn_id) and not bool(world.hud.get("_boss_visible"))
		print("BOSS_PLAY_PERSISTENCE: kill_recorded=%s no_respawn=%s" % [recorded, no_respawn])
		victory = recorded and no_respawn
	world.queue_free()
	await process_frame
	quit(0 if victory else 1)
