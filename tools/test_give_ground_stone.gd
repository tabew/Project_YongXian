extends SceneTree

## 正式 GroundPickup 石头接入投石协议，不能只用 MockThrowableStone 验证。
class OpenGenerator extends WorldGenerator:
	var blocked_tiles: Dictionary = {}

	func is_walkable(tile: Vector2i) -> bool:
		return not blocked_tiles.has(tile)

	func sample_biome(_tile: Vector2i) -> int:
		return Biome.Kind.FOREST


const PLAYER: PackedScene = preload("res://scenes/game/player.tscn")
const GIVE: PackedScene = preload("res://scenes/monsters/give_monster.tscn")
# 在自动加载单例完成注册后再加载带炼金属性的正式材料。
var _stone_data: IngredientData
var _stick_data: IngredientData
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)


func _fixture(amount: int = 1) -> Dictionary:
	var holder := Node2D.new()
	root.add_child(holder)
	var source := OpenGenerator.new(71)
	var player := PLAYER.instantiate() as PlayerCharacter
	player.inventory = Inventory.new()
	holder.add_child(player)
	player.global_position = Vector2(136, 8)
	player.set_physics_process(false)
	var monster := GIVE.instantiate() as GiveMonster
	holder.add_child(monster)
	monster.global_position = Vector2(8, 8)
	monster.configure(player, source, Vector2i.ZERO)
	monster.set_physics_process(false)
	var stone := GroundPickup.new()
	stone.bind(_stone_data, amount, source)
	holder.add_child(stone)
	stone.global_position = Vector2(12, 8)
	return {"holder": holder, "source": source, "player": player, "monster": monster, "stone": stone}


func _clean(holder: Node) -> void:
	holder.get_parent().remove_child(holder)
	holder.queue_free()
	await process_frame


func _wait_stone(stone: GroundPickup) -> void:
	for frame: int in 90:
		if not stone._in_flight:
			break
		await physics_frame
	_check(not stone._in_flight, "flight_finishes_within_bounded_time")


func _run() -> void:
	_stone_data = load("res://resources/items/ingredients/stone.tres") as IngredientData
	_stick_data = load("res://resources/items/ingredients/stick.tres") as IngredientData
	Engine.max_fps = 120
	root.size = Vector2i(1280, 720)
	var f: Dictionary = _fixture()
	_check(f.stone.is_in_group("throwable_stones"), "real_stone_registers_as_ammo")
	_check(not f.stone.is_physics_processing(), "idle_pickup_does_not_poll_physics")
	for endpoint: Vector2 in [Vector2(16, 31.99999), Vector2(31.99999, 16), Vector2(-16, -31.99999), Vector2(8, 160), Vector2(160, 8)]:
		_check(is_inf(f.stone._terrain_block_fraction(Vector2.ZERO, endpoint)), "near_grid_endpoint_trace_terminates_without_overshooting")
	f.monster.set_physics_process(true)
	for frame: int in 120:
		await physics_frame
		if f.player.health < 10:
			break
	f.monster.set_physics_process(false)
	_check(f.player.health == 9, "actual_enemy_brain_throws_real_stone_for_one_damage")
	_check(not f.stone._in_flight and f.stone.amount == 1, "hit_stone_lands_without_consuming_material")
	_check(f.stone.collect(f.player), "landed_stone_can_be_picked_up")
	_check(f.player.inventory.get_count(2) == 1, "landed_stone_adds_exactly_one_inventory_item")
	_check(not f.stone.collect(f.player), "landed_stone_cannot_be_collected_twice")
	_check(not f.stone.is_in_group("throwable_stones"), "collected_stone_leaves_ammo_group_immediately")
	await _clean(f.holder)

	f = _fixture()
	_check(f.monster.attack.perform_attack(f.monster, f.player), "real_stone_perform_attack_succeeds")
	_check(f.stone._in_flight and not f.stone.is_in_group("throwable_stones"), "flight_reserves_ammo_atomically")
	_check(not f.stone.collect(f.player), "airborne_stone_cannot_be_collected")
	_check(not f.stone.throw_at(f.player, 1), "airborne_stone_cannot_be_thrown_twice")
	_check(not f.monster.attack.can_attack(f.monster, f.player), "second_attack_cannot_reuse_airborne_stone")
	f.stone.set_physics_process(false)
	f.player.global_position += Vector2(0, 64)
	f.stone._physics_process(1.0)
	_check(f.player.health == 10 and f.stone.global_position == Vector2(136, 8), "moving_target_evades_fixed_aim_throw")
	_check(f.stone.can_be_thrown(), "missed_stone_is_ammo_again_after_landing")
	await _clean(f.holder)

	f = _fixture(3)
	_check(f.stone.throw_at(f.player, 1), "stack_can_supply_one_throw")
	var piece: GroundPickup = null
	var total: int = 0
	for child: Node in f.holder.get_children():
		if child is GroundPickup:
			total += child.amount
			if child != f.stone:
				piece = child
	_check(total == 3 and f.stone.amount == 2 and piece != null and piece.amount == 1, "stack_splits_one_stone_without_duplication")
	if piece != null:
		piece.set_physics_process(false)
		piece._physics_process(1.0)
		_check(f.player.health == 9, "fast_swept_throw_does_not_tunnel_through_target")
		_check(f.stone.collect(f.player) and piece.collect(f.player), "both_remaining_stack_and_landed_piece_are_collectible")
		_check(f.player.inventory.get_count(2) == 3, "stack_throw_preserves_total_inventory_quantity")
	await _clean(f.holder)

	f = _fixture()
	f.source.blocked_tiles[Vector2i(3, 0)] = true
	_check(f.stone.throw_at(f.player, 1), "terrain_wall_fixture_launches")
	f.stone.set_physics_process(false)
	f.stone._physics_process(1.0)
	_check(f.player.health == 10 and f.stone.global_position.x < 48.0, "fast_throw_stops_before_virtual_terrain_wall")
	_check(f.stone.can_be_thrown(), "blocked_stone_lands_and_can_be_retrieved")
	f.source.blocked_tiles.clear()
	f.source.blocked_tiles[Vector2i(1, 0)] = true
	_check(f.stone._terrain_block_fraction(Vector2(8, 8), Vector2(24, 24)) < 1.0, "corner_grazing_throw_checks_diagonal_neighbor_cells")
	await _clean(f.holder)

	f = _fixture()
	var wall := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2, 48)
	collider.shape = shape
	wall.add_child(collider)
	f.holder.add_child(wall)
	wall.global_position = Vector2(64, 8)
	await physics_frame
	await physics_frame
	_check(f.stone.throw_at(f.player, 1), "physical_wall_fixture_launches")
	f.stone.set_physics_process(false)
	f.stone._physics_process(1.0)
	_check(f.player.health == 10 and f.stone.global_position.x < 63.0, "fast_throw_stops_before_physics_wall")
	await _clean(f.holder)

	f = _fixture()
	f.stone.bind(_stick_data)
	_check(not f.stone.is_in_group("throwable_stones") and not f.stone.throw_at(f.player, 1), "sticks_never_become_throwable_stones")
	f.stone.bind(_stone_data, 1, f.source)
	f.stone.visible = false
	_check(not f.monster.attack.can_attack(f.monster, f.player), "hidden_stone_cannot_supply_ammo")
	f.stone.visible = true
	f.holder.process_mode = Node.PROCESS_MODE_DISABLED
	_check(not f.monster.attack.can_attack(f.monster, f.player), "paused_map_stone_cannot_supply_ammo")
	f.holder.process_mode = Node.PROCESS_MODE_INHERIT
	f.stone.global_position = f.monster.global_position + Vector2(17, 0)
	_check(not f.monster.attack.can_attack(f.monster, f.player), "one_tile_stone_pickup_radius_is_preserved")
	await _clean(f.holder)

	f = _fixture()
	_check(f.stone.throw_at(f.player, 1), "freed_target_fixture_launches")
	f.stone.set_physics_process(false)
	f.player.free()
	f.stone._physics_process(1.0)
	_check(f.stone.can_be_thrown(), "freed_target_does_not_break_landing")
	await _clean(f.holder)

	await _test_actual_world_stone()
	print("GIVE_GROUND_STONE: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_actual_world_stone() -> void:
	root.get_node("GameState").set("world_seed", 18473)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	world._enter_map(3)
	var entity_root: Node2D = world._map_entity_roots[3]
	var stone: GroundPickup = null
	var caster: GiveMonster = null
	var destination: Vector2 = Vector2.ZERO
	for child: Node in entity_root.get_children():
		if not child is GroundPickup or child.data.id != 2:
			continue
		var candidate: GroundPickup = child
		caster = world.monster_spawner.spawn_monster(load("res://resources/monsters/give_spawn_data.tres"), WorldGenerator.world_to_tile(candidate.global_position)) as GiveMonster
		for offset: Vector2 in [Vector2(128, 0), Vector2(-128, 0), Vector2(0, 128), Vector2(0, -128)]:
			if caster.is_terrain_segment_clear(candidate.global_position, candidate.global_position + offset):
				stone = candidate
				destination = candidate.global_position + offset
				break
		if stone != null:
			break
		caster.get_parent().remove_child(caster)
		caster.queue_free()
	_check(stone != null, "actual_generated_map_has_throwable_stone_with_clear_shot")
	if stone == null:
		world.queue_free()
		await process_frame
		return
	_check(stone._generator == world._generator and stone.is_in_group("throwable_stones"), "actual_generated_stone_receives_world_terrain_and_ammo_protocol")
	world.player.global_position = destination
	await physics_frame
	await physics_frame
	_check(caster.attack.perform_attack(caster, world.player), "give_can_throw_actual_generated_ground_material")
	world.player.global_position = stone.global_position
	world._refresh_pickup()
	_check(world._nearby_pickup != stone, "world_e_prompt_skips_flying_stone")
	world.player.global_position = destination
	var frozen: Vector2 = stone.global_position
	world._enter_map(0)
	for frame: int in 6:
		await physics_frame
	_check(stone._in_flight and stone.global_position == frozen, "leaving_map_pauses_stone_flight")
	world._enter_map(3)
	world.player.global_position = destination
	await _wait_stone(stone)
	_check(world.player.health == 9, "returning_map_resumes_real_stone_flight_and_damage")
	world._refresh_pickup()
	_check(world._nearby_pickup == stone, "landed_real_stone_returns_to_world_pickup_prompt")
	var before: int = world.player.inventory.get_count(2)
	_check(stone.collect(world.player), "actual_thrown_stone_can_enter_inventory")
	_check(world.player.inventory.get_count(2) == before + 1, "actual_thrown_stone_is_not_duplicated_in_inventory")
	world.queue_free()
	await process_frame
	await process_frame
