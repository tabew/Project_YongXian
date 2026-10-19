extends SceneTree
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _run() -> void:
	Engine.max_fps = 240
	root.size = Vector2i(1280,720)
	root.get_node("GameState").set("world_seed",309598543)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	for seed_value: int in [309598543,1741004498,18473,42,777]:
		world.build_world(seed_value)
		var first_main_combat: int = 999
		var snow_main: MapSpec = null
		var swamp_combat: int = 0
		var rainforest_combat: int = 0
		for spec: MapSpec in world._generator.map_specs():
			var kind: int = world._generator.run.type_of(spec.node_id)
			var budget: int = world.monster_spawner.content.budget_of(spec.node_id,MapContent.ENEMY)
			check((budget == 0) if RunGraph.floor_of(spec.node_id) == 0 or kind == RoomType.Kind.EVENT else (budget > 0),"first_floor_and_event_rooms_are_monster_free")
			if kind in [RoomType.Kind.COMBAT,RoomType.Kind.BOSS]:
				swamp_combat += int(spec.biome_id == Biome.Kind.SWAMP)
				rainforest_combat += int(spec.biome_id == Biome.Kind.TROPICAL_RAINFOREST)
			if kind != RoomType.Kind.COMBAT:
				continue
			var floor_number: int = RunGraph.floor_of(spec.node_id) + 1
			if world._generator.run.is_main_path(spec.node_id):
				first_main_combat = mini(first_main_combat,floor_number)
				if spec.biome_id in [Biome.Kind.TUNDRA,Biome.Kind.SNOWY_PLAINS] and (snow_main == null or RunGraph.floor_of(spec.node_id) < RunGraph.floor_of(snow_main.node_id)):
					snow_main = spec
		print("RABBIT_SEED seed=%d first_main=%d snow_main=%s swamp=%d rainforest=%d" % [seed_value,first_main_combat,str(snow_main.node_id) if snow_main != null else "none",swamp_combat,rainforest_combat])
		check(world._generator.run.validate().is_empty(),"all_mandatory_shop_rest_reward_rooms_survive")
		check(first_main_combat <= 6,"main_route_combat_is_before_final_two_floors")
		check(snow_main != null and RunGraph.floor_of(snow_main.node_id) + 1 <= 6,"rabbit_combat_on_main_route_before_final_two_floors")
		check(swamp_combat > 0 and rainforest_combat > 0,"swamp_and_rainforest_combat_preserved")
		if seed_value != 309598543 or snow_main == null:
			continue
		check(world._generator.run.type_of(2) == RoomType.Kind.SHOP,"reported_seed_initial_shop_unchanged")
		check(snow_main.node_id == 8 and RunGraph.floor_of(snow_main.node_id) + 1 == 5,"reported_seed_rabbit_battle_is_main_floor_five")
		world._enter_map(snow_main.node_id,-1,snow_main.west_gate_y)
		for frame: int in 240:
			if world.chunk_manager.map_ready():
				break
			await process_frame
		check(world.chunk_manager.map_ready(),"reported_seed_main_rabbit_room_loads")
		var guards: int = 0
		var ordinary: int = 0
		for actor: BaseMonster in world.monster_spawner.monsters:
			if not actor is ShabeiMonster:
				continue
			if actor.has_supply_post:
				guards += 1
				check(actor.is_visible_in_tree(), "reported_seed_rabbit_guards_supply_site")
			else:
				ordinary += 1
		check(guards > 0 and ordinary > 0, "reported_seed_rabbit_room_keeps_scattered_rabbits_and_adds_guards")
		print("RABBIT_ROUTE seed=%d main_floor=%d node=%d guards=%d ordinary=%d" % [seed_value,first_main_combat,snow_main.node_id,guards,ordinary])
	world.queue_free()
	await process_frame
	await process_frame
	print("RABBIT_ROUTE: checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
