class_name Route
extends RefCounted

## 路网定义。
##
## 路是**渲染层**的概念：地形与生物群系数据完全不变，只是把路所在格子的贴图换成路面。
## 这样既保住了原有群系，又不用为"每种地形 × 每种路"准备贴图。
##
## 主路 / 支线来自两张不同频率噪声的零等值线：
## abs(noise) 很小的地方正好落在噪声的过零点上，天然形成蜿蜒曲线，
## 低频 → 又宽又长的主干道，高频 → 又窄又多的岔路。

enum Kind {
	NONE = 0,    ## 不是路
	DIRT = 1,    ## 土路（支线）
	STONE = 2,   ## 石板路（主路）
	BRIDGE = 3,  ## 木桥（路跨过水面）
}

## 实际会绘制出来的路的数量（不含 NONE）。
const COUNT: int = 3

## 图集第 0 行对应 Kind.DIRT，所以图集行号 = Kind - ATLAS_ROW_OFFSET。
const ATLAS_ROW_OFFSET: int = 1

## 索引与 Kind 对齐。
const NAMES: Array[String] = ["无", "土路", "石板路", "木桥"]

## 路一定可以通行：主干道会开山道、架桥，保证玩家顺得下去。
const MINIMAP_MARK: bool = true


static func is_road(kind: int) -> bool:
	return kind != Kind.NONE


static func atlas_row(kind: int) -> int:
	return kind - ATLAS_ROW_OFFSET


static func name_of(kind: int) -> String:
	if kind < 0 or kind >= NAMES.size():
		return "无"
	return NAMES[kind]
