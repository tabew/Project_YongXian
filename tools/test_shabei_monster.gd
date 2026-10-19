extends SceneTree
class FlatGenerator extends WorldGenerator:
	func is_walkable(_tile: Vector2i) -> bool:
		return true
	func sample_terrain(_tile: Vector2i) -> int:
		return Terrain.Kind.SNOW
	func sample_route(_tile: Vector2i) -> int:
		return Route.Kind.NONE
	func sample_biome(_tile: Vector2i) -> int:
		return Biome.Kind.SNOWY_PLAINS
	func sample_map(_tile: Vector2i) -> MapSpec:
		return null
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func fixture() -> Dictionary:
	var holder := Node2D.new()
	root.add_child(holder)
	var player := (load("res://scenes/game/player.tscn") as PackedScene).instantiate() as PlayerCharacter
	player.inventory = Inventory.new()
	holder.add_child(player)
	player.set_physics_process(false)
	var actor := (load("res://scenes/monsters/shabei_monster.tscn") as PackedScene).instantiate() as ShabeiMonster
	holder.add_child(actor)
	actor.configure(player,FlatGenerator.new(18473),Vector2i.ZERO)
	actor.set_physics_process(false)
	player.global_position = actor.global_position + Vector2(100,0)
	return {"holder":holder,"player":player,"actor":actor}
func clear_fixture(holder: Node) -> void:
	holder.queue_free()
	await process_frame
func _run() -> void:
	Engine.max_fps = 240
	root.size = Vector2i(1280,720)
	var items: Node = root.get_node("ItemListGlobal")
	for id: int in [11,12,13]:
		var data: IngredientData = items.create(id)
		check(data != null and data.texture != null,"loot_registered_with_icon")
		var model: ItemModel = data.create_model()
		check(model != null and model.data.id == id,"loot_models_exist")
		model.free()
	check(items.create(12).name == "糯糯肉团","rabbit_meat_new_display_name")
	check(items.create(13).name == "操操操。！","carrot_exact_requested_name")
	check(items.templates.back().id == 300,"potion_remains_last")
	var rabbit_data := load("res://resources/monsters/shabei_spawn_data.tres") as MonsterSpawnData
	check(rabbit_data.allowed_biomes == [Biome.Kind.TAIGA, Biome.Kind.TUNDRA, Biome.Kind.SNOWY_PLAINS],"rabbit_adds_taiga_and_preserves_snow_habitats")
	var loot: MonsterLootTable = load("res://resources/monsters/shabei_loot_table.tres")
	var counts: Dictionary = {11:0,12:0,13:0}
	for index: int in 1000:
		counts[loot.choose_for_roll((index+0.5)/1000.0).id] += 1
	check(counts == {11:300,12:500,13:200},"exact_30_50_20_intervals")
	var f: Dictionary = fixture()
	var actor: ShabeiMonster = f.actor
	check((actor.get_node("NameLabel") as Label).text == "糯糯","rabbit_uses_new_display_name")
	check(actor.get_node("Health").max_health == 80.0,"rabbit_hp_80")
	check(actor.ai_config.vision_distance_tiles == EnemyAIConfig.new().vision_distance_tiles,"template_aggro_range")
	f.player.global_position = actor.global_position + Vector2(1000,0)
	actor.play_monster_animation(&"Move")
	actor._physics_process(0.22)
	check(actor._hop_count == 1 and actor._hop_rest == 0.0,"first_low_hop_no_rest")
	actor.play_monster_animation(&"Move")
	actor._physics_process(0.22)
	check(actor._hop_rest == 1.0 and actor.movement_speed() == 0.0,"two_hops_then_one_second_rest")
	actor._physics_process(1.0)
	check(actor.movement_speed() > 0.0,"rest_finishes")
	f.player.global_position = actor.global_position + Vector2(100,0)
	var impl: ShabeiScreamAttack = actor.attack
	var origin: Vector2 = actor.global_position
	check(impl.perform_attack(actor,f.player),"scream_starts")
	check(actor.monster_animation_state() == &"Scream" and actor.screaming,"scream_uses_animationtree")
	for step: int in 239:
		impl.update(actor,1.0/60.0)
		check(actor.global_position == origin and actor.movement_speed() == 0.0,"full_scream_is_stationary")
		for wave: ShabeiSoundWave in impl.emitted_layers:
			if is_instance_valid(wave):
				wave.set_physics_process(false)
				wave._physics_process(1.0/60.0)
	check(impl._emitted == 5,"exactly_five_layers_over_four_seconds")
	check(not actor.fleeing,"not_fleeing_before_four_seconds")
	impl.update(actor,1.0/60.0)
	check(actor.fleeing and not actor.screaming and impl.is_busy(),"scream_finishes_into_exclusive_flee")
	var escape_before: float = actor.global_position.distance_to(f.player.global_position)
	for step: int in 90:
		actor._physics_process(1.0/60.0)
		await physics_frame
	check(actor.global_position.distance_to(f.player.global_position) > escape_before + 10.0,"actual_flee_navigation_moves_away_from_player")
	for step: int in 120:
		for wave: ShabeiSoundWave in impl.emitted_layers:
			if is_instance_valid(wave):
				wave._physics_process(1.0/60.0)
	check(f.player.health == 50.0,"five_independent_layers_each_deal_one_damage_once")
	actor.global_position = f.player.global_position + Vector2(241,0)
	impl.update(actor,0.01)
	check(not impl.is_busy() and not actor.fleeing and actor.get_ai_state() == EnemyState.State.PATROL,"outside_attack_range_returns_to_patrol")
	check(actor.blackboard.patrol_anchor == actor.global_position,"flee_end_patrol_at_new_location")
	await clear_fixture(f.holder)
	f = fixture()
	actor = f.actor
	impl = actor.attack
	check(impl.perform_attack(actor,f.player),"second_fixture_scream_starts")
	var early: ShabeiSoundWave = impl.emitted_layers[0]
	early.set_physics_process(false)
	early._physics_process(0.5)
	impl.update(actor,0.8)
	var late: ShabeiSoundWave = impl.emitted_layers[1]
	late.set_physics_process(false)
	check(early.radius == 60.0 and late.radius == 0.0,"each_layer_has_own_propagation_radius")
	f.player.global_position = actor.global_position + Vector2(-100,0)
	late._physics_process(1.0)
	check(f.player.health == 100.0,"outside_fan_is_not_hit")
	late._physics_process(1.0)
	check(late.radius == 240.0 and late._spent,"layer_disappears_at_fifteen_tiles")
	var hit := CombatHit.new()
	hit.damage = 1.0
	hit.source = f.player
	actor.get_node("Health").receive_hit(hit)
	check(not impl.is_busy() and not actor.screaming and actor.monster_animation_state() == &"Hurt","shared_hurt_interrupts_scream")
	actor.kill()
	var dropped: int = 0
	for child: Node in f.holder.get_children():
		if child is GroundPickup and child.data.id in [11,12,13]:
			dropped += 1
	check(dropped == 1,"real_death_drops_one_of_three_items")
	await clear_fixture(f.holder)
	await actual_habitat_maps()
	print("SHABEI_TEST: checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
func actual_habitat_maps() -> void:
	root.get_node("GameState").set("world_seed",18473)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	var seen: Dictionary = {}
	for seed_value: int in [18473,1741004498,42,777,12345]:
		world.build_world(seed_value)
		for spec: MapSpec in world._generator.map_specs():
			if spec.biome_id not in [Biome.Kind.TAIGA, Biome.Kind.TUNDRA, Biome.Kind.SNOWY_PLAINS] or world.monster_spawner.content.budget_of(spec.node_id,MapContent.ENEMY) <= 0:
				continue
			world._enter_map(spec.node_id,-1,spec.west_gate_y)
			for frame: int in 240:
				if world.chunk_manager.map_ready():
					break
				await process_frame
			var rabbits: int = 0
			for creature: BaseMonster in world.monster_spawner.monsters:
				if creature is ShabeiMonster:
					rabbits += 1
					var tile: Vector2i = creature.original_spawn_tile
					var local: Vector2i = tile - spec.origin
					check(spec.contains_local(local.x, local.y) and world._generator.sample_biome(tile) in [Biome.Kind.TAIGA, Biome.Kind.TUNDRA, Biome.Kind.SNOWY_PLAINS],"rabbits_spawn_on_requested_room_biomes")
			check(rabbits > 0,"real_taiga_tundra_or_snow_room_has_rabbits")
			seen[spec.biome_id] = true
		if seen.size() == 3:
			break
	check(seen.has(Biome.Kind.TAIGA) and seen.has(Biome.Kind.TUNDRA) and seen.has(Biome.Kind.SNOWY_PLAINS),"real_taiga_tundra_and_snowfield_generation_verified")
	world.queue_free()
	await process_frame
	await process_frame
