extends SceneTree
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _run() -> void:
	Engine.max_fps = 240
	root.size = Vector2i(1280,720)
	root.get_node("GameState").set("world_seed",1741004498)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	for spec: MapSpec in world._generator.map_specs():
		if spec.biome_id not in [Biome.Kind.SWAMP,Biome.Kind.TROPICAL_RAINFOREST]:
			continue
		if world.monster_spawner.content.budget_of(spec.node_id,MapContent.ENEMY) <= 0:
			world._enter_map(spec.node_id)
			await ready_map(world)
			check(world.monster_spawner.monsters.is_empty(), "safe_habitat_room_has_no_gate_encounters")
			continue
		var gates: Array[Vector2i] = [Vector2i(-1,spec.west_gate_y)]
		for y: int in spec.east_gates:
			gates.append(Vector2i(1,y))
		for gate: Vector2i in gates:
			world._enter_map(spec.node_id,gate.x,gate.y)
			await ready_map(world)
			var center: Vector2 = world.camera.get_screen_center_position()
			var half: Vector2 = root.get_visible_rect().size / world.camera.zoom * 0.5
			var view := Rect2(center-half,half*2)
			var nearby: Array[BaseMonster] = []
			for actor: BaseMonster in world.monster_spawner.monsters:
				if not view.has_point(actor.global_position):
					continue
				if (spec.biome_id == Biome.Kind.SWAMP and actor is ShiMonster) or (spec.biome_id == Biome.Kind.TROPICAL_RAINFOREST and actor is GiveMonster):
					nearby.append(actor)
			var required: int = 3 if spec.biome_id == Biome.Kind.SWAMP else 2
			check(nearby.size() >= required, "user_seed_all_combat_entrances_have_visible_encounter")
			for actor: BaseMonster in nearby:
				check(actor.is_visible_in_tree(), "encounter_is_not_hidden_or_count_only")
				check(actor.global_position.distance_to(world.player.global_position) > 4.0*16.0, "encounter_does_not_spawn_on_player")
			var original: Dictionary = {}
			for actor: BaseMonster in world.monster_spawner.monsters:
				original[actor.get_script().resource_path+":"+str(WorldGenerator.world_to_tile(actor.global_position))] = true
			check(not nearby.is_empty(), "encounter_has_real_actor_to_kill")
			if nearby.is_empty():
				continue
			var victim: BaseMonster = nearby[0]
			var key: String = victim.get_script().resource_path+":"+str(WorldGenerator.world_to_tile(victim.global_position))
			victim.kill()
			world._enter_map(0)
			world._enter_map(spec.node_id,gate.x,gate.y)
			await ready_map(world)
			check(world.monster_spawner.monsters.size() == original.size()-1, "gate_death_does_not_generate_replacement")
			for actor: BaseMonster in world.monster_spawner.monsters:
				var restored: String = actor.get_script().resource_path+":"+str(WorldGenerator.world_to_tile(actor.global_position))
				check(original.has(restored) and restored != key, "return_restores_only_original_surviving_identities")
			print("USER_GATE node=%d side=%d y=%d biome=%d visible=%d" % [spec.node_id,gate.x,gate.y,spec.biome_id,nearby.size()])
			# 本检查的下一个入口从全新局验证，避免刚刚击杀的同一组影响邻近入口。
			world.build_world(1741004498)
	world.queue_free()
	await process_frame
	await process_frame
	print("GATE_ENCOUNTERS: checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
func ready_map(world: Node2D) -> void:
	for frame: int in 240:
		if world.chunk_manager.map_ready():
			break
		await process_frame
	check(world.chunk_manager.map_ready(), "map_loading_completed")
