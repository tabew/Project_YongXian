class_name DifficultyTier
extends RefCounted

## 难度祭坛的档位（只做基础 3 档）。自定义修饰接口预留，先返回空列表。

enum Tier {
	APPRENTICE = 0,  ## 学徒 1.0x
	ALCHEMIST = 1,   ## 炼金师 1.2x
	MASTER = 2,      ## 大师 1.5x
}

const COUNT: int = 3

const NAMES: Array[String] = ["学徒", "炼金师", "大师"]
const DESCRIPTIONS: Array[String] = [
	"标准难度，适合熟悉炼金循环。",
	"敌人更强，灵感倍率 1.2x。",
	"高压难度，灵感倍率 1.5x。",
]


static func name_of(tier: int) -> String:
	if tier < 0 or tier >= COUNT:
		return "未知难度"
	return NAMES[tier]


static func description_of(tier: int) -> String:
	return DESCRIPTIONS[clampi(tier, 0, COUNT - 1)]


static func multiplier(tier: int) -> float:
	return InspirationRules.difficulty_multiplier(tier)


## 难度解锁：通关一次解锁下一档。clears 是本存档的累计通关次数。
static func unlocked_max_tier(clears: int) -> int:
	return clampi(clears, 0, COUNT - 1)


static func is_unlocked(tier: int, clears: int) -> bool:
	return tier >= 0 and tier < COUNT and tier <= unlocked_max_tier(clears)


## 自定义修饰接口预留：现在永远返回空数组。
static func modifiers(_tier: int) -> Array[StringName]:
	return []
