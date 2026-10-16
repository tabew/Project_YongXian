extends SceneTree

## 从初图实际出口进入第二层雨林；覆盖房型显示、当前图刷怪与返图死亡记录。
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)


func _rainforest_gate(world: Node2D) -> Dictionary:
	for link: Dictionary in world._generator.gate_links(0):
		if world._generator.map_spec(link["target"]).biome_id == Biome.Kind.TROPICAL_RAINFOREST:
			return link
	return {}


func _resolve_upgrade_pause(world: Node2D) -> void:
	if not world.get_tree().paused:
		return
	var panel := world.get_node("GameHUD/UpgradePanel") as UpgradePanel
	if panel.visible and not panel._cards.is_empty():
		panel.card_chosen.emit(panel._cards[0].id)


func _cross_gate(world: Node2D, link: Dictionary) -> void:
	world.player.global_position = WorldGenerator.tile_to_world(link["point"])
	world.player.velocity = Vector2(float(link["side"]) * world.player.max_speed, 0)
	world._process(0.01)
	_check(world._transitioning, "entering_gate_starts_black_fade")
	for frame: int in 480:
		_resolve_upgrade_pause(world)
		if not world._transitioning:
			return
		await process_frame
	_check(false, "gate_fade_did_not_finish")


func _wait_map(world: Node2D) -> void:
	for frame: int in 1200:
		_resolve_upgrade_pause(world)
		if world.chunk_manager.map_ready() and world.monster_spawner.get_pending_spawn_count() == 0:
			return
		await process_frame
	_check(false, "active_region_ready=%s pending=%d mode=%d processing=%s can_process=%s tree_paused=%s transitioning=%s player_health=%.1f" % [world.chunk_manager.map_ready(), world.monster_spawner.get_pending_spawn_count(), world.monster_spawner.process_mode, world.monster_spawner.is_processing(), world.monster_spawner.can_process(), world.get_tree().paused, world._transitioning, world.player.health])


func _run() -> void:
	Engine.max_fps = 120
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 18473)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.player.damage_taken = 0.0
	_check(world.monster_spawner.monsters.is_empty(), "initial_cottage_remains_safe")
	var link: Dictionary = _rainforest_gate(world)
	_check(not link.is_empty(), "combat_fixture_has_second_layer_rainforest_gate")
	if link.is_empty():
		world.queue_free()
		await process_frame
		quit(1)
		return
	var target_id: int = link["target"]
	await _cross_gate(world, link)
	_check(world._current_node == target_id, "normal_gameplay_gate_enters_actual_rainforest_branch")
	await _wait_map(world)
	var count_before: int = world.monster_spawner.monsters.size()
	_check(count_before > 0, "rainforest_combat_region_generates_give")
	_check(world.monster_spawner._active_map == world.player.active_map, "spawner_tracks_actual_active_region")
	for actor: BaseMonster in world.monster_spawner.monsters:
		var tile: Vector2i = WorldGenerator.world_to_tile(actor.global_position)
		var local: Vector2i = tile - world.player.active_map.origin
		_check(world.player.active_map.contains_local(local.x, local.y), "neighbor_never_consumes_current_region_spawn_slots")
	world.hud._refresh()
	_check(world.hud.info_label.text.contains("战斗"), "hud_identifies_rainforest_combat_room")
	_check(world.hud.stats_label.text.contains("本区域怪物 %d" % count_before), "f3_stats_report_current_actor_count")
	if count_before <= 0:
		world.queue_free()
		await process_frame
		quit(1)
		return
	var victim: BaseMonster = null
	for actor: BaseMonster in world.monster_spawner.monsters:
		if actor is GiveMonster:
			victim = actor
			break
	_check(victim != null, "rainforest_combat_has_give_for_exclusive_loot_check")
	if victim == null:
		world.queue_free()
		await process_frame
		quit(1)
		return
	var killed_tile: Vector2i = victim.original_spawn_tile
	victim.kill()
	var loot: GroundPickup = null
	for child: Node in world.monster_spawner.get_children():
		if child is GroundPickup:
			loot = child
	_check(loot != null and loot.data in victim.death_loot.items, "actual_combat_death_keeps_exclusive_loot")
	for back: Dictionary in world._generator.gate_links(target_id):
		if back["target"] == 0:
			await _cross_gate(world, back)
			break
	_check(world._current_node == 0, "return_gate_reaches_initial_safe_region")
	await _cross_gate(world, link)
	await _wait_map(world)
	var returned_guards: int = 0
	var returned_ordinary: int = 0
	for actor: BaseMonster in world.monster_spawner.monsters:
		if actor.has_supply_post:
			returned_guards += 1
		else:
			returned_ordinary += 1
		_check(actor.original_spawn_tile != killed_tile, "actual_gate_return_does_not_revive_victim")
	_check(returned_guards > 0 and returned_ordinary > 0, "actual_gate_return_keeps_both_supply_guards_and_ordinary_monsters")
	_check(is_instance_valid(loot) and loot.is_visible_in_tree(), "actual_gate_return_restores_same_uncollected_drop")

	# 同样是第二层雨林，也可能是非战斗房间；显示房型并保留内容预算规则。
	world.build_world(777)
	var noncombat: Dictionary = _rainforest_gate(world)
	_check(not noncombat.is_empty(), "noncombat_fixture_has_second_layer_rainforest_gate")
	if not noncombat.is_empty():
		await _cross_gate(world, noncombat)
		await _wait_map(world)
		var spec: MapSpec = world.player.active_map
		var room_kind: int = world._generator.run.type_of(spec.node_id)
		_check(world.monster_spawner.content.budget_of(spec.node_id, MapContent.ENEMY) == 0, "noncombat_rainforest_has_zero_enemy_budget")
		_check(world.monster_spawner.monsters.is_empty(), "noncombat_rainforest_does_not_spawn_combat_enemies")
		world.hud._refresh()
		_check(world.hud.info_label.text.contains(RoomType.name_of(room_kind)), "hud_discloses_noncombat_room_type")
	print("MONSTER_REGION_ENTRY: checks=%d failures=%d" % [_checks, _failures])
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if _failures == 0 else 1)
