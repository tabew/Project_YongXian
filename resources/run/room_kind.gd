class_name RoomKind
extends RefCounted

## 新地图系统的房间类型（与旧 RoomType 并存，旧系统可继续使用）。
## 数值稳定，便于存档与调试输出。
enum Kind {
	COMBAT = 0,     ## 战斗房
	ELITE = 1,      ## 精英房
	BOSS = 2,       ## Boss 房
	EVENT = 3,      ## 事件房
	SHOP = 4,       ## 商店房
	TREASURE = 5,   ## 宝箱房
	ALCHEMY = 6,    ## 炼金房
	REST = 7,       ## 休息房
	CHALLENGE = 8,  ## 挑战房
	SECRET = 9,     ## 秘密房
}

const COUNT: int = 10

const NAMES: Array[String] = [
	"战斗房", "精英房", "Boss 房", "事件房", "商店房",
	"宝箱房", "炼金房", "休息房", "挑战房", "秘密房",
]

## 按炼金决策归类：续组合 / 换组合 / 取材 / 冷却 / 图鉴。
enum Decision {
	SUSTAIN = 0,
	SWITCH = 1,
	LURE = 2,
	COOL = 3,
	CODEX = 4,
}

## 每层保底类别：续组合房、换组合房、取材房、冷却房、秘密房。
const GUARANTEED_DECISIONS: Array[int] = [
	Decision.SUSTAIN, Decision.SWITCH, Decision.LURE, Decision.COOL, Decision.CODEX,
]


static func name_of(kind: int) -> String:
	if kind < 0 or kind >= COUNT:
		return "未知"
	return NAMES[kind]


static func decision_of(kind: int) -> int:
	match kind:
		Kind.COMBAT:
			return Decision.SUSTAIN
		Kind.ELITE:
			return Decision.SWITCH
		Kind.BOSS:
			return Decision.SWITCH
		Kind.SHOP, Kind.TREASURE, Kind.EVENT:
			return Decision.LURE
		Kind.REST, Kind.ALCHEMY, Kind.CHALLENGE:
			return Decision.COOL
		Kind.SECRET:
			return Decision.CODEX
	return Decision.LURE


## 可参与普通门选择的房间（Boss 与秘密房单独处理）。
static func is_selectable(kind: int) -> bool:
	return kind != Kind.BOSS and kind != Kind.SECRET


static func is_combat(kind: int) -> bool:
	return kind == Kind.COMBAT or kind == Kind.ELITE or kind == Kind.BOSS or kind == Kind.CHALLENGE
