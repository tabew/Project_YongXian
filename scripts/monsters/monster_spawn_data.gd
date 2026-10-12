class_name MonsterSpawnData
extends Resource

## 单种怪物的生成配置；行为、血量和索敌规则仍由怪物脚本负责。

@export var monster_id: StringName
@export var monster_scene: PackedScene
@export var allowed_biomes: Array[int] = []
@export_range(0.0, 1.0, 0.01) var chunk_spawn_chance: float = 1.0
@export_range(1, 100, 1) var max_per_chunk: int = 1
@export_range(1, 256, 1) var candidate_attempts: int = 24


func can_spawn_at(generator: WorldGenerator, tile: Vector2i) -> bool:
	if generator == null or not generator.is_walkable(tile):
		return false
	return allowed_biomes.is_empty() or generator.sample_biome(tile) in allowed_biomes
