class_name RegionBiomes
extends RefCounted

## 整片箱庭先确定主题，格子噪声只产生同主题的大块地形。
const LAND: PackedInt32Array = [
	Biome.Kind.FOREST, Biome.Kind.GRASSLAND, Biome.Kind.DESERT,
	Biome.Kind.SAVANNA, Biome.Kind.TROPICAL_RAINFOREST, Biome.Kind.SWAMP,
	Biome.Kind.TAIGA, Biome.Kind.TUNDRA, Biome.Kind.SNOWY_PLAINS, Biome.Kind.MOUNTAIN,
]


static func sequence(seed_value: int, variant: int = 0) -> PackedInt32Array:
	var result: PackedInt32Array = LAND.duplicate()
	var source: RandomNumberGenerator = MapRng.new(seed_value).rng(MapRng.Stream.MAP, 4101 + variant * 97)
	for index: int in range(result.size() - 1, 0, -1):
		var other: int = source.randi_range(0, index)
		var saved: int = result[index]
		result[index] = result[other]
		result[other] = saved
	return result


static func boundary_for(biome: int) -> int:
	match biome:
		Biome.Kind.FOREST, Biome.Kind.GRASSLAND, Biome.Kind.SAVANNA, Biome.Kind.SWAMP:
			return Terrain.Kind.FOREST
		Biome.Kind.TROPICAL_RAINFOREST:
			return Terrain.Kind.RAINFOREST
		Biome.Kind.TAIGA:
			return Terrain.Kind.TAIGA
		Biome.Kind.SNOWY_PLAINS, Biome.Kind.ALPINE:
			return Terrain.Kind.SNOW_PEAK
	return Terrain.Kind.MOUNTAIN


static func ground_for(biome: int) -> int:
	match biome:
		Biome.Kind.DESERT:
			return Terrain.Kind.DESERT
		Biome.Kind.SAVANNA:
			return Terrain.Kind.SAVANNA
		Biome.Kind.SWAMP:
			return Terrain.Kind.SWAMP
		Biome.Kind.TUNDRA:
			return Terrain.Kind.TUNDRA
		Biome.Kind.SNOWY_PLAINS, Biome.Kind.TAIGA, Biome.Kind.ALPINE:
			return Terrain.Kind.SNOW
		Biome.Kind.MOUNTAIN:
			return Terrain.Kind.STONE
	return Terrain.Kind.GRASS


static func terrain_for(biome: int, variation: float, grove: float) -> int:
	var ground: int = ground_for(biome)
	match biome:
		Biome.Kind.FOREST, Biome.Kind.TAIGA, Biome.Kind.TROPICAL_RAINFOREST:
			# 同一片缓慢变化的树林，不再用高频噪声逐格切换森林、雪地和沙漠。
			return boundary_for(biome) if grove > 0.62 else ground
		Biome.Kind.MOUNTAIN, Biome.Kind.ALPINE:
			return boundary_for(biome) if grove > 0.62 else ground
		Biome.Kind.DESERT:
			return Terrain.Kind.SAND if variation > 0.69 else ground
		Biome.Kind.TUNDRA:
			return Terrain.Kind.SNOW if variation > 0.76 else ground
		Biome.Kind.GRASSLAND:
			return Terrain.Kind.STONE if variation > 0.78 else ground
	return ground
