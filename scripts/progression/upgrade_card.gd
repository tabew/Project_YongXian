class_name UpgradeCard
extends RefCounted

## 局内成长卡：一张卡就是一组“效果键 -> 每层数值”。
##
## 数值类效果由 RunProgress 聚合后统一应用；机制类效果由各系统读同名键自行实现。
## 卡本身只描述“给什么”，不关心“谁来用”，因此可以纯数据地写在一张表里。

enum Rarity { COMMON, UNCOMMON, RARE }
enum Scope { GENERAL, WEAPON, ALCHEMY, MECHANIC, COST }

const RARITY_NAMES: Array[String] = ["普通", "精良", "稀有"]

var id: StringName = &""
var display_name: String = ""
var description: String = ""
var rarity: int = Rarity.COMMON
var scope: int = Scope.GENERAL
var max_stacks: int = 1
## 武器卡限定武器 id；空表示不限定。
var weapon_id: StringName = &""
## 效果键 -> 每层数值。
var effects: Dictionary = {}
## 代价卡的生命比例门槛：只有当前生命比例不低于它时才可能出现，0 表示无门槛。
var health_ratio_gate: float = 0.0


static func make(
	card_id: StringName,
	name_text: String,
	desc_text: String,
	card_rarity: int,
	card_scope: int,
	stacks: int,
	card_effects: Dictionary,
	limit_weapon: StringName = &"",
	ratio_gate: float = 0.0
) -> UpgradeCard:
	var card := UpgradeCard.new()
	card.id = card_id
	card.display_name = name_text
	card.description = desc_text
	card.rarity = card_rarity
	card.scope = card_scope
	card.max_stacks = maxi(stacks, 1)
	card.effects = card_effects
	card.weapon_id = limit_weapon
	card.health_ratio_gate = ratio_gate
	return card


static func rarity_name(value: int) -> String:
	if value < 0 or value >= RARITY_NAMES.size():
		return "未知"
	return RARITY_NAMES[value]