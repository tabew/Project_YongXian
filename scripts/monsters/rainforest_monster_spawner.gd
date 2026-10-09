class_name RainforestMonsterSpawner
extends Node2D

## 按世界种子与区块坐标稳定随机，只在热带雨林中生成“给”。

const GIVE_MONSTER_SCENE: PackedScene = preload("res://scenes/monsters/give_monster.tscn")
const MONSTERS_PER_RAINFOREST_CHUNK: int = 2
const CANDIDATE_ATTEMPTS: int = 32
const DESPAWN_MARGIN_CHUNKS: int = 2

var _generator: WorldGenerator = null
var _chunk_manager: ChunkManager = null
var _player: PlayerCharacter = null
var _entities_by_chunk: Dictionary = {}


func setup(
	generator: WorldGenerator,
	chunk_manager: ChunkManager,
	player: PlayerCharacter
) -> void:
	_clear_entities()
	_generator = generator
	_player = player
	if _chunk_manager != null and _chunk_manager.chunk_applied.is_connected(_on_chunk_applied):
		_chunk_manager.chunk_applied.disconnect(_on_chunk_applied)
	_chunk_manager = chunk_manager
	if not _chunk_manager.chunk_applied.is_connected(_on_chunk_applied):
		_chunk_manager.chunk_applied.connect(_on_chunk_applied)

	for coords: Vector2i in _chunk_manager.loaded_chunks():
		_on_chunk_applied(coords)


func _process(_delta: float) -> void:
	if _chunk_manager == null or not is_instance_valid(_player):
		return
	var player_chunk: Vector2i = WorldGenerator.tile_to_chunk(
		WorldGenerator.world_to_tile(_player.global_position)
	)
	var limit: int = _chunk_manager.unload_radius + DESPAWN_MARGIN_CHUNKS
	for coords: Vector2i in _entities_by_chunk.keys():
		var distance: Vector2i = (coords - player_chunk).abs()
		if maxi(distance.x, distance.y) > limit:
			_remove_chunk_entities(coords)


func _on_chunk_applied(coords: Vector2i) -> void:
	if _generator == null or _entities_by_chunk.has(coords):
		return
	var entities: Array[Node] = []
	_entities_by_chunk[coords] = entities

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_generator.world_seed, coords.x, coords.y, "give"])
	var origin: Vector2i = coords * WorldGenerator.CHUNK_SIZE
	var occupied: Dictionary = {}
	var spawned: int = 0
	for _attempt: int in CANDIDATE_ATTEMPTS:
		if spawned >= MONSTERS_PER_RAINFOREST_CHUNK:
			break
		var tile := origin + Vector2i(
			rng.randi_range(0, WorldGenerator.CHUNK_SIZE - 1),
			rng.randi_range(0, WorldGenerator.CHUNK_SIZE - 1)
		)
		if occupied.has(tile):
			continue
		occupied[tile] = true
		if _generator.sample_biome(tile) != Biome.Kind.TROPICAL_RAINFOREST:
			continue
		if not _generator.is_walkable(tile):
			continue

		var monster := GIVE_MONSTER_SCENE.instantiate() as GiveMonster
		add_child(monster)
		monster.global_position = WorldGenerator.tile_to_world(tile)
		monster.configure(_player, _generator, coords)
		entities.append(monster)
		spawned += 1


func _remove_chunk_entities(coords: Vector2i) -> void:
	var entities: Array = _entities_by_chunk.get(coords, [])
	for entity: Node in entities:
		if is_instance_valid(entity):
			if entity.get_parent() != null:
				entity.get_parent().remove_child(entity)
			entity.queue_free()
	_entities_by_chunk.erase(coords)


func _clear_entities() -> void:
	for coords: Vector2i in _entities_by_chunk.keys():
		_remove_chunk_entities(coords)
	_entities_by_chunk.clear()


func get_spawned_monster_count() -> int:
	var count: int = 0
	for entities: Array in _entities_by_chunk.values():
		for entity: Node in entities:
			if is_instance_valid(entity) and entity is GiveMonster:
				count += 1
	return count
