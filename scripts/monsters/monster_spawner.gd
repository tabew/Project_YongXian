class_name MonsterSpawner
extends Node2D

## 通用区块怪物生成器。
## 新怪物只需新增 MonsterSpawnData，无需修改本脚本。

@export var spawn_definitions: Array[MonsterSpawnData] = []
@export_range(0, 16, 1) var despawn_margin_chunks: int = 2
@export_group("密集区域性能")
@export_range(1, 16, 1) var spawns_per_frame: int = 4
@export_range(8, 64, 1) var wake_distance_tiles: int = 24
@export_range(8, 96, 1) var sleep_distance_tiles: int = 36
const ACTIVITY_SCAN_INTERVAL: float = 0.25

## 当前仍有效的全部怪物；怪物退出场景树时自动移除引用。
var monsters: Array[BaseMonster] = []

## 内容层：房间类型决定内容池。为空时保持旧的按群系刷新行为。
var content: MapContent = null

var _generator: WorldGenerator = null
var _chunk_manager: ChunkManager = null
var _player: PlayerCharacter = null
## 正式箱庭只为当前地图消耗生成名额；空值保留通用流式世界行为。
var _active_map: MapSpec = null
var _gate_encounter_anchors: Array[Vector2i] = []
var _monsters_by_chunk: Dictionary = {}
## 本局死亡记录按原始生成位置保存，巡逻/追击后的位置不影响身份。
var _defeated_spawn_ids: Dictionary = {}
var _pending_spawns: Array[Dictionary] = []
var _sleeping_monsters: Dictionary = {}
var _activity_scan_remaining: float = 0.0
var _defer_non_gate_spawns: bool = false
var difficulty_entry: int = 1


func setup(
	generator: WorldGenerator,
	chunk_manager: ChunkManager,
	player: PlayerCharacter,
	active_map: MapSpec = null,
	combat_entry: int = 1,
	defer_during_transition: bool = false
) -> void:
	# 同一生成器代表同一局；切换箱庭保留记录，新开世界（包括相同种子）重置。
	if generator != _generator:
		_defeated_spawn_ids.clear()
	clear_monsters()
	_generator = generator
	_player = player
	_active_map = active_map
	difficulty_entry = maxi(combat_entry, 1)
	_defer_non_gate_spawns = _active_map != null and is_processing() and (can_process() or defer_during_transition)
	_activity_scan_remaining = 0.0
	_gate_encounter_anchors.clear()
	if _active_map != null:
		_gate_encounter_anchors.append(WorldGenerator.world_to_tile(_generator.entry_position(_active_map.node_id, -1, _active_map.west_gate_y)) + Vector2i(10, 0))
		for gate_y: int in _active_map.east_gates:
			_gate_encounter_anchors.append(WorldGenerator.world_to_tile(_generator.entry_position(_active_map.node_id, 1, gate_y)) + Vector2i(-10, 0))
	if _chunk_manager != null and _chunk_manager.chunk_applied.is_connected(_on_chunk_applied):
		_chunk_manager.chunk_applied.disconnect(_on_chunk_applied)
	_chunk_manager = chunk_manager
	if not _chunk_manager.chunk_applied.is_connected(_on_chunk_applied):
		_chunk_manager.chunk_applied.connect(_on_chunk_applied)

	for coords: Vector2i in _chunk_manager.loaded_chunks():
		_on_chunk_applied(coords)


func _process(delta: float) -> void:
	if _chunk_manager == null or not is_instance_valid(_player):
		return
	if _active_map != null:
		for index: int in mini(spawns_per_frame, _pending_spawns.size()):
			var planned: Dictionary = _pending_spawns.pop_front()
			var coords: Vector2i = planned["chunk"]
			if _monsters_by_chunk.has(coords):
				spawn_monster(planned["definition"], planned["tile"], coords)
		_activity_scan_remaining -= delta
		if _activity_scan_remaining <= 0.0:
			_activity_scan_remaining = ACTIVITY_SCAN_INTERVAL
			for monster: BaseMonster in monsters:
				_update_monster_activity(monster)
		return
	var player_chunk: Vector2i = WorldGenerator.tile_to_chunk(
		WorldGenerator.world_to_tile(_player.global_position)
	)
	var limit: int = _chunk_manager.unload_radius + despawn_margin_chunks
	for coords: Vector2i in _monsters_by_chunk.keys():
		var distance: Vector2i = (coords - player_chunk).abs()
		if maxi(distance.x, distance.y) > limit:
			_remove_chunk_monsters(coords)


func _update_monster_activity(monster: BaseMonster) -> void:
	if not is_instance_valid(monster) or monster.is_queued_for_deletion() or not monster.visible:
		return
	var distance_squared: float = monster.global_position.distance_squared_to(_player.global_position)
	var wake_pixels: float = float(wake_distance_tiles * WorldGenerator.TILE_SIZE)
	var sleep_pixels: float = float(maxi(sleep_distance_tiles, wake_distance_tiles + 1) * WorldGenerator.TILE_SIZE)
	var suspicious: bool = monster.blackboard != null and monster.blackboard.has_suspicious_event
	if _sleeping_monsters.has(monster):
		if distance_squared <= wake_pixels * wake_pixels or suspicious:
			_wake_monster(monster)
		return
	if monster.process_mode != Node.PROCESS_MODE_INHERIT or distance_squared < sleep_pixels * sleep_pixels:
		return
	if monster.get_ai_state() != EnemyState.State.PATROL or monster.is_receiving_knockback() or monster.is_distance_sleep_blocked() or suspicious:
		return
	if monster.attack != null and monster.attack.is_busy():
		return
	if monster.navigator != null:
		monster.navigator.clear()
	monster.velocity = Vector2.ZERO
	monster.process_mode = Node.PROCESS_MODE_DISABLED
	_sleeping_monsters[monster] = true


func _wake_monster(monster: BaseMonster) -> void:
	if not _sleeping_monsters.erase(monster) or not is_instance_valid(monster):
		return
	monster.process_mode = Node.PROCESS_MODE_INHERIT


func _on_monster_health_changed(_current: float, _maximum: float, monster: BaseMonster) -> void:
	_wake_monster(monster)


func wake_for_suspicious_event(monster: BaseMonster) -> void:
	_wake_monster(monster)


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
	if _spawn_gate_encounter(definition, coords, occupied):
		return
	var rng: RandomNumberGenerator = MapRng.enemy_chunk_rng(
		_generator.world_seed, coords, definition.monster_id
	)
	if rng.randf() > definition.chunk_spawn_chance:
		return

	if definition.independent_spawn_slots:
		_spawn_independent_slots(definition, coords, occupied)
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
		if not _place_non_gate_monster(definition, tile, coords):
			continue
		occupied[tile] = true
		spawned += 1


func _place_non_gate_monster(definition: MonsterSpawnData, tile: Vector2i, coords: Vector2i) -> bool:
	if _defer_non_gate_spawns:
		_pending_spawns.append({"definition": definition, "tile": tile, "chunk": coords})
		return true
	return spawn_monster(definition, tile, coords) != null


## 入口内侧10格、道路附近的确定遭遇点，使用原生成身份且占用区块名额。
func _spawn_gate_encounter(definition: MonsterSpawnData, coords: Vector2i, occupied: Dictionary) -> bool:
	if _active_map == null or definition.gate_encounter_count <= 0:
		return false
	if not definition.allowed_biomes.is_empty() and not definition.allowed_biomes.has(_active_map.biome_id):
		return false
	if content != null and content.budget_of(_active_map.node_id, MapContent.ENEMY) <= 0:
		return false
	var handled: bool = false
	var used: int = 0
	for anchor: Vector2i in _gate_encounter_anchors:
		if WorldGenerator.tile_to_chunk(anchor) != coords:
			continue
		handled = true
		var placed: int = 0
		for radius: int in range(1, 7):
			for y: int in range(-radius, radius + 1):
				for x: int in range(-radius, radius + 1):
					if placed >= definition.gate_encounter_count or used >= definition.max_per_chunk:
						break
					var tile: Vector2i = anchor + Vector2i(x, y)
					if occupied.has(tile) or WorldGenerator.tile_to_chunk(tile) != coords:
						continue
					if not allows_spawn_at(tile) or not definition.can_spawn_at(_generator, tile):
						continue
					occupied[tile] = true
					used += 1
					placed += 1
					if not _defeated_spawn_ids.has(_spawn_id(definition, tile)):
						spawn_monster(definition, tile, coords)
				if placed >= definition.gate_encounter_count or used >= definition.max_per_chunk:
					break
			if placed >= definition.gate_encounter_count or used >= definition.max_per_chunk:
				break
	return handled


func _spawn_independent_slots(definition: MonsterSpawnData, coords: Vector2i, occupied: Dictionary) -> void:
	for slot: int in definition.max_per_chunk:
		var slot_id := StringName("%s:slot:%d" % [definition.monster_id, slot])
		var source: RandomNumberGenerator = MapRng.enemy_chunk_rng(_generator.world_seed, coords, slot_id)
		# 一个原始名额只掷一次栖地概率；找不到该栖地不能改刷另一类。
		var variant: int = definition.choose_spawn_variant(source)
		for attempt: int in definition.candidate_attempts:
			var tile: Vector2i = definition.select_spawn_tile(_generator, coords, source, variant, _active_map)
			if tile == EnemyPathfinder.INVALID_TILE:
				break
			if occupied.has(tile) or not allows_spawn_at(tile) or not definition.can_spawn_variant_at(_generator, tile, variant):
				continue
			occupied[tile] = true
			if not _defeated_spawn_ids.has(_spawn_id(definition, tile)):
				_place_non_gate_monster(definition, tile, coords)
			# 死亡的原始格也消耗本名额，切图后不会重新选择替代怪物。
			break


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
	var health := monster.get_node_or_null("Health") as HealthComponent
	if health != null:
		health.health_changed.connect(_on_monster_health_changed.bind(monster))

	monster.configure(_player, _generator, chunk_coords)
	monster.apply_difficulty(difficulty_entry)
	if _defer_non_gate_spawns:
		_update_monster_activity(monster)
	return monster


## 使用原始生成格和怪物类型，不使用会随着移动改变的当前位置。
func _spawn_id(definition: MonsterSpawnData, tile: Vector2i) -> String:
	return "%s:%d:%d" % [definition.monster_id, tile.x, tile.y]


func _on_monster_killed(spawn_id: String) -> void:
	_defeated_spawn_ids[spawn_id] = true


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
	_pending_spawns.clear()
	_sleeping_monsters.clear()
	for monster: BaseMonster in monsters.duplicate():
		if is_instance_valid(monster):
			if monster.get_parent() == self:
				remove_child(monster)
			monster.queue_free()
	monsters.clear()
	_monsters_by_chunk.clear()


func get_spawned_monster_count() -> int:
	return monsters.size()


func get_pending_spawn_count() -> int:
	return _pending_spawns.size()


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
	_sleeping_monsters.erase(monster)
	monsters.erase(monster)
	if not _monsters_by_chunk.has(chunk_coords):
		return
	var chunk_monsters: Array = _monsters_by_chunk[chunk_coords]
	chunk_monsters.erase(monster)
	if chunk_monsters.is_empty() and _active_map == null:
		_monsters_by_chunk.erase(chunk_coords)
