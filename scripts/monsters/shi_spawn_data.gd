class_name ShiSpawnData
extends MonsterSpawnData

## 每区块一个紧凑史莱姆群，各原始名额保持独立且确定，死亡不补刷。
var _cached_generator: WorldGenerator = null
var _anchors: Dictionary = {}

func select_spawn_tile(generator: WorldGenerator, coords: Vector2i, rng: RandomNumberGenerator, _variant: int, active_map: MapSpec = null) -> Vector2i:
	if active_map != null and not allowed_biomes.has(active_map.biome_id):
		return EnemyPathfinder.INVALID_TILE
	if generator != _cached_generator:
		_cached_generator = generator
		_anchors.clear()
	var scope: int = active_map.node_id if active_map != null else -1
	var key: String = "%d:%d:%d" % [scope, coords.x, coords.y]
	if not _anchors.has(key):
		_anchors[key] = _find_anchor(generator, coords, active_map)
	var anchor: Vector2i = _anchors[key]
	if anchor == EnemyPathfinder.INVALID_TILE:
		return anchor
	return anchor + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))

func _find_anchor(generator: WorldGenerator, coords: Vector2i, active_map: MapSpec) -> Vector2i:
	var pack: RandomNumberGenerator = MapRng.enemy_chunk_rng(generator.world_seed, coords, &"shi:pack")
	var origin: Vector2i = coords * WorldGenerator.CHUNK_SIZE
	for attempt: int in 128:
		var candidate := origin + Vector2i(pack.randi_range(2, 29), pack.randi_range(2, 29))
		if not can_spawn_at(generator, candidate):
			continue
		if active_map != null:
			var local: Vector2i = candidate - active_map.origin
			if not active_map.contains_local(local.x, local.y):
				continue
		return candidate
	return EnemyPathfinder.INVALID_TILE
