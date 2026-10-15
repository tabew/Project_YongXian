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

func wait_for_room(world: Node2D) -> void:
	for frame: int in 480:
		if world.chunk_manager.map_ready() and world.monster_spawner.get_pending_spawn_count() == 0:
			return
		await process_frame
	check(false, "room_and_spawn_queue_finish_loading")

func _run() -> void:
	Engine.max_fps = 240
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 18473)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	var target: MapSpec = null
	for spec: MapSpec in world._generator.map_specs():
		if spec.biome_id == Biome.Kind.SWAMP and world.monster_spawner.content.budget_of(spec.node_id, MapContent.ENEMY) > 0:
			target = spec
			break
	check(target != null, "dense_swamp_combat_exists")
	if target == null:
		quit(1)
		return
	var spawner: MonsterSpawner = world.monster_spawner
	world._enter_map(target.node_id, -1, target.west_gate_y)
	check(spawner._defer_non_gate_spawns, "live_room_uses_spawn_budget")
	spawner.set_process(false)
	for frame: int in 480:
		if world.chunk_manager.map_ready():
			break
		await process_frame
	check(world.chunk_manager.map_ready(), "terrain_finishes_while_spawns_wait")
	var entrance_count: int = 0
	for actor: BaseMonster in spawner.monsters:
		if actor is ShiMonster and actor.global_position.distance_to(world.player.global_position) < 16.0 * 15.0:
			entrance_count += 1
	check(entrance_count >= 3, "gate_encounter_is_immediate")
	world.chunk_manager.set_process(false)
	var waiting: int = spawner.get_pending_spawn_count()
	check(waiting > spawner.spawns_per_frame, "interior_slots_are_queued_not_instantiated_at_entry")
	spawner.set_process(true)
	spawner._process(0.016)
	check(spawner.get_pending_spawn_count() == maxi(waiting - spawner.spawns_per_frame, 0), "spawn_budget_limits_one_frame")
	world._enter_map(0)
	check(spawner.monsters.is_empty() and spawner.get_pending_spawn_count() == 0, "leaving_room_cancels_queued_slots")
	world.chunk_manager.set_process(true)
	world._enter_map(target.node_id)
	await wait_for_room(world)
	var dormant: BaseMonster = null
	var engaged: BaseMonster = null
	for actor: BaseMonster in spawner.monsters:
		if actor.process_mode == Node.PROCESS_MODE_DISABLED and (dormant == null or actor is ShiMonster):
			dormant = actor
		if actor.process_mode != Node.PROCESS_MODE_DISABLED and engaged == null:
			engaged = actor
	check(dormant != null and engaged != null, "far_patrollers_sleep_while_entrance_encounter_stays_active")
	if engaged != null:
		var saved_position: Vector2 = world.player.global_position
		var saved_state: EnemyState.State = engaged.blackboard.state
		engaged.blackboard.state = EnemyState.State.CHASE
		world.player.global_position = engaged.global_position + Vector2(16.0 * 60.0, 0.0)
		spawner._update_monster_activity(engaged)
		check(engaged.process_mode != Node.PROCESS_MODE_DISABLED, "chasing_actor_never_sleeps")
		world.player.global_position = saved_position
		engaged.blackboard.state = saved_state
	if dormant != null:
		var original_player_position: Vector2 = world.player.global_position
		world.player.global_position = dormant.global_position
		spawner._process(0.25)
		check(dormant.process_mode == Node.PROCESS_MODE_INHERIT, "nearby_dormant_actor_wakes")
		world.player.global_position = original_player_position
		dormant._visual_height = 5.0
		spawner._update_monster_activity(dormant)
		check(dormant.process_mode == Node.PROCESS_MODE_INHERIT, "midair_actor_does_not_sleep")
		dormant._visual_height = 0.0
		if dormant is ShiMonster:
			(dormant as ShiMonster)._hop_active = true
			spawner._update_monster_activity(dormant)
			check(dormant.process_mode == Node.PROCESS_MODE_INHERIT, "slime_hop_does_not_freeze")
			(dormant as ShiMonster)._hop_active = false
		dormant.navigator.pending_generation = 123
		spawner._update_monster_activity(dormant)
		check(dormant.process_mode == Node.PROCESS_MODE_DISABLED, "far_idle_actor_can_sleep_again")
		check(dormant.navigator.pending_generation == -1, "sleep_clears_stale_navigation_request")
		var hit := CombatHit.new()
		hit.source = world.player
		hit.position = dormant.global_position
		hit.damage = 1.0
		(dormant.get_node("Health") as HealthComponent).receive_hit(hit)
		check(dormant.process_mode == Node.PROCESS_MODE_INHERIT and dormant.is_receiving_knockback(), "damage_wakes_before_hit_reaction")
		spawner._update_monster_activity(dormant)
		check(dormant.process_mode == Node.PROCESS_MODE_INHERIT, "knockback_prevents_immediate_resleep")
		var candidate: BaseMonster = null
		for actor: BaseMonster in spawner.monsters:
			if actor != dormant and actor.process_mode == Node.PROCESS_MODE_DISABLED:
				candidate = actor
				break
		check(candidate != null, "another_dormant_actor_exists_for_death_test")
		if candidate != null:
			root.get_node("EventBus").emit_signal(&"noise_reported", candidate.global_position, 16.0, world.player)
			check(candidate.process_mode == Node.PROCESS_MODE_INHERIT and candidate.blackboard.has_suspicious_event, "heard_noise_wakes_dormant_actor_immediately")
			candidate.blackboard.has_suspicious_event = false
			spawner._update_monster_activity(candidate)
			check(candidate.process_mode == Node.PROCESS_MODE_DISABLED, "distant_actor_can_sleep_again_after_alert")
			var dead_tile: Vector2i = WorldGenerator.world_to_tile(candidate.global_position)
			var definition: MonsterSpawnData = null
			for possible: MonsterSpawnData in spawner.spawn_definitions:
				if (candidate is CrocodileMonster and possible.monster_id == &"crocodile") or (candidate is ShiMonster and possible.monster_id == &"shi"):
					definition = possible
					break
			check(definition != null, "dormant_victim_species_is_registered")
			candidate.kill()
			check(definition != null and spawner._defeated_spawn_ids.has(spawner._spawn_id(definition, dead_tile)), "sleeping_victim_records_death")
			world._enter_map(0)
			world._enter_map(target.node_id)
			await wait_for_room(world)
			check(definition != null and spawner.spawn_monster(definition, dead_tile) == null, "return_does_not_revive_sleeping_victim")
	world.queue_free()
	await process_frame
	await process_frame
	print("MONSTER_ACTIVITY_BUDGET: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
