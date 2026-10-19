extends SceneTree

const SAMPLE_FRAMES: int = 180


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


func _sample(label: String) -> void:
	var worst_ms: float = 0.0
	var slow_frames: int = 0
	var total_ms: float = 0.0
	var last_usec: int = Time.get_ticks_usec()
	for frame: int in SAMPLE_FRAMES:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var elapsed_ms: float = float(now - last_usec) / 1000.0
		last_usec = now
		total_ms += elapsed_ms
		worst_ms = maxf(worst_ms, elapsed_ms)
		if elapsed_ms > 33.3:
			slow_frames += 1
	var stats: Dictionary = (current_scene as Node2D).chunk_manager.get_stats()
	print("BOSS_VIS_SAMPLE: label=%s avg_ms=%.2f worst_ms=%.2f slow_frames=%d fps=%d process_ms=%.2f physics_ms=%.2f objects=%d chunks_applied=%d queued=%d in_flight=%d apply_avg_ms=%.2f" % [label, total_ms / SAMPLE_FRAMES, worst_ms, slow_frames, Engine.get_frames_per_second(), 1000.0 * Performance.get_monitor(Performance.TIME_PROCESS), 1000.0 * Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS), int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(stats["applied"]), int(stats["queued"]), int(stats["in_flight"]), float(stats["apply_avg_ms"])])


func _red_warning_pixels(image: Image, clear_image: Image) -> int:
	var changed: int = 0
	for y: int in range(0, image.get_height(), 8):
		for x: int in range(0, image.get_width(), 8):
			var active: Color = image.get_pixel(x, y)
			var clear: Color = clear_image.get_pixel(x, y)
			if active.r - clear.r > 0.12 and active.r > active.g + 0.1:
				changed += 1
	return changed


func _filled_rage_sections(image: Image, bar: BossRageBar) -> int:
	var rect: Rect2 = bar.get_global_rect()
	var step: float = (rect.size.x - 2.0 - 3.0 * 9.0) / 10.0 + 3.0
	var filled: int = 0
	for index: int in 10:
		var x: int = roundi(rect.position.x + 1.0 + float(index) * step + (step - 3.0) * 0.5)
		var y: int = roundi(rect.position.y + rect.size.y * 0.5)
		var color: Color = image.get_pixel(x, y)
		if color.r > color.b + 0.18 and color.g > color.b + 0.12:
			filled += 1
	return filled


func _hud_layout_clear(world: Node2D, boss: FinalBoss) -> bool:
	var game_hud := world.get_node("GameHUD/HUD") as Control
	var info := game_hud.get_node("InfoLabel") as Control
	var minimap := game_hud.get_node("Minimap") as Control
	var toast := game_hud.get_node("ToastLabel") as Control
	var health_rect: Rect2 = boss.boss_hud.health_bar.get_global_rect()
	var title_rect: Rect2 = boss.boss_hud.name_label.get_global_rect()
	var rage_rect: Rect2 = boss.boss_hud.rage_bar.get_global_rect()
	return not health_rect.intersects(info.get_global_rect()) and not health_rect.intersects(minimap.get_global_rect()) and not title_rect.intersects(info.get_global_rect()) and not title_rect.intersects(minimap.get_global_rect()) and not rage_rect.intersects(info.get_global_rect()) and not toast.get_global_rect().intersects(info.get_global_rect()) and not toast.get_global_rect().intersects(minimap.get_global_rect())


func _run() -> void:
	Engine.max_fps = 60
	Engine.time_scale = 1.0
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 1)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.player.set_physics_process(false)
	var spec: MapSpec = world._generator.map_spec(world._generator.run.final_node())
	world._enter_map(spec.node_id, -1, spec.west_gate_y)
	var spawner := world.monster_spawner as MonsterSpawner
	var bosses: Array[FinalBoss] = bosses_in(spawner)
	if bosses.size() != 1:
		push_error("Expected exactly one fixed Boss in visibility test")
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
	print("BOSS_VIS_ROOM: extent=%s entry_distance=%.1f" % [spec.extent, world.player.global_position.distance_to(boss.global_position)])
	var entry_health_rect: Rect2 = boss.boss_hud.health_bar.get_global_rect()
	await _sample("entry")
	world.player.global_position = boss.global_position + Vector2(70.0, 0.0)
	await _sample("arena")
	var arena_health_rect: Rect2 = boss.boss_hud.health_bar.get_global_rect()
	var hud_fixed: bool = entry_health_rect.is_equal_approx(arena_health_rect) and arena_health_rect.position.y < 80.0 and arena_health_rect.size.x >= 500.0
	print("BOSS_VIS_HUD: screen_fixed=%s health_rect=%s" % [hud_fixed, arena_health_rect])
	if not hud_fixed:
		push_error("Boss health HUD moved with the camera or is not at the top")
		quit(1)
		return
	var hit := CombatHit.new()
	hit.source = world.player
	hit.damage = 3100.0
	hit.position = boss.global_position
	(boss.get_node("Hurtbox") as CombatHurtbox).receive_hit(hit)
	await create_timer(4.1, false).timeout
	boss._start_normal_attack()
	boss._attack_remaining = 1.5
	boss.queue_redraw()
	await RenderingServer.frame_post_draw
	var visible_count: int = 0
	for center: Vector2 in boss._slam_centers:
		if absf(center.x - world.player.global_position.x) <= 330.0 and absf(center.y - world.player.global_position.y) <= 190.0:
			visible_count += 1
	print("BOSS_VIS_SLAM: visible=%d total=%d state=%d" % [visible_count, boss._slam_centers.size(), boss.attack_state])
	var image := root.get_texture().get_image()
	if image != null and not image.is_empty():
		var save_error: Error = image.save_png("res://.godot/boss_visual_slam.png")
		print("BOSS_VIS_SCREENSHOT: result=%d size=%s" % [save_error, image.get_size()])
		boss.attack_state = FinalBoss.AttackState.WAIT
		boss.queue_redraw()
		await RenderingServer.frame_post_draw
		var clear_image := root.get_texture().get_image()
		print("BOSS_VIS_PIXELS: red_warning_samples=%d" % _red_warning_pixels(image, clear_image))
		boss.attack_state = FinalBoss.AttackState.SLAM
		boss.queue_redraw()
	else:
		print("BOSS_VIS_SCREENSHOT: unavailable")
	await _sample("slam")
	boss._cancel_attack()
	boss.phase = 3
	boss.rage = 500
	boss._refresh_phase_display()
	var rage_rect: Rect2 = boss.boss_hud.rage_bar.get_global_rect()
	var health_rect: Rect2 = boss.boss_hud.health_bar.get_global_rect()
	var rage_fits: bool = boss.boss_hud.rage_bar.visible and rage_rect.size.x < health_rect.size.x and rage_rect.position.y > health_rect.end.y and boss.boss_hud.rage_bar.current_rage == 500
	print("BOSS_VIS_RAGE: fits=%s rage_rect=%s health_rect=%s segments=%d" % [rage_fits, rage_rect, health_rect, BossRageBar.SEGMENT_COUNT])
	if not rage_fits:
		push_error("Segmented rage meter is missing or does not fit below health")
		quit(1)
		return
	boss._start_normal_attack()
	boss.set_physics_process(true)
	await _sample("eyes_live")
	boss.set_physics_process(false)
	await RenderingServer.frame_post_draw
	var eyes_image := root.get_texture().get_image()
	if eyes_image != null and not eyes_image.is_empty():
		var eye_save_error: Error = eyes_image.save_png("res://.godot/boss_visual_eyes.png")
		var lit_sections: int = _filled_rage_sections(eyes_image, boss.boss_hud.rage_bar)
		boss.attack_state = FinalBoss.AttackState.WAIT
		boss.queue_redraw()
		await RenderingServer.frame_post_draw
		var eyes_clear_image := root.get_texture().get_image()
		print("BOSS_VIS_EYES: result=%d red_beam_samples=%d rage_lit_sections=%d player_health=%.1f" % [eye_save_error, _red_warning_pixels(eyes_image, eyes_clear_image), lit_sections, world.player.health])
		if lit_sections != 5:
			push_error("500 rage should light exactly five rendered segments")
			quit(1)
			return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(390, 640)]:
		root.size = viewport_size
		await process_frame
		await RenderingServer.frame_post_draw
		var clear: bool = is_equal_approx(boss.boss_hud.size.x, float(viewport_size.x)) and _hud_layout_clear(world, boss)
		print("BOSS_VIS_HUD_LAYOUT: requested=%s root=%s hud=%s clear=%s health=%s rage=%s" % [viewport_size, root.size, boss.boss_hud.size, clear, boss.boss_hud.health_bar.get_global_rect(), boss.boss_hud.rage_bar.get_global_rect()])
		if not clear:
			push_error("Boss HUD overlaps gameplay HUD at viewport %s" % viewport_size)
			quit(1)
			return
		if viewport_size.x == 390:
			var mobile_image := root.get_texture().get_image()
			print("BOSS_VIS_MOBILE: result=%d" % mobile_image.save_png("res://.godot/boss_visual_hud_mobile.png"))
			var stats := world.hud.get_node("StatsLabel") as Label
			var old_preference: bool = bool(world.hud.get("_stats_visible_before_boss"))
			var toggle := InputEventAction.new()
			toggle.action = &"toggle_debug"
			toggle.pressed = true
			world.hud._unhandled_input(toggle)
			var new_preference: bool = bool(world.hud.get("_stats_visible_before_boss"))
			if stats.visible or old_preference == new_preference:
				push_error("F3 should preserve its state without overlapping the mobile Boss HUD")
				quit(1)
				return
	world.queue_free()
	await process_frame
	quit()
