extends Node2D

## 真正死亡与地图卸载必须区分，返图不能补刷死怪，新开一局必须重置。
class FlatGenerator extends WorldGenerator:
	func sample_biome(_tile: Vector2i) -> int:
		return Biome.Kind.FOREST

	func is_walkable(_tile: Vector2i) -> bool:
		return true


class VisibleChunkManager extends ChunkManager:
	var visible_chunks: Array[Vector2i] = [Vector2i.ZERO]

	func loaded_chunks() -> Array[Vector2i]:
		return visible_chunks.duplicate()


const GIVE_DATA: MonsterSpawnData = preload("res://resources/monsters/give_spawn_data.tres")
const PLAYER: PackedScene = preload("res://scenes/game/player.tscn")
const OTHER_CHUNK: Vector2i = Vector2i(2, 1)

var _passed: bool = true
var _player: PlayerCharacter
var _manager: VisibleChunkManager
var _spawner: MonsterSpawner
var _generator: FlatGenerator


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	print("PERSISTENCE_CHECK ", description, "=", condition)
	if not condition:
		_passed = false
		push_error(description)


func _tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for monster: BaseMonster in _spawner.monsters:
		result.append(WorldGenerator.world_to_tile(monster.global_position))
	return result


func _enter_chunk(coords: Vector2i) -> void:
	_manager.visible_chunks = [coords]
	_spawner.setup(_generator, _manager, _player)


func _run() -> void:
	_generator = FlatGenerator.new(24681357)
	_player = PLAYER.instantiate() as PlayerCharacter
	_player.inventory = Inventory.new()
	_manager = VisibleChunkManager.new()
	_spawner = MonsterSpawner.new()
	_spawner.spawn_definitions = [GIVE_DATA]
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_manager.process_mode = Node.PROCESS_MODE_DISABLED
	_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_player)
	add_child(_manager)
	add_child(_spawner)
	_enter_chunk(Vector2i.ZERO)
	var original: Array[Vector2i] = _tiles()
	_check(original.size() == GIVE_DATA.max_per_chunk, "initial_chunk_has_original_monsters")
	if original.size() != GIVE_DATA.max_per_chunk:
		get_tree().quit(1)
		return

	# 一只怪物离开原始生成格后被正常伤害击杀；同帧离图也必须记住原身份。
	var victim: BaseMonster = _spawner.monsters[0]
	var killed_tile: Vector2i = original[0]
	victim.global_position += Vector2(640, 640)
	var hit := CombatHit.new()
	hit.damage = (victim.get_node("Health") as HealthComponent).current_health
	(victim.get_node("Health") as HealthComponent).receive_hit(hit)
	_enter_chunk(OTHER_CHUNK)
	await get_tree().process_frame
	var other_original: Array[Vector2i] = _tiles()
	_check(other_original.size() == GIVE_DATA.max_per_chunk, "other_chunk_is_unaffected")
	_enter_chunk(Vector2i.ZERO)
	var survivors: Array[Vector2i] = _tiles()
	_check(survivors.size() == original.size() - 1, "return_does_not_replace_the_killed_slot")
	_check(not survivors.has(killed_tile) and survivors.has(original[1]), "only_original_survivor_returns")
	_enter_chunk(OTHER_CHUNK)
	_check(_tiles().size() == other_original.size(), "unloading_alive_monsters_is_not_a_kill")
	for tile: Vector2i in other_original:
		_check(_tiles().has(tile), "other_chunk_keeps_its_original_spawn")
	_enter_chunk(Vector2i.ZERO)
	_check(_tiles().size() == 1, "repeated_returns_keep_the_death_record")

	# K 调试全灭也是真正死亡，携带道具仍保留。
	var carried_item := Node2D.new()
	_spawner.monsters[0].add_child(carried_item)
	carried_item.add_to_group("ingredients")
	GameWorld.kill_monsters_in_tree(get_tree())
	await get_tree().process_frame
	_check(_spawner.monsters.is_empty(), "debug_kill_clears_remaining_monsters")
	_check(is_instance_valid(carried_item) and carried_item.get_parent() == _spawner, "debug_kill_preserves_carried_items")
	_spawner._on_chunk_applied(Vector2i.ZERO)
	_check(_spawner.monsters.is_empty(), "reapplied_chunk_does_not_respawn_a_cleared_group")
	_enter_chunk(OTHER_CHUNK)
	_enter_chunk(Vector2i.ZERO)
	_check(_spawner.monsters.is_empty(), "cleared_chunk_stays_empty_after_return")
	_check(_spawner.spawn_monster(GIVE_DATA, killed_tile) == null, "explicit_spawn_cannot_revive_a_dead_slot")

	# 新世界实例即新的一局，哪怕种子相同也应正常生成怪物。
	_generator = FlatGenerator.new(24681357)
	_enter_chunk(Vector2i.ZERO)
	_check(_tiles().size() == original.size(), "new_run_with_same_seed_resets_kill_records")
	for tile: Vector2i in original:
		_check(_tiles().has(tile), "new_run_uses_original_deterministic_spawns")
	_spawner._remove_chunk_monsters(Vector2i.ZERO)
	_spawner._on_chunk_applied(Vector2i.ZERO)
	_check(_tiles().size() == original.size(), "distance_unload_does_not_mark_alive_monsters_dead")

	_spawner.queue_free()
	_manager.queue_free()
	_player.queue_free()
	await get_tree().process_frame
	print("MONSTER_PERSISTENCE_RESULT=", _passed)
	get_tree().quit(0 if _passed else 1)
