class_name MonsterSpawnData
extends Resource

## 单种怪物的生成配置；行为、血量和索敌规则仍由怪物脚本负责。

@export var monster_id: StringName
@export var monster_scene: PackedScene
@export var allowed_biomes: Array[int] = []
@export_range(0.0, 1.0, 0.01) var chunk_spawn_chance: float = 1.0
@export_range(1, 100, 1) var max_per_chunk: int = 1
@export_range(1, 256, 1) var candidate_attempts: int = 24
## 特殊栖地按独立原始名额抽样；普通怪物保留原区块随机序列。
@export var independent_spawn_slots: bool = false
## 战斗房间入口内侧的稳定遭遇组；占用该区块名额，避免怪物只在遥远房间内部。
@export_range(0, 6, 1) var gate_encounter_count: int = 0

@export_group("成长")
## 击杀基础经验；实际值按楼层缩放后由 RunProgress 结算，掉落经验球由生成器负责。
@export_range(0, 10000, 1) var experience_reward: int = 10


func choose_spawn_variant(_rng: RandomNumberGenerator) -> int:
	return 0


func select_spawn_tile(_generator: WorldGenerator, coords: Vector2i, rng: RandomNumberGenerator, _variant: int, _active_map: MapSpec = null) -> Vector2i:
	return coords * WorldGenerator.CHUNK_SIZE + Vector2i(rng.randi_range(0, 31), rng.randi_range(0, 31))


func can_spawn_variant_at(generator: WorldGenerator, tile: Vector2i, _variant: int) -> bool:
	return can_spawn_at(generator, tile)


func can_spawn_at(generator: WorldGenerator, tile: Vector2i) -> bool:
	if generator == null or not generator.is_walkable(tile):
		return false
	return allowed_biomes.is_empty() or generator.sample_biome(tile) in allowed_biomes
