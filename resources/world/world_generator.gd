class_name WorldGenerator
extends RefCounted

## 无限世界的区块生成器。
##
## 关键性质：地形只由 (世界种子, 格子坐标) 决定，**与区块无关**，
## 所以区块之间不会出现接缝，也不需要在生成时读取邻居区块。
##
## 每个实例各自持有一套噪声对象，因此可以给不同线程各分配一个实例并发调用。

const CHUNK_SIZE: int = 32
const TILE_SIZE: int = 16

## 大陆噪声（0..1）的阈值
const DEEP_LEVEL: float = 0.27
const SEA_LEVEL: float = 0.38

## 陆地内部按海拔再分层
const BEACH_LEVEL: float = 0.05
const MOUNTAIN_LEVEL: float = 0.56
const ALPINE_LEVEL: float = 0.76

## 对比度增益：把噪声往两端拉，否则单纯形噪声几乎都在 0.5 附近，
## 沙漠 / 雨林 / 雪峰这类需要极端温湿度的群系会永远出不来。
const CONTINENT_CONTRAST: float = 1.20
const CLIMATE_CONTRAST: float = 1.90

## 海拔每升高 1.0 带来的降温，让高山自然变冷
const ALTITUDE_COOLING: float = 0.34

## 路网宽度阈值，作用在 abs(噪声) 上：越小路越窄。
## 低频主路噪声变化慢，同样的阈值得到更宽的路面。
const MAIN_ROAD_WIDTH: float = 0.0125
const BRANCH_ROAD_WIDTH: float = 0.0220

## 出生点要求周围 SPAWN_CHECK_RADIUS 格范围内至少这么多比例可通行
const SPAWN_CHECK_RADIUS: int = 3
const SPAWN_OPEN_RATIO: float = 0.72

const SPAWN_NOT_FOUND: Vector2i = Vector2i(2147483647, 2147483647)

var world_seed: int = 0

var _continent := FastNoiseLite.new()
var _temperature := FastNoiseLite.new()
var _humidity := FastNoiseLite.new()
var _variation := FastNoiseLite.new()
var _main_route := FastNoiseLite.new()
var _branch_route := FastNoiseLite.new()

# _classify 的输出缓冲，避免为每个格子分配对象
var _last_terrain: int = Terrain.Kind.WATER
var _last_biome: int = Biome.Kind.OCEAN
var _last_route: int = Route.Kind.NONE


func _init(seed_value: int = 0) -> void:
	world_seed = seed_value if seed_value != 0 else random_seed()
	_configure_noise()


func _configure_noise() -> void:
	_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent.seed = world_seed
	_continent.frequency = 0.006
	_continent.fractal_octaves = 4
	_continent.fractal_gain = 0.5
	_continent.fractal_lacunarity = 2.0
	# 用引擎内置的域扭曲打散海岸线，比手写两层扭曲噪声少两次采样
	_continent.domain_warp_enabled = true
	_continent.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_continent.domain_warp_amplitude = 26.0
	_continent.domain_warp_frequency = 0.012

	_temperature.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_temperature.seed = world_seed + 8191
	_temperature.frequency = 0.0035
	_temperature.fractal_octaves = 2

	_humidity.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_humidity.seed = world_seed + 15731
	_humidity.frequency = 0.0042
	_humidity.fractal_octaves = 2

	_variation.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_variation.seed = world_seed + 32749
	_variation.frequency = 0.085
	_variation.fractal_octaves = 1

	# 主路：低频 + 域扭曲 -> 大尺度蜿蜒的主干道，路面宽
	_main_route.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_main_route.seed = world_seed + 49157
	_main_route.frequency = 0.0022
	_main_route.fractal_octaves = 2
	_main_route.domain_warp_enabled = true
	_main_route.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_main_route.domain_warp_amplitude = 40.0
	_main_route.domain_warp_frequency = 0.006

	# 支线：频率高一些 -> 短而密的岔路，路面窄
	_branch_route.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_branch_route.seed = world_seed + 65537
	_branch_route.frequency = 0.0075
	_branch_route.fractal_octaves = 2


static func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 2147483646)


# ------------------------------------------------------------ 坐标换算
# 全部用 floor，保证世界延伸到负数坐标时区块与格子依然对齐

static func world_to_tile(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(TILE_SIZE)),
		floori(world_position.y / float(TILE_SIZE))
	)


static func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(
		(float(tile.x) + 0.5) * TILE_SIZE,
		(float(tile.y) + 0.5) * TILE_SIZE
	)


static func tile_to_chunk(tile: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile.x) / float(CHUNK_SIZE)),
		floori(float(tile.y) / float(CHUNK_SIZE))
	)


# ------------------------------------------------------------ 生成

## 生成一个区块的全部地形。可以在工作线程里调用。
func generate_chunk(chunk_coords: Vector2i, epoch: int = 0) -> ChunkData:
	var data := ChunkData.create(chunk_coords, CHUNK_SIZE)
	data.epoch = epoch

	var origin_x: int = chunk_coords.x * CHUNK_SIZE
	var origin_y: int = chunk_coords.y * CHUNK_SIZE

	var index: int = 0
	for local_y: int in CHUNK_SIZE:
		for local_x: int in CHUNK_SIZE:
			_classify(origin_x + local_x, origin_y + local_y)
			data.terrain[index] = _last_terrain
			data.biome[index] = _last_biome
			data.route[index] = _last_route
			index += 1

	data.last_used = Time.get_ticks_msec()
	return data


## 只要一个格子的地形，供玩家碰撞等即时查询使用。
func sample_terrain(tile: Vector2i) -> int:
	_classify(tile.x, tile.y)
	return _last_terrain


func sample_biome(tile: Vector2i) -> int:
	_classify(tile.x, tile.y)
	return _last_biome


func sample_route(tile: Vector2i) -> int:
	_classify(tile.x, tile.y)
	return _last_route


## 玩家能否站上这一格：地形本身可通行，或者这里是路。
## 路一定可通行——主干道会架桥过水、开山道过山，保证顺得下去。
func is_walkable(tile: Vector2i) -> bool:
	_classify(tile.x, tile.y)
	return Terrain.is_walkable(_last_terrain) or _last_route != Route.Kind.NONE


## 单个格子的完整判定：一次算完地形、群系与路网，写入成员变量。
func _classify(tile_x: int, tile_y: int) -> void:
	var fx: float = float(tile_x)
	var fy: float = float(tile_y)

	_last_terrain = _classify_terrain(fx, fy)

	var road: int = _classify_route(fx, fy)
	# 路跨过水面时画成桥
	if road != Route.Kind.NONE and Terrain.is_water(_last_terrain):
		road = Route.Kind.BRIDGE
	_last_route = road


## 地形与群系：完全沿用原来的算法，路网不影响它。
func _classify_terrain(fx: float, fy: float) -> int:
	var continent: float = _sharpen(
		(_continent.get_noise_2d(fx, fy) + 1.0) * 0.5, CONTINENT_CONTRAST
	)

	if continent < DEEP_LEVEL:
		_last_biome = Biome.Kind.DEEP_OCEAN
		return Terrain.Kind.DEEP_WATER

	var temperature: float = _sharpen(
		(_temperature.get_noise_2d(fx, fy) + 1.0) * 0.5, CLIMATE_CONTRAST
	)

	if continent < SEA_LEVEL:
		_last_biome = Biome.Kind.OCEAN
		return Terrain.Kind.ICE if temperature < 0.20 else Terrain.Kind.WATER

	var altitude: float = (continent - SEA_LEVEL) / (1.0 - SEA_LEVEL)
	var humidity: float = _sharpen(
		(_humidity.get_noise_2d(fx, fy) + 1.0) * 0.5, CLIMATE_CONTRAST
	)
	# 高处更冷，于是山脉自然过渡到雪原 / 雪峰
	temperature = clampf(temperature - altitude * ALTITUDE_COOLING, 0.0, 1.0)

	var biome: int = _pick_biome(altitude, temperature, humidity)
	_last_biome = biome

	var variation: float = (_variation.get_noise_2d(fx, fy) + 1.0) * 0.5
	return _pick_terrain(biome, variation, temperature)


## 路网判定：abs(噪声) 越小越靠近零等值线，那里就是路面。
func _classify_route(fx: float, fy: float) -> int:
	if absf(_main_route.get_noise_2d(fx, fy)) < MAIN_ROAD_WIDTH:
		return Route.Kind.STONE
	if absf(_branch_route.get_noise_2d(fx, fy)) < BRANCH_ROAD_WIDTH:
		return Route.Kind.DIRT
	return Route.Kind.NONE


## 以 0.5 为中心做对比度拉伸，gain > 1 会把值推向两端。
static func _sharpen(value: float, gain: float) -> float:
	return clampf((value - 0.5) * gain + 0.5, 0.0, 1.0)


static func _pick_biome(altitude: float, temperature: float, humidity: float) -> int:
	if altitude > ALPINE_LEVEL:
		return Biome.Kind.ALPINE
	if altitude > MOUNTAIN_LEVEL:
		return Biome.Kind.MOUNTAIN
	if altitude < BEACH_LEVEL:
		return Biome.Kind.BEACH

	if temperature < 0.18:
		return Biome.Kind.SNOWY_PLAINS
	if temperature < 0.34:
		return Biome.Kind.TUNDRA if humidity < 0.45 else Biome.Kind.TAIGA
	if temperature < 0.54:
		if humidity < 0.35:
			return Biome.Kind.GRASSLAND
		return Biome.Kind.FOREST if humidity < 0.76 else Biome.Kind.SWAMP
	if temperature < 0.70:
		if humidity < 0.30:
			return Biome.Kind.SAVANNA
		if humidity < 0.55:
			return Biome.Kind.GRASSLAND
		return Biome.Kind.FOREST if humidity < 0.86 else Biome.Kind.SWAMP
	if humidity < 0.42:
		return Biome.Kind.DESERT
	return Biome.Kind.SAVANNA if humidity < 0.62 else Biome.Kind.TROPICAL_RAINFOREST


static func _pick_terrain(biome: int, variation: float, temperature: float) -> int:
	if biome == Biome.Kind.OCEAN:
		if temperature < 0.22 and variation >= Biome.SPLIT_A:
			return Terrain.Kind.ICE
		return Terrain.Kind.WATER

	if variation >= Biome.SPLIT_B:
		return Biome.TERTIARY[biome]
	if variation >= Biome.SPLIT_A:
		return Biome.SECONDARY[biome]
	return Biome.PRIMARY[biome]


# ------------------------------------------------------------ 出生点

## 从 origin 向外一圈圈找落脚点。
## 先找"开阔且在路上的"，这样一开局就站在主路上；找不到再放宽为只要开阔。
func find_spawn(origin: Vector2i = Vector2i.ZERO, max_radius: int = 320) -> Vector2i:
	var on_road: Vector2i = _search_spawn(origin, max_radius, true)
	if on_road != SPAWN_NOT_FOUND:
		return on_road

	var anywhere: Vector2i = _search_spawn(origin, max_radius, false)
	if anywhere != SPAWN_NOT_FOUND:
		return anywhere

	return origin


func _search_spawn(origin: Vector2i, max_radius: int, require_road: bool) -> Vector2i:
	if is_open_area(origin, require_road):
		return origin

	var radius: int = 6
	while radius <= max_radius:
		var steps: int = maxi(8, radius / 4)
		for step: int in steps:
			var angle: float = TAU * float(step) / float(steps)
			var candidate := Vector2i(
				origin.x + int(roundf(cos(angle) * float(radius))),
				origin.y + int(roundf(sin(angle) * float(radius)))
			)
			if is_open_area(candidate, require_road):
				return candidate
		radius += 6

	return SPAWN_NOT_FOUND


## 先看中心一格（便宜），再统计周围一圈的可通行比例。路也算可通行。
func is_open_area(tile: Vector2i, require_road: bool = false) -> bool:
	_classify(tile.x, tile.y)
	if not Terrain.is_walkable(_last_terrain) and _last_route == Route.Kind.NONE:
		return false
	if require_road and _last_route == Route.Kind.NONE:
		return false

	var walkable: int = 0
	var total: int = 0
	for dy: int in range(-SPAWN_CHECK_RADIUS, SPAWN_CHECK_RADIUS + 1):
		for dx: int in range(-SPAWN_CHECK_RADIUS, SPAWN_CHECK_RADIUS + 1):
			total += 1
			_classify(tile.x + dx, tile.y + dy)
			if Terrain.is_walkable(_last_terrain) or _last_route != Route.Kind.NONE:
				walkable += 1

	return float(walkable) / float(total) >= SPAWN_OPEN_RATIO
