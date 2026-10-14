class_name RunMapBuilder
extends RefCounted

## 把局内地图（RunMapGenerator 产出的 FloorData）接到世界生成器上。
##
## 分工：
## - RunMapGenerator：纯逻辑，产出层 → 区域 → 房间与门（可单元测试）。
## - FloorRoomGraph：把房间图翻译成 WorldGenerator 认识的编号与类型。
## - WorldGenerator：继续负责地形、区域位置、物理门与刷怪预算。
##
## 本类只做一次装配，不持有状态。


## 生成一层可玩的世界：FloorData → 房间图 → 世界生成器。
static func build(
	seed_value: int,
	floor_index: int = 0,
	run_config: RunMapConfig = null,
	map_config: MapConfig = null
) -> WorldGenerator:
	var floor: FloorData = RunMapGenerator.generate(seed_value, floor_index, run_config)
	return build_from_floor(seed_value, floor, map_config)


## 用已有的 FloorData 装配世界（便于测试与复用同一层数据）。
static func build_from_floor(seed_value: int, floor: FloorData, map_config: MapConfig = null) -> WorldGenerator:
	var graph: FloorRoomGraph = FloorRoomGraph.plan_from_floor(floor, map_config, seed_value)
	return WorldGenerator.new(seed_value, map_config, 0, graph)
