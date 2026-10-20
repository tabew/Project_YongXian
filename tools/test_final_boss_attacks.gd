extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func wait_room(world: Node2D) -> void:
	for frame: int in 900:
		for monster: BaseMonster in world.monster_spawner.monsters:
			if not monster is FinalBoss:
				monster.process_mode = Node.PROCESS_MODE_DISABLED
		if world.chunk_manager.map_ready() and world.monster_spawner.get_pending_spawn_count() == 0:
			return
		await process_frame
	check(false, "boss_room_loaded")


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


func hit_boss(boss: FinalBoss, amount: float, from_player: bool = true) -> void:
	var hit := CombatHit.new()
	hit.source = boss.player if from_player else null
	hit.damage = amount
	hit.position = boss.global_position
	(boss.get_node("Health") as HealthComponent).receive_hit(hit)


func far_walkable_position(generator: WorldGenerator, spec: MapSpec, origin: Vector2) -> Vector2:
	var farthest: Vector2 = origin
	var best_distance: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 72841
	for tile: Vector2i in MapContent.pick_tiles(generator, spec.node_id, 128, rng):
		var position: Vector2 = WorldGenerator.tile_to_world(tile)
		var distance: float = position.distance_squared_to(origin)
		if distance > best_distance:
			best_distance = distance
			farthest = position
	return farthest


func _run() -> void:
	Engine.max_fps = 120
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 1)
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
		push_error("Expected exactly one fixed Boss in attack test")
		quit(1)
		return
	var boss: FinalBoss = bosses[0]
	boss.set_physics_process(false)
	await wait_room(world)
	check(bosses_in(spawner).size() == 1 and spawner.monsters.size() == 1, "boss_room_contains_only_one_fixed_boss")
	pause_ordinary_monsters(spawner)
	var far_position: Vector2 = far_walkable_position(world._generator, spec, boss.global_position)
	check(far_position.distance_to(boss.global_position) > 64.0 * WorldGenerator.TILE_SIZE, "far_target_is_inside_same_boss_room")
	check(boss.phase == 1 and boss.attack_state == FinalBoss.AttackState.WAIT, "boss_starts_in_first_attack_state")

	boss._start_normal_attack()
	check(boss.attack_state == FinalBoss.AttackState.SOULS and boss._missiles.size() >= 7 and boss._missiles.size() <= 8, "first_phase_creates_seven_or_eight_missiles")
	for missile: BossSoulMissile in boss._missiles:
		missile.set_physics_process(false)
	var first: BossSoulMissile = boss._missiles[0]
	check(BossSoulMissile.SPEED == 300.0 and is_equal_approx(first._speed, BossSoulMissile.SPEED) and first._remaining >= BossSoulMissile.LIFE_SECONDS, "soul_missile_uses_fixed_three_hundred_speed")
	var health_before: float = player.health
	player.global_position = first.global_position
	first._physics_process(0.01)
	check(is_equal_approx(player.health, health_before - 10.0) and is_equal_approx(player.fear_remaining, 0.0), "direct_missile_hit_deals_ten_without_fear")
	player.apply_fear(2.0)
	check(is_equal_approx(player.fear_remaining, 2.0), "fear_is_only_from_other_effects")
	player._reset_boss_status()
	var expiring: BossSoulMissile = boss._missiles[1]
	var flash_count: int = boss._flashes.size()
	health_before = player.health
	player.global_position = far_position
	expiring._speed = 0.0
	expiring._physics_process(expiring._remaining + 0.01)
	check(expiring.is_queued_for_deletion() and boss._flashes.size() == flash_count + 1 and player.health == health_before, "unlanded_missile_explodes_after_its_flight_budget")
	boss._cancel_attack()
	boss.attack_state = FinalBoss.AttackState.SOULS
	player.global_position = boss.global_position
	health_before = player.health
	boss.soul_explosion(player.global_position)
	check(is_equal_approx(player.health, health_before - 15.0), "expired_soul_explosion_deals_fifteen")
	boss._cancel_attack()

	player.health_component.max_health = 500.0
	player.health_component.reset()
	player.global_position = far_position
	boss._start_normal_attack()
	var far_missiles: Array[BossSoulMissile] = boss._missiles.duplicate()
	var far_flight_budget: float = 0.0
	for missile: BossSoulMissile in far_missiles:
		missile.set_physics_process(false)
		far_flight_budget = maxf(far_flight_budget, missile._remaining)
	check(far_flight_budget > BossSoulMissile.LIFE_SECONDS, "distant_missiles_keep_fixed_speed_and_gain_time_to_cross_room")
	health_before = player.health
	for frame: int in ceili(far_flight_budget / 0.05) + 1:
		for missile: BossSoulMissile in far_missiles:
			if is_instance_valid(missile) and not missile.is_queued_for_deletion():
				missile._physics_process(0.05)
	check(player.health < health_before, "souls_can_reach_player_at_far_end_of_boss_room")
	boss._cancel_attack()

	boss._start_lasso()
	var distant_rope: BossLasso = boss._lasso
	distant_rope.set_physics_process(false)
	distant_rope._physics_process(boss.global_position.distance_to(far_position) / BossLasso.TRAVEL_SPEED + 0.1)
	check(player.boss_grappled, "lasso_can_catch_player_at_far_end_of_boss_room")
	boss._cancel_attack()

	player.health_component.max_health = 500.0
	player.health_component.reset()
	player.global_position = boss.global_position + Vector2(160.0, 0.0)
	boss._normal_casts = 2
	boss._finish_normal_attack()
	check(boss.attack_state == FinalBoss.AttackState.LASSO and boss._lasso != null, "lasso_unlocks_after_third_normal_attack")
	var rope: BossLasso = boss._lasso
	rope.set_physics_process(false)
	rope._physics_process(0.3)
	check(player.boss_grappled and rope.health.current_health == 300.0, "rope_catches_and_has_three_hundred_health")
	var lunge_attack := WeaponAttack.new()
	lunge_attack.wielder = player
	lunge_attack.definition = WeaponDefinition.new()
	lunge_attack.definition.lunge_tiles = 2.0
	lunge_attack.aim_direction = Vector2.RIGHT
	var position_before_lunge: Vector2 = player.global_position
	lunge_attack._lunge()
	check(player.global_position == position_before_lunge, "weapon_lunge_cannot_move_grappled_player")
	player.weapon_controller.set_aim(Vector2.LEFT)
	var rope_health_before: float = rope.health.current_health
	check(player.weapon_controller.try_attack(), "player_can_start_melee_attack_while_grappled")
	for frame: int in 50:
		await physics_frame
	check(rope.health.current_health < rope_health_before, "actual_melee_attack_hits_lasso_collision_shape")
	var rope_hit := CombatHit.new()
	rope_hit.source = player
	rope_hit.damage = 300.0
	rope_hit.position = rope.hurtbox.global_position
	check(rope.hurtbox.receive_hit(rope_hit), "weapon_hit_can_break_rope")
	check(not player.boss_grappled and boss.attack_state == FinalBoss.AttackState.WAIT, "rope_break_releases_player_without_blast")
	await process_frame
	player.health_component.reset()
	player.collide_with_terrain = false
	player.global_position = boss.global_position + Vector2(112.0, 0.0)
	boss._finish_normal_attack()
	boss._finish_normal_attack()
	check(boss._normal_casts == 2 and boss.attack_state == FinalBoss.AttackState.WAIT, "lasso_remains_unavailable_for_two_new_normal_attacks")
	boss._finish_normal_attack()
	check(boss._normal_casts == 0 and boss.attack_state == FinalBoss.AttackState.LASSO, "lasso_rearms_after_three_more_completed_normal_attacks")
	var pulling_rope: BossLasso = boss._lasso
	pulling_rope.set_physics_process(false)
	pulling_rope._physics_process(0.2)
	check(player.boss_grappled, "second_rope_catches_player")
	health_before = player.health
	pulling_rope._physics_process(1.0)
	check(BossLasso.DAMAGE_INTERVAL == 0.5 and is_equal_approx(player.health, health_before - 1.0) and player.global_position.distance_to(boss.global_position) <= 80.0, "rope_pulls_two_tiles_and_deals_half_damage_twice_per_second")
	pulling_rope._physics_process(1.1)
	check(not player.boss_grappled and boss.attack_state == FinalBoss.AttackState.WAIT and is_equal_approx(player.health, health_before - 52.0), "rope_reaching_three_tiles_causes_six_tile_fifty_damage_blast")
	player.collide_with_terrain = true
	await process_frame

	boss.phase = 2
	boss._refresh_phase_display()
	player.global_position = far_position
	boss._start_normal_attack()
	check(boss.attack_state == FinalBoss.AttackState.SLAM and boss._slam_centers.size() == 5 and boss._attack_remaining == 3.0, "second_phase_telegraphs_five_slams_for_three_seconds")
	var slams_cover_room: bool = false
	var slams_in_room: bool = true
	for center: Vector2 in boss._slam_centers:
		var tile: Vector2i = WorldGenerator.world_to_tile(center) - spec.origin
		slams_in_room = slams_in_room and spec.contains_local(tile.x, tile.y)
		slams_cover_room = slams_cover_room or center.distance_to(player.global_position) > 8.0 * WorldGenerator.TILE_SIZE
	check(boss._slam_centers[0].distance_to(player.global_position) <= WorldGenerator.TILE_SIZE, "slam_targets_player_at_far_end_of_room")
	check(slams_in_room and slams_cover_room, "other_slam_warnings_span_walkable_boss_room")
	boss._tentacle_warning = -1.0
	boss._slam_centers.clear()
	for index: int in 5:
		boss._slam_centers.append(player.global_position)
	health_before = player.health
	boss._resolve_slams()
	check(is_equal_approx(player.health, health_before - 150.0), "overlapping_slams_each_deal_thirty")
	boss._finish_normal_attack()
	check(boss.attack_state == FinalBoss.AttackState.WAIT and boss._normal_wait == FinalBoss.NORMAL_INTERVAL, "normal_cooldown_starts_after_slam_ends")
	boss._tentacle_target = player.global_position
	boss._tentacle_warning = 0.3
	boss._tick_tentacle(0.1)
	boss._tick_tentacle(0.3)
	check(player.boss_captured, "tentacle_catches_without_future_dodge_action")
	boss._tick_tentacle(0.6)
	check(not player.boss_captured and is_equal_approx(player.health, health_before - 170.0) and player.stun_remaining == 2.0, "tentacle_landing_deals_twenty_and_stuns_for_two_seconds")
	var landing_tile: Vector2i = WorldGenerator.world_to_tile(player.global_position)
	check(spec.contains_local(landing_tile.x - spec.origin.x, landing_tile.y - spec.origin.y) and world._generator.is_walkable(landing_tile), "tentacle_lands_on_walkable_tile_inside_boss_room")
	player._physics_process(0.1)
	check(player.input_direction == Vector2.ZERO and player.velocity == Vector2.ZERO, "stun_prevents_all_movement")
	var attack_input := InputEventAction.new()
	attack_input.action = &"attack"
	attack_input.pressed = true
	player._unhandled_input(attack_input)
	check(not player.weapon_controller.is_attacking() and not player.weapon_controller.is_trigger_held(), "stun_blocks_new_weapon_actions")
	position_before_lunge = player.global_position
	lunge_attack._lunge()
	check(player.global_position == position_before_lunge, "weapon_lunge_cannot_move_stunned_player")
	lunge_attack.free()
	player.stun_remaining = 0.0
	player.global_position = boss.global_position
	boss._tentacle_target = player.global_position
	boss._tentacle_warning = 0.3
	health_before = player.health
	player.global_position += Vector2(64.0, 0.0)
	boss._tick_tentacle(0.31)
	check(not player.boss_captured and player.health == health_before, "moving_away_before_tentacle_strike_avoids_grab")
	boss._cancel_attack()
	check(player.try_dodge(Vector2.RIGHT) and player.is_dodging() and player.is_invulnerable(), "remote_dodge_still_works_outside_boss_control")
	player.set_boss_captured(true)
	check(not player.is_dodging() and not player.is_invulnerable() and not player.can_dodge(), "boss_capture_interrupts_dodge_and_invulnerability")
	player.sprite.position.y = -15.0
	player._reset_boss_status()
	check(not player.boss_captured and player.sprite.position.y == 0.0, "room_transition_resets_airborne_sprite_and_status")

	boss.phase = 3
	boss.rage = 500
	boss._refresh_phase_display()
	var rage_bar: BossRageBar = boss.boss_hud.rage_bar
	check(rage_bar.visible and rage_bar.current_rage == 500 and BossRageBar.SEGMENT_COUNT == 10 and BossRageBar.RAGE_PER_SEGMENT == 100, "phase_three_starts_with_five_of_ten_rage_segments")
	check(rage_bar.size.x < boss.boss_hud.health_bar.size.x and rage_bar.get_global_rect().position.y > boss.boss_hud.health_bar.get_global_rect().end.y, "narrower_rage_segments_stay_below_health")
	player.health_component.reset()
	player.global_position = far_position
	boss._start_normal_attack()
	check(boss.attack_state == FinalBoss.AttackState.EYES and boss._attack_remaining == 10.0, "twenty_eye_barrier_lasts_ten_seconds")
	health_before = player.health
	boss._physics_process(0.25)
	check(player.health == health_before, "laser_does_not_hit_before_half_second_interval")
	boss._physics_process(0.25)
	check(is_equal_approx(player.health, health_before - 1.0), "laser_hits_after_half_second_interval")
	boss._physics_process(9.5)
	check(is_equal_approx(player.health, health_before - 20.0) and boss.attack_state == FinalBoss.AttackState.WAIT and boss._normal_wait == FinalBoss.NORMAL_INTERVAL, "all_lasers_share_one_damage_tick_and_finish_before_cooldown")
	boss._physics_process(2.4)
	check(boss.attack_state == FinalBoss.AttackState.WAIT, "eye_barrier_does_not_recast_before_two_and_half_seconds")
	boss._physics_process(0.2)
	check(boss.attack_state == FinalBoss.AttackState.EYES, "eye_barrier_recasts_after_finished_attack_cooldown")
	for index: int in 20:
		hit_boss(boss, 1.0)
	check(boss.rage == 1000 and boss.attack_state == FinalBoss.AttackState.ENRAGED and boss._attack_remaining == 15.0, "twenty_hits_cancel_active_lasers_and_enter_fifteen_second_charge")
	check(rage_bar.current_rage == 1000 and rage_bar.charging and boss.boss_hud.rage_label.text.contains("蓄力"), "full_rage_shows_all_ten_segments_and_charge_countdown")
	var boss_health_before: float = (boss.get_node("Health") as HealthComponent).current_health
	health_before = player.health
	boss._physics_process(15.1)
	check(boss.rage == 500 and boss.attack_state == FinalBoss.AttackState.WAIT and is_equal_approx(player.health, health_before - 80.0), "self_destruct_damages_player_and_resets_rage")
	var room_flash: Dictionary = boss._flashes.back()
	check(room_flash.has("rect") and (room_flash["rect"] as Rect2).has_point(far_position), "self_destruct_flash_covers_far_end_of_boss_room")
	check(rage_bar.current_rage == 500 and not rage_bar.charging and not boss.boss_hud.rage_label.text.contains("蓄力"), "rage_meter_exits_charge_without_stale_countdown")
	check(is_equal_approx((boss.get_node("Health") as HealthComponent).current_health, boss_health_before - 400.0), "self_destruct_damages_boss_by_four_hundred")
	for index: int in 20:
		hit_boss(boss, 1.0)
	check(boss.attack_state == FinalBoss.AttackState.ENRAGED, "rage_can_recur_after_explosion")
	for index: int in 20:
		hit_boss(boss, 1.0)
	check(boss.rage == 500 and boss.attack_state == FinalBoss.AttackState.WAIT, "twenty_more_hits_cancel_charge_at_five_hundred")
	hit_boss(boss, 1.0, false)
	hit_boss(boss, 1.0, false)
	check(boss.rage == 550, "anonymous_direct_damage_counts_each_successful_hit")
	boss._dot_last_rage_ms = -1000000
	var anonymous_tick := CombatHit.new()
	anonymous_tick.weapon_id = &"damage_over_time"
	anonymous_tick.damage = 1.0
	anonymous_tick.position = boss.global_position
	var boss_health := boss.get_node("Health") as HealthComponent
	boss_health.receive_hit(anonymous_tick)
	boss_health.receive_hit(anonymous_tick)
	check(boss.rage == 575 and rage_bar.current_rage == 575 and boss.boss_hud.rage_label.text.contains("575 / 1000"), "rage_updates_within_the_sixth_hundred_point_segment")
	boss._dot_last_rage_ms = -1000000
	var sourced_tick := CombatHit.new()
	sourced_tick.source = player
	sourced_tick.weapon_id = &"damage_over_time"
	sourced_tick.damage = 1.0
	sourced_tick.position = boss.global_position
	boss_health.receive_hit(sourced_tick)
	boss_health.receive_hit(sourced_tick)
	check(boss.rage == 600, "player_sourced_periodic_damage_also_counts_once_per_second")
	var poison_tick := BuffData.new()
	poison_tick.id = &"boss_rage_test_dot"
	poison_tick.tick_interval = 0.5
	poison_tick.damage_per_tick = 1.0
	check(Buffs.apply(boss, poison_tick, 0, player), "periodic_buff_applies_to_boss")
	var holder := Buffs.holder_of(boss)
	boss._dot_last_rage_ms = -1000000
	holder._tick(holder._active[0])
	holder._tick(holder._active[0])
	check(boss.rage == 625, "real_buff_ticks_keep_player_source_and_limit_rage_to_once_per_second")
	Buffs.remove(boss, poison_tick.id)
	boss._dot_last_rage_ms = -1000000
	Buffs.hurt_entity(boss, 1.0, null, &"damage_over_time")
	Buffs.hurt_entity(boss, 1.0, null, &"damage_over_time")
	check(boss.rage == 650, "tagged_alchemy_fire_pulses_count_at_most_once_per_second")

	player.active_map = world._generator.map_spec(0)
	player.global_position = world._generator.start_world_position()
	player.health_component.reset()
	health_before = player.health
	boss.attack_state = FinalBoss.AttackState.EYES
	boss._attack_remaining = FinalBoss.EYE_SECONDS
	boss._laser_tick = FinalBoss.LASER_TICK_SECONDS
	boss._physics_process(1.0)
	check(player.health == health_before and boss._attack_remaining == FinalBoss.EYE_SECONDS, "eye_attack_does_not_reach_adjacent_room")
	boss._complete_self_destruct()
	check(player.health == health_before, "room_wide_explosion_does_not_hit_other_room")
	boss._start_normal_attack()
	check(boss.attack_state == FinalBoss.AttackState.WAIT, "boss_does_not_cast_at_player_in_other_room")

	world.queue_free()
	await process_frame
	await process_frame
	print("FINAL_BOSS_ATTACKS: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
