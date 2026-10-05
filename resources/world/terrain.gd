class_name Terrain
extends RefCounted

## 地形定义。
##
## 编号同时就是地形图集（assets/terrain_tiles.png）里的行坐标，
## 修改顺序时必须同步改 tools/generate_art.py 里的 TERRAINS 列表。

enum Kind {
	DEEP_WATER = 0,   ## 深水
	WATER = 1,        ## 浅水
	ICE = 2,          ## 浮冰
	SAND = 3,         ## 沙滩
	GRASS = 4,        ## 草地
	FOREST = 5,       ## 森林
	TAIGA = 6,        ## 针叶林
	RAINFOREST = 7,   ## 雨林
	SWAMP = 8,        ## 沼泽
	SAVANNA = 9,      ## 稀树草原
	DESERT = 10,      ## 沙漠
	TUNDRA = 11,      ## 苔原
	STONE = 12,       ## 石地
	MOUNTAIN = 13,    ## 山地
	SNOW = 14,        ## 雪原
	SNOW_PEAK = 15,   ## 雪峰
}

const COUNT: int = 16

const NAMES: Array[String] = [
	"深水", "浅水", "浮冰", "沙滩", "草地", "森林", "针叶林", "雨林",
	"沼泽", "稀树草原", "沙漠", "苔原", "石地", "山地", "雪原", "雪峰",
]

## 索引与 Kind 对齐；true 表示挡路。
const BLOCKING: Array[bool] = [
	true, true, false, false, false, false, false, false,
	false, false, false, false, false, true, false, true,
]


static func is_walkable(kind: int) -> bool:
	if kind < 0 or kind >= COUNT:
		return false
	return not BLOCKING[kind]


static func name_of(kind: int) -> String:
	if kind < 0 or kind >= COUNT:
		return "未知"
	return NAMES[kind]
