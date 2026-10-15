class_name SecretDoor
extends RefCounted

## 秘密房的词条门：需要特定词条才能进入。
## 只描述需求，判定由战斗/炼金层调用 matches() 完成。

enum Kind {
	EXPLODE = 0,   ## 炸墙
	MAGNET = 1,    ## 磁吸机关
	PHASE = 2,     ## 相位穿墙
	ACID = 3,      ## 酸蚀门
	FIRE = 4,      ## 火烧藤蔓
	ICE = 5,       ## 冰冻水面
	ELECTRIC = 6,  ## 电开机关
	BONE = 7,      ## 骨钥匙
}

const COUNT: int = 8

const NAMES: Array[String] = ["炸墙", "磁吸机关", "相位穿墙", "酸蚀门", "火烧藤蔓", "冰冻水面", "电开机关", "骨钥匙"]

## 每种门需要的词条与最低等级。
const REQUIREMENTS: Dictionary = {
	Kind.EXPLODE: {"trait": &"explode", "level": 1},
	Kind.MAGNET: {"trait": &"magnet", "level": 1},
	Kind.PHASE: {"trait": &"soul", "level": 1},
	Kind.ACID: {"trait": &"acid", "level": 1},
	Kind.FIRE: {"trait": &"fire", "level": 1},
	Kind.ICE: {"trait": &"ice", "level": 1},
	Kind.ELECTRIC: {"trait": &"electric", "level": 1},
	Kind.BONE: {"trait": &"bone", "level": 1},
}


static func name_of(kind: int) -> String:
	if kind < 0 or kind >= COUNT:
		return "未知门"
	return NAMES[kind]


static func requirement_of(kind: int) -> Dictionary:
	return REQUIREMENTS.get(kind, {"trait": &"", "level": 1})


static func trait_of(kind: int) -> StringName:
	return StringName(requirement_of(kind).get("trait", &""))


static func level_of(kind: int) -> int:
	return int(requirement_of(kind).get("level", 1))


## 判断一组词条是否满足开门条件。
## trait_levels: {trait_id: 等级}
static func matches(kind: int, trait_levels: Dictionary) -> bool:
	var trait_id := trait_of(kind)
	if trait_id == &"":
		return false
	return int(trait_levels.get(trait_id, 0)) >= level_of(kind)


## 把炼金组合的公开快照 [{ "id": StringName, "level": int }] 压成判定表。
## 只接受公开数据，本模块不引用炼金内部类型；同词条取最高等级。
static func levels_from(trait_entries: Array) -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in trait_entries:
		var trait_id := StringName(entry.get("id", &""))
		if trait_id == &"":
			continue
		var level: int = int(entry.get("level", 1))
		result[trait_id] = maxi(int(result.get(trait_id, 0)), level)
	return result


## 该门需求词条的中文名，供门面提示。
static func trait_name_of(kind: int) -> String:
	return TraitCatalog.display_name_of(trait_of(kind))


## 一句可读的开门提示。
static func requirement_text(kind: int) -> String:
	return "%s：需要「%s」" % [name_of(kind), trait_name_of(kind)]
