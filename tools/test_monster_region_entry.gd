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


func _cross_gate(world: Node2D, link: Dictionary) -> void:
	world.player.global_position = WorldGenerator.tile_to_world(link["point"])
	world.player.velocity = Vector2(float(link["side"]) * world.player.max_speed, 0)
	world._process(0.01)


func _wait_map(world: Node2D) -> void:
	for frame: int in 240:
		if world.chunk_manager.map_ready():
			break
		await process_frame
	_check(world.chunk_manager.map_ready(), "active_region_finishes_loading")


func _run() -> void:
	Engine.max_fps = 120
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 18473)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	_check(world.monster_spawner.monsters.is_empty(), "initial_cottage_remains_safe")
	var link: Dictionary = _rainforest_gate(world)
	_check(not link.is_empty(), "combat_fixture_has_second_layer_rainforest_gate")
	if link.is_empty():
		world.queue_free()
		await process_frame
		quit(1)
		return
	var target_id: int = link["target"]
	_cross_gate(world, link)
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
	var victim: BaseMonster = world.monster_spawner.monsters[0]
	var killed_tile: Vector2i = WorldGenerator.world_to_tile(victim.global_position)
	victim.kill()
	var loot: GroundPickup = null
	for child: Node in world.monster_spawner.get_children():
		if child is GroundPickup:
			loot = child
	_check(loot != null and loot.data.id in [4, 5], "actual_combat_death_keeps_exclusive_loot")
	for back: Dictionary in world._generator.gate_links(target_id):
		if back["target"] == 0:
			_cross_gate(world, back)
			break
	_check(world._current_node == 0, "return_gate_reaches_initial_safe_region")
	_cross_gate(world, link)
	await _wait_map(world)
	_check(world.monster_spawner.monsters.size() == count_before - 1, "actual_gate_return_preserves_empty_dead_slot_without_replacement")
	for actor: BaseMonster in world.monster_spawner.monsters:
		_check(WorldGenerator.world_to_tile(actor.global_position) != killed_tile, "actual_gate_return_does_not_revive_victim")
	_check(is_instance_valid(loot) and loot.is_visible_in_tree(), "actual_gate_return_restores_same_uncollected_drop")

	# 同样是第二层雨林，也可能是非战斗房间；显示房型并保留内容预算规则。
	world.build_world(777)
	var noncombat: Dictionary = _rainforest_gate(world)
	_check(not noncombat.is_empty(), "noncombat_fixture_has_second_layer_rainforest_gate")
	if not noncombat.is_empty():
		_cross_gate(world, noncombat)
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
