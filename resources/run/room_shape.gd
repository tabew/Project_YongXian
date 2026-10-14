class_name RoomShape
extends RefCounted

## 房间形状：每种形状适合不同词条（长条适合穿透/连锁，圆形适合爆炸/扩散等）。

enum Shape {
	LONG = 0,      ## 长条
	CIRCLE = 1,    ## 圆形
	L_SHAPE = 2,   ## L 形
	CROSS = 3,     ## 十字
	RING = 4,      ## 环形
	NARROW = 5,    ## 窄道
	OPEN = 6,      ## 开阔
}

const COUNT: int = 7

const NAMES: Array[String] = ["长条", "圆形", "L 形", "十字", "环形", "窄道", "开阔"]

## 形状对应的词条倾向：生成器据此给房间预置材料/敌人。
const FAVORED_TRAITS: Dictionary = {
	Shape.LONG: [&"pierce", &"chain"],
	Shape.CIRCLE: [&"explode", &"spread"],
	Shape.L_SHAPE: [&"bounce", &"pierce"],
	Shape.CROSS: [&"spread", &"chain"],
	Shape.RING: [&"whirl", &"duration"],
	Shape.NARROW: [&"pierce", &"magnet"],
	Shape.OPEN: [&"spread", &"explode"],
}


static func name_of(shape: int) -> String:
	if shape < 0 or shape >= COUNT:
		return "未知"
	return NAMES[shape]


static func favored_traits(shape: int) -> Array:
	return FAVORED_TRAITS.get(shape, [])
