class_name RoomType
extends RefCounted

## 房间类型。数值稳定，便于调试输出与后续存盘。
enum Kind {
	START = 0,   ## 起点
	COMBAT = 1,  ## 战斗
	REWARD = 2,  ## 奖励
	SHOP = 3,    ## 商店
	REST = 4,    ## 休息
	EVENT = 5,   ## 事件
	BOSS = 6,    ## Boss
}

const COUNT: int = 7

const NAMES: Array[String] = ["起点", "战斗", "奖励", "商店", "休息", "事件", "Boss"]

## 关键房间：必须存在、必须可达、不能紧邻 Boss。
const KEY_KINDS: Array[int] = [Kind.SHOP, Kind.REWARD, Kind.REST]


static func name_of(kind: int) -> String:
	if kind < 0 or kind >= COUNT:
		return "未知"
	return NAMES[kind]


static func is_key(kind: int) -> bool:
	return KEY_KINDS.has(kind)


## 调试与 ASCII 图用的单字母缩写。
static func short_name(kind: int) -> String:
	match kind:
		Kind.START:
			return "P"
		Kind.COMBAT:
			return "C"
		Kind.REWARD:
			return "R"
		Kind.SHOP:
			return "$"
		Kind.REST:
			return "H"
		Kind.EVENT:
			return "E"
		Kind.BOSS:
			return "B"
	return "?"
