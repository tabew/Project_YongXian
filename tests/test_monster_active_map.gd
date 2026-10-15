extends Node

## 两个战斗区域共享一个区块时，邻图不能抢走当前地图的生成名额。
class SharedChunkGenerator extends WorldGenerator:
	var current_spec: MapSpec
	var neighbor_spec: MapSpec

	func sample_biome(_tile: Vector2i) -> int:
		return Biome.Kind.TROPICAL_RAINFOREST

	func is_walkable(_tile: Vector2i) -> bool:
		return true

	func sample_map(tile: Vector2i) -> MapSpec:
		return current_spec if tile.x < 16 else neighbor_spec


const DATA: MonsterSpawnData = preload("res://resources/monsters/give_spawn_data.tres")
const PLAYER: PackedScene = preload("res://scenes/game/player.tscn")
var _passed: bool = true


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	print("ACTIVE_MAP_CHECK ", description, "=", condition)
	if not condition:
		_passed = false
		push_error(description)


func _spawn(spawner: MonsterSpawner, generator: WorldGenerator, manager: ChunkManager, player: PlayerCharacter, spec: MapSpec = null) -> void:
	spawner.setup(generator, manager, player, spec)
	spawner._on_chunk_applied(Vector2i.ZERO)


func _run() -> void:
	# 选择前两个有效候选都位于邻图的种子，稳定复现先占名额后被裁掉的问题。
	var seed_value: int = 0
	for candidate: int in range(1, 128):
		var source: RandomNumberGenerator = MapRng.enemy_chunk_rng(candidate, Vector2i.ZERO, DATA.monster_id)
		source.randf()
		var first := Vector2i(source.randi_range(0, 31), source.randi_range(0, 31))
		var second := Vector2i(source.randi_range(0, 31), source.randi_range(0, 31))
		if first.x >= 16 and second.x >= 16 and first != second:
			seed_value = candidate
			break
	_check(seed_value != 0, "reproduction_seed_exists")
	var generator := SharedChunkGenerator.new(seed_value)
	var current := MapSpec.new()
	current.node_id = 2
	current.origin = Vector2i.ZERO
	current.extent = Vector2i(16, 32)
	current.biome_id = Biome.Kind.TROPICAL_RAINFOREST
	var neighbor := MapSpec.new()
	neighbor.node_id = 3
	neighbor.origin = Vector2i(16, 0)
	neighbor.extent = Vector2i(16, 32)
	neighbor.biome_id = Biome.Kind.TROPICAL_RAINFOREST
	generator.current_spec = current
	generator.neighbor_spec = neighbor
	var content := MapContent.new()
	content.entries[2] = [{"kind": MapContent.ENEMY, "budget": 3}]
	content.entries[3] = [{"kind": MapContent.ENEMY, "budget": 3}]
	var player := PLAYER.instantiate() as PlayerCharacter
	player.inventory = Inventory.new()
	var manager := ChunkManager.new()
	var spawner := MonsterSpawner.new()
	spawner.spawn_definitions = [DATA]
	spawner.content = content
	player.process_mode = Node.PROCESS_MODE_DISABLED
	manager.process_mode = Node.PROCESS_MODE_DISABLED
	spawner.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	add_child(manager)
	add_child(spawner)
	_spawn(spawner, generator, manager, player)
	_check(spawner.monsters.size() == 2, "unscoped_streaming_mode_still_generates")
	for actor: BaseMonster in spawner.monsters:
		_check(WorldGenerator.world_to_tile(actor.global_position).x >= 16, "old_candidates_all_belong_to_neighbor")
	_spawn(spawner, generator, manager, player, current)
	_check(spawner.monsters.size() == 2, "current_map_gets_both_slots_despite_neighbor_candidates")
	for actor: BaseMonster in spawner.monsters:
		_check(WorldGenerator.world_to_tile(actor.global_position).x < 16, "current_map_never_instantiates_neighbor_actors")
	if spawner.monsters.size() != 2:
		get_tree().quit(1)
		return
	var killed_tile: Vector2i = WorldGenerator.world_to_tile(spawner.monsters[0].global_position)
	spawner.monsters[0].kill()
	_spawn(spawner, generator, manager, player, neighbor)
	_check(spawner.monsters.size() == 2, "neighbor_keeps_its_own_deterministic_slots")
	_spawn(spawner, generator, manager, player, current)
	_check(spawner.monsters.size() == 1, "scoped_return_keeps_killed_slot_empty")
	for actor: BaseMonster in spawner.monsters:
		_check(WorldGenerator.world_to_tile(actor.global_position) != killed_tile, "scoped_return_does_not_revive_dead_actor")
	content.entries[2] = [{"kind": MapContent.DECOR, "budget": 6}]
	_spawn(spawner, generator, manager, player, current)
	_check(spawner.monsters.is_empty(), "active_map_scope_does_not_bypass_safe_room_budget")
	spawner.queue_free()
	manager.queue_free()
	player.queue_free()
	await get_tree().process_frame
	print("MONSTER_ACTIVE_MAP_RESULT=", _passed)
	get_tree().quit(0 if _passed else 1)
