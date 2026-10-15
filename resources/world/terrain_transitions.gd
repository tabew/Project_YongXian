class_name TerrainTransitions
extends RefCounted

## 只改变铺图，不改群系、地形碰撞或道路数据。跨区块查询使用一格 halo。
const SOURCE_ID: int = 2
const KIND_COUNT: int = 19
const MASK_COUNT: int = 24
const IGNORE: int = 255
const NO_BLEND: Vector2i = Vector2i(-1, -1)
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const CORNERS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
const TEXTURE: Texture2D = preload("res://assets/terrain_transitions.png")


static func install(tile_set: TileSet) -> void:
	if tile_set.has_source(SOURCE_ID):
		return
	var source := TileSetAtlasSource.new()
	source.texture = TEXTURE
	source.texture_region_size = Vector2i.ONE * WorldGenerator.TILE_SIZE
	for row: int in KIND_COUNT * KIND_COUNT:
		for mask: int in MASK_COUNT:
			source.create_tile(Vector2i(mask, row))
	tile_set.add_source(source, SOURCE_ID)


static func display_kind(terrain: int, route: int) -> int:
	return terrain if route == Route.Kind.NONE else Terrain.COUNT + Route.atlas_row(route)


static func halo(generator: WorldGenerator, data: ChunkData, _spec: MapSpec) -> PackedByteArray:
	var side: int = WorldGenerator.CHUNK_SIZE + 2
	var result := PackedByteArray()
	result.resize(side * side)
	result.fill(IGNORE)
	var origin: Vector2i = data.coords * WorldGenerator.CHUNK_SIZE
	for y: int in range(-1, WorldGenerator.CHUNK_SIZE + 1):
		for x: int in range(-1, WorldGenerator.CHUNK_SIZE + 1):
			var tile: Vector2i = origin + Vector2i(x, y)
			var neighbor: MapSpec = generator.sample_map(tile)
			if neighbor == null:
				continue
			var local: Vector2i = tile - neighbor.origin
			if neighbor.cottage != null and neighbor.cottage.bounds.has_point(local):
				continue
			var kind: int
			if x >= 0 and y >= 0 and x < WorldGenerator.CHUNK_SIZE and y < WorldGenerator.CHUNK_SIZE:
				var index: int = y * WorldGenerator.CHUNK_SIZE + x
				kind = display_kind(data.terrain[index], data.route[index])
			else:
				generator._classify(tile.x, tile.y)
				kind = display_kind(generator._last_terrain, generator._last_route)
			result[(y + 1) * side + x + 1] = kind
	return result


static func edge_at(samples: PackedByteArray, cell: Vector2i) -> Vector2i:
	var side: int = WorldGenerator.CHUNK_SIZE + 2
	var index: int = (cell.y + 1) * side + cell.x + 1
	var base: int = samples[index]
	# 桥和木屋保持明确结构轮廓。
	if base == IGNORE or base == Terrain.COUNT + Route.atlas_row(Route.Kind.BRIDGE):
		return NO_BLEND
	var other: int = -1
	var best_count: int = 0
	var adjacent: PackedInt32Array = PackedInt32Array([samples[index - side], samples[index + 1], samples[index + side], samples[index - 1]])
	for candidate: int in adjacent:
		if candidate == base or candidate == IGNORE or candidate == 18:
			continue
		var count: int = adjacent.count(candidate)
		if count > best_count:
			other = candidate
			best_count = count
	var mask: int = 0
	if other >= 0:
		for direction: int in 4:
			if adjacent[direction] == other:
				mask |= 1 << direction
	else:
		# 对角接触也补圆角，避免草地与路面仍留下硬直角。
		for corner: int in 4:
			var offset: Vector2i = CORNERS[corner]
			var candidate: int = samples[index + offset.y * side + offset.x]
			if candidate != base and candidate != IGNORE and candidate != 18:
				other = candidate
				mask = 16 + corner
				break
	return Vector2i(mask, base * KIND_COUNT + other) if other >= 0 else NO_BLEND


## 地图贴边处缓慢混入邻图围合地貌；只动图集，不改碰撞与区域归属。
static func seam_at(generator: WorldGenerator, spec: MapSpec, tile: Vector2i, base: int) -> Vector2i:
	if base != RegionBiomes.boundary_for(spec.biome_id):
		return NO_BLEND
	var local: Vector2i = tile - spec.origin
	var neighbor_tile: Vector2i = tile
	var distance: int = 9
	if local.x < 8:
		neighbor_tile = Vector2i(spec.origin.x - 1, tile.y)
		distance = local.x
	if spec.extent.x - 1 - local.x < distance:
		neighbor_tile = Vector2i(spec.origin.x + spec.extent.x, tile.y)
		distance = spec.extent.x - 1 - local.x
	if local.y < distance:
		neighbor_tile = Vector2i(tile.x, spec.origin.y - 1)
		distance = local.y
	if spec.extent.y - 1 - local.y < distance:
		neighbor_tile = Vector2i(tile.x, spec.origin.y + spec.extent.y)
		distance = spec.extent.y - 1 - local.y
	if distance > 7:
		return NO_BLEND
	var other_spec: MapSpec = generator.sample_map(neighbor_tile)
	if other_spec == null or other_spec == spec:
		return NO_BLEND
	var other: int = RegionBiomes.boundary_for(other_spec.biome_id)
	if other == base:
		return NO_BLEND
	var wobble: float = generator._edges.get_noise_2d(float(tile.x), float(tile.y)) * 1.5
	var strength: float = clampf((8.0 - float(distance) + wobble) / 8.0, 0.0, 1.0)
	if strength < 0.125:
		return NO_BLEND
	return Vector2i(19 + clampi(roundi(strength * 4.0), 1, 4), base * KIND_COUNT + other)


## 出入口附近用目标区域的地面色渐变；两端在边界混合各半，群系身份保持不变。
static func gate_at(generator: WorldGenerator, spec: MapSpec, tile: Vector2i, base: int) -> Vector2i:
	if base >= Terrain.COUNT or base != RegionBiomes.ground_for(spec.biome_id):
		return NO_BLEND
	var local: Vector2i = tile - spec.origin
	var strongest: float = 0.0
	var other: int = -1
	for link: Dictionary in generator.gate_links(spec.node_id):
		var target: MapSpec = generator.map_spec(int(link["target"]))
		var target_ground: int = RegionBiomes.ground_for(target.biome_id)
		if target_ground == base:
			continue
		var depth: float = float(local.x if int(link["side"]) < 0 else spec.extent.x - 1 - local.x)
		var across: float = absf(float(local.y - int(link["y"])))
		if depth > 12.0 or across > 16.0:
			continue
		var width: float = 10.0 + sin(float(local.y) * 0.25 + spec.phase_a) * 1.5
		var strength: float = clampf(1.0 - depth / width, 0.0, 1.0) * clampf(1.0 - maxf(across - 7.0, 0.0) / 9.0, 0.0, 1.0)
		if strength > strongest:
			strongest = strength
			other = target_ground
	if other < 0 or strongest < 0.125:
		return NO_BLEND
	var level: int = clampi(roundi(strongest * 4.0), 1, 4)
	return Vector2i(19 + level, base * KIND_COUNT + other)
