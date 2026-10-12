extends Node

class SpawnBiomeGenerator extends WorldGenerator:
	var test_biome: int = Biome.Kind.FOREST
	var walkable: bool = true

	func sample_biome(_tile: Vector2i) -> int:
		return test_biome

	func is_walkable(_tile: Vector2i) -> bool:
		return walkable


const PLAYER_SCENE: PackedScene = preload("res://scenes/game/player.tscn")
const BASE_SCENE: PackedScene = preload("res://scenes/monsters/base_monster.tscn")
const GIVE_SPAWN_DATA: MonsterSpawnData = preload("res://resources/monsters/give_spawn_data.tres")
const ALLOWED_BIOMES: Array[int] = [
	Biome.Kind.FOREST, Biome.Kind.TAIGA, Biome.Kind.TROPICAL_RAINFOREST,
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var generator := SpawnBiomeGenerator.new(24681357)
	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	var manager := ChunkManager.new()
	var spawner := MonsterSpawner.new()
	spawner.spawn_definitions = [GIVE_SPAWN_DATA]
	get_tree().root.add_child(player)
	get_tree().root.add_child(manager)
	get_tree().root.add_child(spawner)
	spawner.set_process(false)

	for biome: int in Biome.COUNT:
		generator.test_biome = biome
		player.spawn_on(generator, WorldGenerator.tile_to_world(Vector2i.ZERO))
		spawner.setup(generator, manager, player)
		spawner._on_chunk_applied(Vector2i.ZERO)
		var expected: int = GIVE_SPAWN_DATA.max_per_chunk if biome in ALLOWED_BIOMES else 0
		if spawner.monsters.size() != expected or spawner.get_child_count() != expected:
			_fail("Wrong spawn count for biome %s: %d" % [Biome.name_of(biome), spawner.monsters.size()])
			return
		for monster: BaseMonster in spawner.monsters:
			monster.set_physics_process(false)
			if monster.get_parent() != spawner:
				_fail("Generated monster is not parented to MonsterSpawner")
				return

	generator.test_biome = Biome.Kind.FOREST
	spawner.setup(generator, manager, player)
	spawner._on_chunk_applied(Vector2i.ZERO)
	var before_death: int = spawner.monsters.size()
	for monster: BaseMonster in spawner.monsters:
		monster.set_physics_process(false)
	spawner.monsters[0].kill()
	await get_tree().process_frame
	if spawner.monsters.size() != before_death - 1:
		_fail("Dead monster reference was not removed from the live array")
		return

	generator.walkable = false
	spawner.setup(generator, manager, player)
	spawner._on_chunk_applied(Vector2i.ZERO)
	if not spawner.monsters.is_empty() or spawner.get_child_count() != 0:
		_fail("Blocked forest tiles must not spawn monsters")
		return

	var template_data := MonsterSpawnData.new()
	template_data.monster_id = &"template_test"
	template_data.monster_scene = BASE_SCENE
	var template_monster: BaseMonster = spawner.spawn_monster(template_data, Vector2i(3, 2), Vector2i.ZERO)
	if template_monster == null or template_monster.player != player or template_monster.world_generator != generator:
		_fail("Base template did not receive the shared generator configuration")
		return
	if template_monster.spawn_chunk != Vector2i.ZERO or template_monster.health_bar == null:
		_fail("Base template is missing its spawn context or inherited health bar")
		return
	spawner.clear_monsters()
	if not spawner.monsters.is_empty() or spawner.get_child_count() != 0:
		_fail("Base template did not clean up through MonsterSpawner")
		return

	print("FOREST_SPAWNER_TEST_PASSED allowed=forest,taiga,rainforest other_biomes_rejected=true template_configured=true")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
