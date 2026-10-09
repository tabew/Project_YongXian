extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/game/player.tscn")
const TEST_SEED: int = 24681357


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var generator := WorldGenerator.new(TEST_SEED)
	var rainforest_tile: Vector2i = _find_rainforest_tile(generator)
	if rainforest_tile == WorldGenerator.SPAWN_NOT_FOUND:
		push_error("Could not find a rainforest tile for the spawn test")
		get_tree().quit(1)
		return

	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	var manager := ChunkManager.new()
	var spawner := RainforestMonsterSpawner.new()
	get_tree().root.add_child(player)
	get_tree().root.add_child(manager)
	get_tree().root.add_child(spawner)
	player.spawn_on(generator, WorldGenerator.tile_to_world(rainforest_tile))
	spawner.setup(generator, manager, player)

	var center_chunk: Vector2i = WorldGenerator.tile_to_chunk(rainforest_tile)
	for dy: int in range(-4, 5):
		for dx: int in range(-4, 5):
			spawner._on_chunk_applied(center_chunk + Vector2i(dx, dy))

	var monster_count: int = 0
	var all_in_rainforest: bool = true
	for child: Node in spawner.get_children():
		if child is GiveMonster:
			monster_count += 1
			var tile: Vector2i = WorldGenerator.world_to_tile((child as GiveMonster).global_position)
			if generator.sample_biome(tile) != Biome.Kind.TROPICAL_RAINFOREST:
				all_in_rainforest = false

	if monster_count <= 0:
		push_error("No rainforest monsters spawned in the scanned chunks")
		get_tree().quit(1)
		return
	elif not all_in_rainforest:
		push_error("A rainforest monster spawned outside the tropical rainforest biome")
		get_tree().quit(1)
		return

	var next_generator := WorldGenerator.new(TEST_SEED + 1)
	spawner.setup(next_generator, manager, player)
	if spawner.get_child_count() != 0 or spawner.get_spawned_monster_count() != 0:
		push_error("Changing worlds did not clear previous monsters and test stones")
		get_tree().quit(1)
	else:
		print("RAINFOREST_SPAWNER_TEST_PASSED monsters=", monster_count)
		get_tree().quit(0)


func _find_rainforest_tile(generator: WorldGenerator) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = TEST_SEED
	for _attempt: int in 5000:
		var tile := Vector2i(
			rng.randi_range(-2000, 2000),
			rng.randi_range(-2000, 2000)
		)
		if generator.sample_biome(tile) == Biome.Kind.TROPICAL_RAINFOREST:
			if generator.is_walkable(tile):
				return tile
	return WorldGenerator.SPAWN_NOT_FOUND
