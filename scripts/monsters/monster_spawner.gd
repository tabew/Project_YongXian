class_name MonsterSpawner
extends Node2D

## 通用区块怪物生成器。
## 新怪物只需新增 MonsterSpawnData，无需修改本脚本。

@export var spawn_definitions: Array[MonsterSpawnData] = []
@export_range(0, 16, 1) var despawn_margin_chunks: int = 2

## 怪物被真正击杀（不是切图回收）：携带怪物节点与它的灵感来源档位。
## 只做广播，不决定掉落数量；灵感账本由局内世界层负责。
signal monster_killed(monster: BaseMonster, inspiration_source: int)

## 当前仍有效的全部怪物；怪物退出场景树时自动移除引用。
var monsters: Array[BaseMonster] = []

## 内容层：房间类型决定内容池。为空时保持旧的按群系刷新行为。
var content: MapContent = null

var _generator: WorldGenerator = null
var _chunk_manager: ChunkManager = null
var _player: PlayerCharacter = null
## 正式箱庭只为当前地图消耗生成名额；空值保留通用流式世界行为。
var _active_map: MapSpec = null
var _monsters_by_chunk: Dictionary = {}
## 本局死亡记录按原始生成位置保存，巡逻/追击后的位置不影响身份。
var _defeated_spawn_ids: Dictionary = {}


func setup(
	generator: WorldGenerator,
	chunk_manager: ChunkManager,
	player: PlayerCharacter,
	active_map: MapSpec = null
) -> void:
	# 同一生成器代表同一局；切换箱庭保留记录，新开世界（包括相同种子）重置。
	if generator != _generator:
		_defeated_spawn_ids.clear()
	clear_monsters()
	_generator = generator
	_player = player
	_active_map = active_map
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
	var limit: int = _chunk_manager.unload_radius + despawn_margin_chunks
	for coords: Vector2i in _monsters_by_chunk.keys():
		var distance: Vector2i = (coords - player_chunk).abs()
		if maxi(distance.x, distance.y) > limit:
			_remove_chunk_monsters(coords)


func _on_chunk_applied(coords: Vector2i) -> void:
	if _generator == null or _monsters_by_chunk.has(coords):
		return
	var chunk_monsters: Array[BaseMonster] = []
	_monsters_by_chunk[coords] = chunk_monsters
	var occupied: Dictionary = {}

	for definition: MonsterSpawnData in spawn_definitions:
		_spawn_definition_in_chunk(definition, coords, occupied)


func _spawn_definition_in_chunk(
	definition: MonsterSpawnData,
	coords: Vector2i,
	occupied: Dictionary
) -> void:
	if definition == null or definition.monster_scene == null:
		return
	var rng: RandomNumberGenerator = MapRng.enemy_chunk_rng(
		_generator.world_seed, coords, definition.monster_id
	)
	if rng.randf() > definition.chunk_spawn_chance:
		return

	var origin: Vector2i = coords * WorldGenerator.CHUNK_SIZE
	var spawned: int = 0
	for _attempt: int in definition.candidate_attempts:
		if spawned >= definition.max_per_chunk:
			break
		var tile := origin + Vector2i(
			rng.randi_range(0, WorldGenerator.CHUNK_SIZE - 1),
			rng.randi_range(0, WorldGenerator.CHUNK_SIZE - 1)
		)
		if occupied.has(tile) or not definition.can_spawn_at(_generator, tile):
			continue
		if not allows_spawn_at(tile):
			continue
		if _defeated_spawn_ids.has(_spawn_id(definition, tile)):
			# 死怪仍占用原来的生成名额，不能继续掷随机数补刷一只替代怪物。
			occupied[tile] = true
			spawned += 1
			continue
		var monster: BaseMonster = spawn_monster(definition, tile, coords)
		if monster == null:
			continue
		occupied[tile] = true
		spawned += 1


func spawn_monster(
	definition: MonsterSpawnData,
	tile: Vector2i,
	chunk_coords: Vector2i = WorldGenerator.tile_to_chunk(tile)
) -> BaseMonster:
	if definition == null or definition.monster_scene == null:
		return null
	var spawn_id: String = _spawn_id(definition, tile)
	if _defeated_spawn_ids.has(spawn_id):
		return null
	var monster := definition.monster_scene.instantiate() as BaseMonster
	if monster == null:
		push_warning("Monster scene '%s' must inherit BaseMonster" % definition.monster_id)
		return null

	add_child(monster)
	monster.global_position = WorldGenerator.tile_to_world(tile)
	monsters.append(monster)
	if not _monsters_by_chunk.has(chunk_coords):
		var created: Array[BaseMonster] = []
		_monsters_by_chunk[chunk_coords] = created
	var chunk_monsters: Array[BaseMonster] = _monsters_by_chunk[chunk_coords]
	chunk_monsters.append(monster)
	monster.tree_exited.connect(_on_monster_exited.bind(monster, chunk_coords), CONNECT_ONE_SHOT)
	monster.killed.connect(_on_monster_killed.bind(spawn_id), CONNECT_ONE_SHOT)
	monster.killed.connect(_on_monster_killed_broadcast.bind(monster, definition.inspiration_source), CONNECT_ONE_SHOT)

	monster.configure(_player, _generator, chunk_coords)
	return monster


## 使用原始生成格和怪物类型，不使用会随着移动改变的当前位置。
func _spawn_id(definition: MonsterSpawnData, tile: Vector2i) -> String:
	return "%s:%d:%d" % [definition.monster_id, tile.x, tile.y]


func _on_monster_killed(spawn_id: String) -> void:
	_defeated_spawn_ids[spawn_id] = true


## 死亡时怪物还没被 queue_free 掉，位置仍是最终击杀点，可以直接拿来掉落。
func _on_monster_killed_broadcast(monster: BaseMonster, inspiration_source: int) -> void:
	if not is_instance_valid(monster):
		return
	monster_killed.emit(monster, inspiration_source)


## 该格所属区域是否有刷怪预算：只有战斗 / Boss 区域刷怪。
## 未接入内容层时一律允许，行为与改造前一致。
func allows_spawn_at(tile: Vector2i) -> bool:
	if _active_map != null:
		var local: Vector2i = tile - _active_map.origin
		if not _active_map.contains_local(local.x, local.y):
			return false
	if content == null or _generator == null:
		return true
	var spec: MapSpec = _generator.sample_map(tile)
	if spec == null:
		return false
	return content.budget_of(spec.node_id, MapContent.ENEMY) > 0


func clear_monsters() -> void:
	for monster: BaseMonster in monsters.duplicate():
		if is_instance_valid(monster):
			if monster.get_parent() == self:
				remove_child(monster)
			monster.queue_free()
	monsters.clear()
	_monsters_by_chunk.clear()


func get_spawned_monster_count() -> int:
	return monsters.size()


func _remove_chunk_monsters(coords: Vector2i) -> void:
	var chunk_monsters: Array = _monsters_by_chunk.get(coords, [])
	_monsters_by_chunk.erase(coords)
	for monster: BaseMonster in chunk_monsters:
		monsters.erase(monster)
		if is_instance_valid(monster):
			if monster.get_parent() == self:
				remove_child(monster)
			monster.queue_free()


func _on_monster_exited(monster: BaseMonster, chunk_coords: Vector2i) -> void:
	monsters.erase(monster)
	if not _monsters_by_chunk.has(chunk_coords):
		return
	var chunk_monsters: Array = _monsters_by_chunk[chunk_coords]
	chunk_monsters.erase(monster)
	if chunk_monsters.is_empty():
		_monsters_by_chunk.erase(chunk_coords)
