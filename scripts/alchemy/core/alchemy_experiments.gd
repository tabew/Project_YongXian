class_name AlchemyExperiments
extends RefCounted

## 实验系统：把「材料组合」当作可解锁的知识。
##
## 未解锁的实验在 UI 上只显示「？？？」与产地提示；花材料做实验，
## 成功则解锁图鉴条目，失败则出事故（自伤 + 额外热量）。
## 纯逻辑，不依赖场景树，可单独单元测试。

const UNKNOWN_TEXT: String = "？？？"
const DEFAULT_ACCIDENT_CHANCE: float = 0.35
## 事故惩罚：自伤点数与额外热量。
const ACCIDENT_SELF_DAMAGE: float = 6.0
const ACCIDENT_HEAT: float = 15.0
## 每次实验的基础热量。
const EXPERIMENT_HEAT: float = 10.0

signal unlocked_changed
signal experiment_result(result: Dictionary)

## 实验配方表（唯一真源）：materials 是材料 id 组合，与顺序无关；
## reaction 是解锁时同时登记进图鉴的反应 id。
const EXPERIMENTS: Array[Dictionary] = [
	{"id": &"exp_poison_smoke", "name": "毒烟", "reaction": &"poison_smoke",
		"materials": [1001, 1002], "hint": "毒沼 × 矿洞", "accident_chance": 0.30},
	{"id": &"exp_steam_burst", "name": "蒸汽爆炸", "reaction": &"steam_burst",
		"materials": [1005, 1002], "hint": "冰区 × 矿洞", "accident_chance": 0.45},
	{"id": &"exp_magnetic_field", "name": "磁场拉拽", "reaction": &"magnetic_field",
		"materials": [1022, 1021], "hint": "雷区 × 机械废墟", "accident_chance": 0.35},
	{"id": &"exp_corrode", "name": "腐蚀破甲", "reaction": &"corrosive_sunder",
		"materials": [1004, 1012], "hint": "酸池 × 机械废墟", "accident_chance": 0.30},
	{"id": &"exp_skeleton", "name": "召唤骷髅", "reaction": &"skeleton_summon",
		"materials": [1023, 1003], "hint": "墓地 × 墓地", "accident_chance": 0.40},
	{"id": &"exp_annihilation", "name": "湮灭", "reaction": &"annihilation",
		"materials": [1050, 1051], "hint": "光殿 × 深渊", "accident_chance": 0.60},
	{"id": &"exp_dust_storm", "name": "尘暴致盲", "reaction": &"dust_storm",
		"materials": [1010, 1011], "hint": "草原 × 沙漠", "accident_chance": 0.25},
	{"id": &"exp_deflagration", "name": "爆燃", "reaction": &"deflagration",
		"materials": [1006, 1014], "hint": "火区 × 火区", "accident_chance": 0.40},
	{"id": &"exp_blizzard", "name": "暴风雪", "reaction": &"blizzard",
		"materials": [1005, 1010], "hint": "冰区 × 草原", "accident_chance": 0.35},
	{"id": &"exp_holy_flame", "name": "圣火", "reaction": &"holy_flame",
		"materials": [1026, 1006], "hint": "光殿 × 火区", "accident_chance": 0.45},
	{"id": &"exp_glass_forge", "name": "玻璃", "reaction": &"glass_forge",
		"materials": [1011, 1002], "hint": "沙漠 × 矿洞", "accident_chance": 0.35},
	{"id": &"exp_soul_devour", "name": "灵魂吞噬", "reaction": &"soul_devour",
		"materials": [1045, 1027], "hint": "墓地 × 深渊", "accident_chance": 0.55},
]

var _unlocked: Dictionary = {}


static func definition_of(experiment_id: StringName) -> Dictionary:
	for entry: Dictionary in EXPERIMENTS:
		if entry["id"] == experiment_id:
			return entry
	return {}


static func recipe_of(entry: Dictionary) -> Array[int]:
	var recipe: Array[int] = []
	for value: Variant in entry.get("materials", []):
		recipe.append(int(value))
	return recipe


## 材料组合的规范化键：排序后拼接，顺序无关。
static func key_of(material_ids: Array[int]) -> String:
	var sorted: Array[int] = material_ids.duplicate()
	sorted.sort()
	var parts: PackedStringArray = []
	for material_id: int in sorted:
		parts.append(str(material_id))
	return "+".join(parts)


## 找出覆盖给定材料组合的实验：配方材料必须是组合的子集，取材料最多的一条。
static func experiment_for(material_ids: Array[int]) -> Dictionary:
	var best: Dictionary = {}
	for entry: Dictionary in EXPERIMENTS:
		var recipe: Array[int] = recipe_of(entry)
		if recipe.is_empty() or not _is_subset(recipe, material_ids):
			continue
		if best.is_empty() or recipe.size() > recipe_of(best).size():
			best = entry
	return best


static func _is_subset(recipe: Array[int], material_ids: Array[int]) -> bool:
	var pool: Array[int] = material_ids.duplicate()
	for material_id: int in recipe:
		var index: int = pool.find(material_id)
		if index < 0:
			return false
		pool.remove_at(index)
	return true


func is_unlocked(experiment_id: StringName) -> bool:
	return bool(_unlocked.get(experiment_id, false))


## 未解锁只显示「？？？」，已解锁显示正式名字。
func display_name(experiment_id: StringName) -> String:
	if not is_unlocked(experiment_id):
		return UNKNOWN_TEXT
	return String(definition_of(experiment_id).get("name", UNKNOWN_TEXT))


## 产地提示：未解锁时也给玩家一点方向，避免完全盲试。
func hint_of(experiment_id: StringName) -> String:
	return String(definition_of(experiment_id).get("hint", ""))


func unlock(experiment_id: StringName) -> bool:
	if experiment_id == &"" or is_unlocked(experiment_id):
		return false
	_unlocked[experiment_id] = true
	unlocked_changed.emit()
	return true


func unlocked_count() -> int:
	var count: int = 0
	for entry: Dictionary in EXPERIMENTS:
		if is_unlocked(entry["id"]):
			count += 1
	return count


func completion_ratio() -> float:
	return float(unlocked_count()) / float(maxi(EXPERIMENTS.size(), 1))


## 做一次实验：命中配方时按概率决定「解锁」还是「事故」。
## 返回 {status: unlocked / accident / known / nothing, id, name, reaction, self_damage, heat}。
func resolve(material_ids: Array[int], rng: RandomNumberGenerator) -> Dictionary:
	var entry: Dictionary = experiment_for(material_ids)
	if entry.is_empty():
		return {"status": "nothing", "id": &"", "name": UNKNOWN_TEXT, "reaction": &"", "self_damage": 0.0, "heat": 0.0}
	var experiment_id: StringName = entry["id"]
	if is_unlocked(experiment_id):
		return {"status": "known", "id": experiment_id, "name": String(entry["name"]),
			"reaction": entry.get("reaction", &""), "self_damage": 0.0, "heat": EXPERIMENT_HEAT}
	var chance: float = clampf(float(entry.get("accident_chance", DEFAULT_ACCIDENT_CHANCE)), 0.0, 1.0)
	var accident: bool = rng.randf() < chance
	var result: Dictionary = {
		"status": "accident" if accident else "unlocked",
		"id": experiment_id,
		"name": String(entry["name"]),
		"reaction": entry.get("reaction", &""),
		"self_damage": ACCIDENT_SELF_DAMAGE if accident else 0.0,
		"heat": EXPERIMENT_HEAT + (ACCIDENT_HEAT if accident else 0.0),
	}
	if not accident:
		unlock(experiment_id)
	experiment_result.emit(result)
	return result


func to_dict() -> Dictionary:
	var ids: Array[String] = []
	for experiment_id: Variant in _unlocked.keys():
		ids.append(String(experiment_id))
	return {"unlocked": ids}


func from_dict(data: Dictionary) -> void:
	_unlocked.clear()
	for value: Variant in data.get("unlocked", []):
		_unlocked[StringName(value)] = true


func reset() -> void:
	_unlocked.clear()
