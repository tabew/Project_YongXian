class_name RunMapConfig
extends RefCounted

## 局内地图生成配置：层 → 区域 → 房间 的数量范围与保底规则。
## 全部有默认值，不配置也能跑。

## 每层区域数 2~3。
var min_regions: int = 2
var max_regions: int = 3
## 每区域房间数 4~8。
var min_rooms: int = 4
var max_rooms: int = 8
## 额外跳边概率：制造环路与 2~3 个出口。
var loop_chance: float = 0.5
## 连续战斗房上限：超过就强制插一个冷却房。
var combat_run_limit: int = 4
## 每层秘密房数量。
var secret_rooms: int = 1
## 指定区域主题序列；不足的部分从主题表里补。
var theme_ids: Array[StringName] = []


static func prototype() -> RunMapConfig:
	## 最小可玩原型：1 层，2 区域（毒沼、矿洞），每区域 4~6 房间。
	var config := RunMapConfig.new()
	config.min_rooms = 4
	config.max_rooms = 6
	config.theme_ids = RegionThemeCatalog.PROTOTYPE_THEME_IDS.duplicate()
	return config


static func full() -> RunMapConfig:
	var config := RunMapConfig.new()
	return config
