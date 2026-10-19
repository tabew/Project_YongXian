class_name MapRng
extends RefCounted

## 统一随机源：所有生成子系统都从主种子派生，互不干扰、可复现。
##
## 地图侧是**无状态派生**：每次都用 (主种子, 用途) 现算一个 RNG，不依赖调用顺序，
## 所以工作线程、分块生成和重复生成都得到同一结果。
## 需要连续序列的子系统（战斗判定等）使用命名共享流。
##
## 派生公式沿用旧实现，替换随机源不会改变既有地图。

## 命名流：每个流一个独立盐值，互不干扰。
enum Stream {
	MAP = 0,     ## 地形与区域布局
	ROOM = 1,    ## 房间图骨架与节奏模板
	ENEMY = 2,   ## 刷怪
	LOOT = 3,    ## 物品与奖励
	DECOR = 4,   ## 装饰
	COMBAT = 5,  ## 战斗判定（暴击等）
	EVENT = 6,   ## 地图事件
}

## 与旧实现完全一致的噪声盐值。
const NOISE_SALTS: Array[int] = [8191, 15731, 32749, 65537, 104729, 130363]
## 旧实现的区域布局盐值。
const LAYOUT_SALT: int = 7919
## 流之间再混一个盐，避免不同流抽到同一序列。
const STREAM_SALT: int = 0x51ED270B

var master_seed: int = 0


func _init(seed_value: int = 0) -> void:
	master_seed = seed_value if seed_value != 0 else MapRng.random_seed()


## 默认主种子：外部不传时随机取一个。
## 放在这里而不是 WorldGenerator，避免两个 class_name 互相引用。
static func random_seed() -> int:
	var generator := RandomNumberGenerator.new()
	generator.randomize()
	return generator.randi_range(1, 2147483646)


# ------------------------------------------------------------ 无状态派生

## 与旧实现一致的噪声种子：主种子加固定盐。
func noise_seed(index: int) -> int:
	return master_seed + NOISE_SALTS[posmod(index, NOISE_SALTS.size())]


## 与旧实现一致的区域种子；MapSpec 也复用这一份。
static func node_seed(world_seed: int, map_node_id: int) -> int:
	var value: int = world_seed * 6364136223846793005 + 1442695040888963407
	value = (value ^ (map_node_id * 73856093)) * 6364136223846793005
	return value ^ (value >> 29)


## 单个区域的生成 RNG，与旧 MapSpec.create 完全相同。
static func node_rng(world_seed: int, map_node_id: int) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = node_seed(world_seed, map_node_id)
	return generator


## 区域布局的 RNG，与旧 WorldGenerator._build_layout 完全相同。
func layout_rng() -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = node_seed(master_seed, LAYOUT_SALT)
	return generator


## 任意用途的无状态 RNG：同一个 (主种子, 流, 盐) 永远得到同一序列。
func rng(stream_kind: int, salt: int = 0) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = stream_seed(stream_kind, salt)
	return generator


## 派生一个整数种子，供需要自行播种的调用方使用。
func stream_seed(stream_kind: int, salt: int = 0) -> int:
	return MapRng.mix(master_seed, stream_kind * 2654435761 + salt * 40503 + STREAM_SALT)


## 区块刷怪沿用旧种子公式，保证同一世界同一区块的怪物位置不变。
static func enemy_chunk_rng(world_seed: int, coords: Vector2i, monster_id: StringName) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = hash([world_seed, coords.x, coords.y, monster_id])
	return generator


## 把两个整数混成一个稳定种子。
static func mix(a: int, b: int) -> int:
	var value: int = (a ^ (b * 0x9E3779B1)) * 6364136223846793005 + 1442695040888963407
	return value ^ (value >> 29)


# ------------------------------------------------------------ 命名共享流

## 供拿不到生成器引用的子系统（战斗等）使用；开新世界时用主种子重置。
static var _shared_master: int = 0
static var _shared: Dictionary = {}


static func set_shared_master(seed_value: int) -> void:
	_shared_master = seed_value
	_shared.clear()


static func shared(stream_kind: int) -> RandomNumberGenerator:
	if not _shared.has(stream_kind):
		var generator := RandomNumberGenerator.new()
		generator.seed = MapRng.mix(_shared_master, stream_kind * 2654435761 + STREAM_SALT)
		_shared[stream_kind] = generator
	return _shared[stream_kind]
