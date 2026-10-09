extends Node

class AlwaysRainforestGenerator extends WorldGenerator:
	func sample_biome(_tile: Vector2i) -> int:
		return Biome.Kind.TROPICAL_RAINFOREST

	func is_walkable(_tile: Vector2i) -> bool:
		return true


class RainforestWallGenerator extends WorldGenerator:
	func sample_biome(_tile: Vector2i) -> int:
		return Biome.Kind.TROPICAL_RAINFOREST

	func is_walkable(tile: Vector2i) -> bool:
		return not (tile.x == 2 and tile.y >= -1 and tile.y <= 1)


class RainforestSpawnOpenWorldGenerator extends WorldGenerator:
	func sample_biome(tile: Vector2i) -> int:
		return Biome.Kind.TROPICAL_RAINFOREST if tile.x <= 0 else Biome.Kind.GRASSLAND

	func is_walkable(_tile: Vector2i) -> bool:
		return true


class MockThrowableStone extends Node2D:
	func _ready() -> void:
		add_to_group("ingredients")
		add_to_group("throwable_stones")

	func throw_at(target: PlayerCharacter, damage: int) -> void:
		remove_from_group("throwable_stones")
		target.take_damage(damage)


const PLAYER_SCENE: PackedScene = preload("res://scenes/game/player.tscn")
const MONSTER_SCENE: PackedScene = preload("res://scenes/monsters/give_monster.tscn")

var _generator := AlwaysRainforestGenerator.new(12345)
var _player: PlayerCharacter = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_player = PLAYER_SCENE.instantiate() as PlayerCharacter
	get_tree().root.add_child(_player)
	await get_tree().process_frame

	var passed: bool = true
	var navigation_only: bool = "--navigation-only" in OS.get_cmdline_user_args()
	if navigation_only:
		print("TEST_WALL_PATHFINDING")
		passed = await _test_wall_pathfinding() and passed
		print("TEST_PHYSICS_WALL_PATHFINDING")
		passed = await _test_physics_wall_pathfinding() and passed
	else:
		print("TEST_ITEM_DATA")
		passed = _test_item_data_contract() and passed
		print("TEST_ATTACK_CONFIGURATION")
		passed = _test_attack_configuration() and passed
		print("TEST_HEALTH_AND_KILL_ALL")
		passed = await _test_health_and_kill_all() and passed
		print("TEST_OUTSIDE_AGGRO")
		passed = await _test_outside_aggro() and passed
		print("TEST_CROSS_BIOME_PURSUIT")
		passed = await _test_cross_biome_pursuit() and passed
		print("TEST_RANGED_ATTACK")
		passed = await _test_ranged_attack() and passed
		print("TEST_LEAP_ATTACK")
		passed = await _test_leap_attack() and passed
		print("TEST_RANGED_WITHOUT_STONE")
		passed = await _test_ranged_without_stone() and passed
		print("TEST_MAX_RANGE_ATTACK")
		passed = await _test_max_range_attack() and passed

	print("GIVE_MONSTER_TEST_RESULT=", passed)
	if passed:
		print("GIVE_MONSTER_TESTS_PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _test_item_data_contract() -> bool:
	var ingredient := IngredientData.new()
	var passed: bool = (
		ingredient is ItemData
		and ingredient.alchemical_attribute != null
		and ingredient.physical_attribute != null
		and ingredient.create_model() == null
	)
	if not passed:
		push_error("IngredientData no longer follows the shared ItemData contract")
	return passed


func _test_attack_configuration() -> bool:
	var tile_size: float = float(WorldGenerator.TILE_SIZE)
	var passed: bool = (
		is_equal_approx(GiveMonster.ATTACK_COOLDOWN, 1.0)
		and is_equal_approx(GiveMonster.AGGRO_RANGE, tile_size * 10.0)
		and is_equal_approx(GiveMonster.RANGED_MIN_RANGE, tile_size * 6.0)
		and is_equal_approx(GiveMonster.RANGED_MAX_RANGE, tile_size * 10.0)
		and is_equal_approx(GiveMonster.LEAP_MAX_RANGE, tile_size * 6.0)
		and _has_k_kill_binding()
	)
	if not passed:
		push_error("给 attack ranges or shared attack interval do not match the design")
	return passed


func _has_k_kill_binding() -> bool:
	if not InputMap.has_action("kill_all_monsters"):
		return false
	for event: InputEvent in InputMap.action_get_events("kill_all_monsters"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_K:
			return true
	return false


func _test_health_and_kill_all() -> bool:
	var monster := MONSTER_SCENE.instantiate() as GiveMonster
	get_tree().root.add_child(monster)
	var carried_stone := MockThrowableStone.new()
	monster.add_child(carried_stone)
	carried_stone.position = Vector2(8.0, 0.0)
	var loose_stone := MockThrowableStone.new()
	get_tree().root.add_child(loose_stone)

	var started_at_one_hundred: bool = monster.health == 100
	var weapon_hit := CombatHit.new()
	weapon_hit.source = _player
	weapon_hit.damage = 99.0
	weapon_hit.position = monster.global_position
	var hurtbox := monster.get_node("Hurtbox") as CombatHurtbox
	var weapon_hit_received: bool = hurtbox.receive_hit(weapon_hit)
	var damage_applied: bool = weapon_hit_received and monster.health == 1
	GameWorld.kill_monsters_in_tree(get_tree())
	var carried_item_released: bool = carried_stone.get_parent() == get_tree().root
	var loose_item_untouched: bool = loose_stone.get_parent() == get_tree().root
	await get_tree().process_frame
	var monster_removed: bool = not is_instance_valid(monster)
	var items_survived: bool = (
		is_instance_valid(carried_stone) and is_instance_valid(loose_stone)
	)
	var passed: bool = (
		started_at_one_hundred and damage_applied and monster_removed
		and carried_item_released and loose_item_untouched and items_survived
	)
	_remove_node(carried_stone)
	_remove_node(loose_stone)
	print("HEALTH_KILL_ALL_RESULT=", passed)
	if not passed:
		push_error("Monster health or monster-only global kill behavior is incorrect")
	return passed


func _test_outside_aggro() -> bool:
	_player.spawn_on(_generator, Vector2(WorldGenerator.TILE_SIZE * 11, 0))
	var monster: GiveMonster = _spawn_monster(Vector2.ZERO)
	await get_tree().create_timer(0.15).timeout
	var passed: bool = not monster.has_attack_intent() and _player.health == 10
	_remove_node(monster)
	print("OUTSIDE_AGGRO_RESULT=", passed)
	if not passed:
		push_error("Monster became aggressive beyond ten tiles")
	return passed


func _test_wall_pathfinding() -> bool:
	var wall_generator := RainforestWallGenerator.new(67890)
	_player.spawn_on(wall_generator, WorldGenerator.tile_to_world(Vector2i(4, 0)))
	var monster := MONSTER_SCENE.instantiate() as GiveMonster
	get_tree().root.add_child(monster)
	monster.global_position = WorldGenerator.tile_to_world(Vector2i(0, 0))
	monster.navigation_speed = 240.0
	monster.configure(_player, wall_generator, Vector2i.ZERO)
	var stone := MockThrowableStone.new()
	monster.add_child(stone)
	stone.position = Vector2(8.0, 0.0)

	await get_tree().physics_frame
	await get_tree().physics_frame
	var did_not_lock_through_wall: bool = not monster.has_attack_intent()
	var crossed_wall: bool = false
	var moved_around_wall: bool = false
	for _frame: int in 120:
		await get_tree().physics_frame
		var tile: Vector2i = WorldGenerator.world_to_tile(monster.global_position)
		if tile.x == 2 and tile.y >= -1 and tile.y <= 1:
			crossed_wall = true
		if absf(monster.global_position.y - WorldGenerator.tile_to_world(Vector2i.ZERO).y) > 8.0:
			moved_around_wall = true
		if moved_around_wall and _player.health < 10:
			break

	var passed: bool = (
		did_not_lock_through_wall
		and not crossed_wall
		and moved_around_wall
		and _player.health == 9
	)
	print("TERRAIN_WALL_RESULT=", passed)
	_remove_node(monster)
	_remove_node(stone)
	if not passed:
		push_error(
			"Wall navigation failed: no_lock=%s crossed=%s moved=%s health=%d"
			% [
				did_not_lock_through_wall, crossed_wall,
				moved_around_wall, _player.health,
			]
		)
	return passed


func _test_physics_wall_pathfinding() -> bool:
	_player.spawn_on(_generator, WorldGenerator.tile_to_world(Vector2i(4, 0)))
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(WorldGenerator.TILE_SIZE, WorldGenerator.TILE_SIZE * 3)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	get_tree().root.add_child(wall)
	wall.global_position = WorldGenerator.tile_to_world(Vector2i(2, 0))

	var monster := MONSTER_SCENE.instantiate() as GiveMonster
	get_tree().root.add_child(monster)
	monster.global_position = WorldGenerator.tile_to_world(Vector2i(0, 0))
	monster.navigation_speed = 240.0
	monster.configure(_player, _generator, Vector2i.ZERO)
	var stone := MockThrowableStone.new()
	monster.add_child(stone)
	stone.position = Vector2(8.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var did_not_lock_through_wall: bool = not monster.has_attack_intent()
	var moved_around_wall: bool = false
	for _frame: int in 120:
		await get_tree().physics_frame
		if absf(monster.global_position.y - wall.global_position.y) > WorldGenerator.TILE_SIZE * 1.5:
			moved_around_wall = true
		if moved_around_wall and _player.health < 10:
			break

	var passed: bool = (
		did_not_lock_through_wall and moved_around_wall and _player.health == 9
	)
	print(
		"PHYSICS_WALL_RESULT=", passed,
		" no_lock=", did_not_lock_through_wall,
		" moved=", moved_around_wall,
		" health=", _player.health,
		" position=", monster.global_position
	)
	_remove_node(monster)
	_remove_node(stone)
	_remove_node(wall)
	if not passed:
		push_error(
			"Physics wall navigation failed: no_lock=%s moved=%s health=%d"
			% [did_not_lock_through_wall, moved_around_wall, _player.health]
		)
	return passed


func _test_cross_biome_pursuit() -> bool:
	var mixed_generator := RainforestSpawnOpenWorldGenerator.new(24680)
	_player.spawn_on(mixed_generator, WorldGenerator.tile_to_world(Vector2i(5, 0)))
	var monster := MONSTER_SCENE.instantiate() as GiveMonster
	get_tree().root.add_child(monster)
	monster.global_position = WorldGenerator.tile_to_world(Vector2i(0, 0))
	monster.configure(_player, mixed_generator, Vector2i.ZERO)

	for _frame: int in 60:
		await get_tree().physics_frame
		if _player.health < 10:
			break
	var monster_tile: Vector2i = WorldGenerator.world_to_tile(monster.global_position)
	var left_rainforest: bool = (
		mixed_generator.sample_biome(monster_tile) != Biome.Kind.TROPICAL_RAINFOREST
	)
	var passed: bool = left_rainforest and _player.health == 9
	_remove_node(monster)
	print("CROSS_BIOME_RESULT=", passed, " tile=", monster_tile)
	if not passed:
		push_error("给 did not leave its rainforest spawn biome while pursuing the player")
	return passed


func _test_ranged_attack() -> bool:
	_player.spawn_on(_generator, Vector2(WorldGenerator.TILE_SIZE * 6, 0))
	var monster: GiveMonster = _spawn_monster(Vector2.ZERO)
	var stone := MockThrowableStone.new()
	get_tree().root.add_child(stone)
	stone.global_position = Vector2(8, 0)
	for _frame: int in 90:
		await get_tree().physics_frame
		if _player.health < 10:
			break
	var passed: bool = _player.health == 9
	_remove_node(monster)
	_remove_node(stone)
	print("RANGED_ATTACK_RESULT=", passed, " health=", _player.health)
	if not passed:
		push_error("Ranged stone attack did not deal exactly one damage")
	return passed


func _test_leap_attack() -> bool:
	_player.spawn_on(_generator, Vector2(WorldGenerator.TILE_SIZE * 5, 0))
	var monster: GiveMonster = _spawn_monster(Vector2.ZERO)
	for _frame: int in 60:
		await get_tree().physics_frame
		if _player.health < 10:
			break
	var passed: bool = _player.health == 9
	_remove_node(monster)
	print("LEAP_ATTACK_RESULT=", passed, " health=", _player.health)
	if not passed:
		push_error("Leap melee attack did not deal exactly one damage")
	return passed


func _test_ranged_without_stone() -> bool:
	_player.spawn_on(_generator, Vector2(WorldGenerator.TILE_SIZE * 8, 0))
	var monster: GiveMonster = _spawn_monster(Vector2.ZERO)
	for _frame: int in 15:
		await get_tree().physics_frame
	var passed: bool = (
		_player.health == 10
		and not monster.has_attack_intent()
		and is_zero_approx(monster._attack_cooldown)
	)
	_remove_node(monster)
	print("NO_STONE_RESULT=", passed, " health=", _player.health)
	if not passed:
		push_error("给 did not stop its ranged attack when no stone was nearby")
	return passed


func _test_max_range_attack() -> bool:
	_player.spawn_on(_generator, Vector2(WorldGenerator.TILE_SIZE * 10, 0))
	var monster: GiveMonster = _spawn_monster(Vector2.ZERO)
	var stone := MockThrowableStone.new()
	get_tree().root.add_child(stone)
	stone.global_position = Vector2(8, 0)
	for _frame: int in 90:
		await get_tree().physics_frame
		if _player.health < 10:
			break
	var passed: bool = _player.health == 9
	_remove_node(monster)
	_remove_node(stone)
	print("MAX_RANGE_RESULT=", passed, " health=", _player.health)
	if not passed:
		push_error("给 did not throw at the inclusive ten-tile maximum range")
	return passed


func _spawn_monster(position: Vector2) -> GiveMonster:
	var monster := MONSTER_SCENE.instantiate() as GiveMonster
	get_tree().root.add_child(monster)
	monster.global_position = position
	monster.configure(_player, _generator, Vector2i.ZERO)
	return monster


func _remove_node(node: Variant) -> void:
	if is_instance_valid(node):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()
