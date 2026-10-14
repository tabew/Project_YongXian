class_name CrocodileSpawnData
extends MonsterSpawnData

const WATER_VARIANT: int = 0
const BANK_VARIANT: int = 1
const BANK_RADIUS: int = 5
@export_range(0.0, 1.0, 0.01) var bank_spawn_chance: float = 0.10
var _cached_generator: WorldGenerator = null
var _pools: Dictionary = {}

static func is_swamp_water(generator: WorldGenerator, tile: Vector2i) -> bool:
	return generator != null and generator.sample_biome(tile) == Biome.Kind.SWAMP and Terrain.is_water(generator.sample_terrain(tile)) and generator.sample_route(tile) == Route.Kind.NONE

static func is_bank_ground(generator: WorldGenerator, tile: Vector2i) -> bool:
	if generator == null or generator.sample_biome(tile) != Biome.Kind.SWAMP or not generator.is_walkable(tile) or generator.sample_route(tile) != Route.Kind.NONE:
		return false
	return generator.sample_terrain(tile) in [Terrain.Kind.SWAMP, Terrain.Kind.SAND, Terrain.Kind.GRASS]

static func nearest_swamp_water(generator: WorldGenerator, tile: Vector2i, radius: int = BANK_RADIUS) -> Vector2i:
	var nearest: Vector2i = EnemyPathfinder.INVALID_TILE
	var best: int = radius * radius + 1
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			var distance: int = x * x + y * y
			if distance >= best:
				continue
			var candidate := tile + Vector2i(x, y)
			if is_swamp_water(generator, candidate):
				nearest = candidate
				best = distance
	return nearest

func can_spawn_at(generator: WorldGenerator, tile: Vector2i) -> bool:
	return is_swamp_water(generator, tile) or (is_bank_ground(generator, tile) and nearest_swamp_water(generator, tile) != EnemyPathfinder.INVALID_TILE)

func choose_spawn_variant(rng: RandomNumberGenerator) -> int:
	return BANK_VARIANT if rng.randf() < bank_spawn_chance else WATER_VARIANT

func can_spawn_variant_at(generator: WorldGenerator, tile: Vector2i, variant: int) -> bool:
	if variant == WATER_VARIANT:
		return is_swamp_water(generator, tile)
	return is_bank_ground(generator, tile) and nearest_swamp_water(generator, tile) != EnemyPathfinder.INVALID_TILE

func select_spawn_tile(generator: WorldGenerator, coords: Vector2i, rng: RandomNumberGenerator, variant: int, active_map: MapSpec = null) -> Vector2i:
	if generator != _cached_generator:
		_cached_generator = generator
		_pools.clear()
	if active_map != null and active_map.biome_id != Biome.Kind.SWAMP:
		return EnemyPathfinder.INVALID_TILE
	var scope: int = active_map.node_id if active_map != null else -1
	var key: String = "%d:%d:%d" % [scope, coords.x, coords.y]
	if not _pools.has(key):
		_pools[key] = _build_pools(generator, coords, active_map)
	var pool: Array = _pools[key][variant]
	return EnemyPathfinder.INVALID_TILE if pool.is_empty() else pool[rng.randi_range(0, pool.size() - 1)]

func _build_pools(generator: WorldGenerator, coords: Vector2i, active_map: MapSpec) -> Array:
	var water: Dictionary = {}
	var wet: Array[Vector2i] = []
	var dry: Array[Vector2i] = []
	var origin: Vector2i = coords * WorldGenerator.CHUNK_SIZE
	# 同图5格 halo 一次计算，避免每个地面候选重复查询81个水格。
	for y: int in range(-BANK_RADIUS, WorldGenerator.CHUNK_SIZE + BANK_RADIUS):
		for x: int in range(-BANK_RADIUS, WorldGenerator.CHUNK_SIZE + BANK_RADIUS):
			var tile := origin + Vector2i(x, y)
			if active_map != null:
				var local: Vector2i = tile - active_map.origin
				if not active_map.contains_local(local.x, local.y):
					continue
			if is_swamp_water(generator, tile):
				water[tile] = true
	for y: int in WorldGenerator.CHUNK_SIZE:
		for x: int in WorldGenerator.CHUNK_SIZE:
			var tile := origin + Vector2i(x, y)
			if active_map != null:
				var local: Vector2i = tile - active_map.origin
				if not active_map.contains_local(local.x, local.y):
					continue
			if water.has(tile):
				wet.append(tile)
			elif is_bank_ground(generator, tile):
				var near: bool = false
				for offset_y: int in range(-BANK_RADIUS, BANK_RADIUS + 1):
					for offset_x: int in range(-BANK_RADIUS, BANK_RADIUS + 1):
						if offset_x * offset_x + offset_y * offset_y <= BANK_RADIUS * BANK_RADIUS and water.has(tile + Vector2i(offset_x, offset_y)):
							near = true
							break
					if near:
						break
				if near:
					dry.append(tile)
	return [wet, dry]
