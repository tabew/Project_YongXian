class_name Biome
extends RefCounted

## 生物群系定义：由海拔 + 温度 + 湿度共同决定，再映射成具体地形。

enum Kind {
	DEEP_OCEAN = 0,          ## 深海
	OCEAN = 1,               ## 海洋
	BEACH = 2,               ## 海岸
	DESERT = 3,              ## 沙漠
	SAVANNA = 4,             ## 稀树草原
	GRASSLAND = 5,           ## 草原
	FOREST = 6,              ## 森林
	TROPICAL_RAINFOREST = 7, ## 热带雨林
	SWAMP = 8,               ## 沼泽
	TAIGA = 9,               ## 针叶林
	TUNDRA = 10,             ## 苔原
	SNOWY_PLAINS = 11,       ## 雪原
	MOUNTAIN = 12,           ## 山地
	ALPINE = 13,             ## 雪峰
}

const COUNT: int = 14

const NAMES: Array[String] = [
	"深海", "海洋", "海岸", "沙漠", "稀树草原", "草原", "森林",
	"热带雨林", "沼泽", "针叶林", "苔原", "雪原", "山地", "雪峰",
]

## 每个群系的三种地形：主要 / 次要 / 点缀，索引与 Kind 对齐。
## 具体用哪一种由 variation 噪声决定，所以同一群系内部也有过渡。
const PRIMARY: Array[int] = [
	Terrain.Kind.DEEP_WATER,   # DEEP_OCEAN
	Terrain.Kind.WATER,        # OCEAN
	Terrain.Kind.SAND,         # BEACH
	Terrain.Kind.DESERT,       # DESERT
	Terrain.Kind.SAVANNA,      # SAVANNA
	Terrain.Kind.GRASS,        # GRASSLAND
	Terrain.Kind.FOREST,       # FOREST
	Terrain.Kind.RAINFOREST,   # TROPICAL_RAINFOREST
	Terrain.Kind.SWAMP,        # SWAMP
	Terrain.Kind.TAIGA,        # TAIGA
	Terrain.Kind.TUNDRA,       # TUNDRA
	Terrain.Kind.SNOW,         # SNOWY_PLAINS
	Terrain.Kind.STONE,        # MOUNTAIN
	Terrain.Kind.SNOW_PEAK,    # ALPINE
]

const SECONDARY: Array[int] = [
	Terrain.Kind.DEEP_WATER,   # DEEP_OCEAN
	Terrain.Kind.DEEP_WATER,   # OCEAN
	Terrain.Kind.SAND,         # BEACH
	Terrain.Kind.SAND,         # DESERT
	Terrain.Kind.GRASS,        # SAVANNA
	Terrain.Kind.SAVANNA,      # GRASSLAND
	Terrain.Kind.GRASS,        # FOREST
	Terrain.Kind.FOREST,       # TROPICAL_RAINFOREST
	Terrain.Kind.GRASS,        # SWAMP
	Terrain.Kind.FOREST,       # TAIGA
	Terrain.Kind.STONE,        # TUNDRA
	Terrain.Kind.TUNDRA,       # SNOWY_PLAINS
	Terrain.Kind.MOUNTAIN,     # MOUNTAIN
	Terrain.Kind.SNOW,         # ALPINE
]

const TERTIARY: Array[int] = [
	Terrain.Kind.DEEP_WATER,   # DEEP_OCEAN
	Terrain.Kind.DEEP_WATER,   # OCEAN
	Terrain.Kind.GRASS,        # BEACH
	Terrain.Kind.DESERT,       # DESERT
	Terrain.Kind.DESERT,       # SAVANNA
	Terrain.Kind.FOREST,       # GRASSLAND
	Terrain.Kind.FOREST,       # FOREST
	Terrain.Kind.SWAMP,        # TROPICAL_RAINFOREST
	Terrain.Kind.WATER,        # SWAMP
	Terrain.Kind.STONE,        # TAIGA
	Terrain.Kind.SNOW,         # TUNDRA
	Terrain.Kind.ICE,          # SNOWY_PLAINS
	Terrain.Kind.SNOW,         # MOUNTAIN
	Terrain.Kind.MOUNTAIN,     # ALPINE
]

## variation < SPLIT_A 用主地形，< SPLIT_B 用次地形，否则用点缀地形。
const SPLIT_A: float = 0.46
const SPLIT_B: float = 0.80


static func name_of(kind: int) -> String:
	if kind < 0 or kind >= COUNT:
		return "未知"
	return NAMES[kind]
