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
		if world.chunk_manager.map_ready() and world.monster_spawner.get_pending_spawn_count() == 0:
			return
		await process_frame
	check(false, "boss_room_loaded")


func hit_boss(boss: FinalBoss, amount: float, from_player: bool = true) -> void:
	var hit := CombatHit.new()
	hit.source = boss.player if from_player else null
	hit.damage = amount
	hit.position = boss.global_position
	(boss.get_node("Health") as HealthComponent).receive_hit(hit)


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
	var boss := world.monster_spawner.monsters[0] as FinalBoss
	boss.set_physics_process(false)
	boss.brain = null
	await wait_room(world)
	check(boss.phase == 1 and boss.attack_state == FinalBoss.AttackState.WAIT, "boss_starts_in_first_attack_state")

	boss._start_normal_attack()
	check(boss.attack_state == FinalBoss.AttackState.SOULS and boss._missiles.size() >= 7 and boss._missiles.size() <= 8, "first_phase_creates_seven_or_eight_missiles")
	for missile: BossSoulMissile in boss._missiles:
		missile.set_physics_process(false)
	var first: BossSoulMissile = boss._missiles[0]
	var health_before: float = player.health
	player.global_position = first.global_position
	first._physics_process(0.01)
	check(is_equal_approx(player.health, health_before - 10.0) and is_equal_approx(player.fear_remaining, 2.0), "direct_missile_hit_deals_ten_and_adds_two_fear")
	player.apply_fear(2.0)
	check(is_equal_approx(player.fear_remaining, 4.0), "repeated_fear_adds_duration")
	Input.action_press("move_up")
	player._physics_process(0.01)
	check(player.input_direction.y > 0.0, "fear_reverses_up_to_down")
	Input.action_press("move_right")
	player._physics_process(0.01)
	check(player.input_direction.x < 0.0 and player.input_direction.y > 0.0, "fear_reverses_both_axes_of_diagonal_movement")
	Input.action_release("move_up")
	Input.action_release("move_right")
	var expiring: BossSoulMissile = boss._missiles[1]
	var flash_count: int = boss._flashes.size()
	health_before = player.health
	player.global_position = expiring.global_position + Vector2(0.0, 1000.0)
	expiring._physics_process(4.01)
	check(expiring.is_queued_for_deletion() and boss._flashes.size() == flash_count + 1 and player.health == health_before, "unlanded_missile_explodes_after_four_seconds")
	boss._cancel_attack()
	boss.attack_state = FinalBoss.AttackState.SOULS
	health_before = player.health
	boss.soul_explosion(player.global_position)
	check(is_equal_approx(player.health, health_before - 15.0), "expired_soul_explosion_deals_fifteen")
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
	check(is_equal_approx(player.health, health_before - 0.5) and player.global_position.distance_to(boss.global_position) <= 80.0, "rope_pulls_two_tiles_and_takes_half_health_per_second")
	pulling_rope._physics_process(1.1)
	check(not player.boss_grappled and boss.attack_state == FinalBoss.AttackState.WAIT and is_equal_approx(player.health, health_before - 51.0), "rope_reaching_three_tiles_causes_six_tile_fifty_damage_blast")
	player.collide_with_terrain = true
	await process_frame

	boss.phase = 2
	boss._refresh_phase_display()
	boss._start_normal_attack()
	check(boss.attack_state == FinalBoss.AttackState.SLAM and boss._slam_centers.size() == 5 and boss._attack_remaining == 3.0, "second_phase_telegraphs_five_slams_for_three_seconds")
	var slams_near_player: bool = true
	for center: Vector2 in boss._slam_centers:
		if absf(center.x - player.global_position.x) > 128.0 or absf(center.y - player.global_position.y) > 128.0:
			slams_near_player = false
	check(slams_near_player, "five_slam_warnings_stay_within_visible_range_of_cast_position")
	boss._tentacle_warning = -1.0
	boss._slam_centers.clear()
	for index: int in 5:
		boss._slam_centers.append(player.global_position)
	health_before = player.health
	boss._resolve_slams()
	check(is_equal_approx(player.health, health_before - 150.0), "overlapping_slams_each_deal_thirty")
	boss._finish_normal_attack()
	check(boss.attack_state == FinalBoss.AttackState.WAIT and boss._normal_wait == 5.0, "normal_cooldown_starts_after_slam_ends")
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
	boss._start_normal_attack()
	check(boss.attack_state == FinalBoss.AttackState.EYES and boss._attack_remaining == 10.0, "twenty_eye_barrier_lasts_ten_seconds")
	health_before = player.health
	boss._physics_process(10.0)
	check(is_equal_approx(player.health, health_before - 10.0) and boss.attack_state == FinalBoss.AttackState.WAIT and boss._normal_wait == 5.0, "all_lasers_share_one_damage_tick_and_finish_before_cooldown")
	boss._physics_process(4.9)
	check(boss.attack_state == FinalBoss.AttackState.WAIT, "eye_barrier_does_not_recast_before_five_seconds")
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

	world.queue_free()
	await process_frame
	await process_frame
	print("FINAL_BOSS_ATTACKS: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
