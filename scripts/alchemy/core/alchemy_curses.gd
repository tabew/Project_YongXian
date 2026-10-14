class_name AlchemyCurses
extends RefCounted

## 诅咒炼金：用「强度 / 时长」换「自伤 / 热量 / 额外消耗」。
##
## 两条来源：玩家手动选一条诅咒，或「诅咒」词条按等级强制附带 1~3 条随机诅咒。
## 纯逻辑，配置来自 CURSES；实际扣材料 / 加自伤由 AlchemyStation 与战斗层执行。

signal changed

## 诅咒配置表（唯一真源）：power 强度、duration 时长、self_damage 每秒自伤、
## heat 额外热量、material_cost 额外消耗的材料数。
const CURSES: Array[Dictionary] = [
	{"id": &"blood_pact", "name": "血契", "desc": "强度 +25%，每秒自伤 +1",
		"power": 0.25, "self_damage": 1.0},
	{"id": &"frenzy", "name": "狂乱", "desc": "强度 +40%，热量 +30",
		"power": 0.40, "heat": 30.0},
	{"id": &"brittle", "name": "脆化", "desc": "强度 +50%，时长 -30%",
		"power": 0.50, "duration": -0.30},
	{"id": &"overdraw", "name": "透支", "desc": "时长 +60%，热量 +20",
		"duration": 0.60, "heat": 20.0},
	{"id": &"soul_tithe", "name": "魂税", "desc": "强度 +30%，额外消耗 1 个材料",
		"power": 0.30, "material_cost": 1},
	{"id": &"corrosion", "name": "蚀骨", "desc": "强度 +60%，每秒自伤 +2",
		"power": 0.60, "self_damage": 2.0},
	{"id": &"chaos", "name": "混沌", "desc": "强度 +80%，时长 -20%，热量 +25",
		"power": 0.80, "duration": -0.20, "heat": 25.0},
	{"id": &"deathmark", "name": "死印", "desc": "强度 +100%，每秒自伤 +3",
		"power": 1.00, "self_damage": 3.0},
]

## 玩家手动选择的一条诅咒（可为空）。
var selected_curse: StringName = &""
## 本次炼金由「诅咒」词条随机附带、需要结算的诅咒。
var _rolled: Array[StringName] = []


static func curse_of(id: StringName) -> Dictionary:
	for entry: Dictionary in CURSES:
		if entry["id"] == id:
			return entry
	return {}


static func has_curse(id: StringName) -> bool:
	return not curse_of(id).is_empty()


static func all_curse_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in CURSES:
		ids.append(entry["id"])
	return ids


static func display_name_of(id: StringName) -> String:
	return String(curse_of(id).get("name", String(id)))


## ── 手动选择 ────────────────────────────────────────────────────────────

## 选一条诅咒；传空 StringName 表示取消。
func select(id: StringName) -> bool:
	if id != &"" and not has_curse(id):
		return false
	if selected_curse == id:
		return true
	selected_curse = id
	changed.emit()
	return true


func clear_selection() -> void:
	if selected_curse == &"":
		return
	selected_curse = &""
	changed.emit()


## ── 随机诅咒（诅咒词条）────────────────────────────────────────────────

## 随机抽 count 条互不相同的诅咒。
func pick_random(count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var pool: Array[StringName] = all_curse_ids()
	var picked: Array[StringName] = []
	var total: int = clampi(count, 0, pool.size())
	for _index: int in range(total):
		var index: int = rng.randi_range(0, pool.size() - 1)
		picked.append(pool[index])
		pool.remove_at(index)
	return picked


## 按组合里的「诅咒」词条等级决定附带几条诅咒；没有诅咒词条返回 0。
static func curse_count_of(combo: BrewCombo) -> int:
	if combo == null:
		return 0
	for trait_instance: TraitInstance in combo.traits:
		if trait_instance.id == &"curse":
			return int(trait_instance.value_of(&"curses"))
	return 0


## 为一次炼金结算诅咒：先清空，再取「玩家手动选的」或「诅咒词条随机出的」。
func roll_for_combo(combo: BrewCombo, rng: RandomNumberGenerator) -> Array[StringName]:
	_rolled.clear()
	if selected_curse != &"":
		_rolled.append(selected_curse)
	else:
		_rolled = pick_random(curse_count_of(combo), rng)
	return _rolled.duplicate()


func rolled_curses() -> Array[StringName]:
	return _rolled.duplicate()


## ── 结算 ────────────────────────────────────────────────────────────────

## 参与结算的诅咒：手动选择的 + 随机附带的，去重。
func active_curses() -> Array[StringName]:
	var result: Array[StringName] = []
	if selected_curse != &"":
		result.append(selected_curse)
	for id: StringName in _rolled:
		if not result.has(id):
			result.append(id)
	return result


func _sum(key: StringName) -> float:
	var total: float = 0.0
	for id: StringName in active_curses():
		total += float(curse_of(id).get(key, 0.0))
	return total


## 强度加成（累加）。
func power_bonus() -> float:
	return _sum(&"power")


## 时长加成（累加，可为负）。
func duration_bonus() -> float:
	return _sum(&"duration")


## 额外每秒自伤。
func self_damage() -> float:
	return _sum(&"self_damage")


## 额外热量。
func heat_bonus() -> float:
	return _sum(&"heat")


## 额外消耗的材料数。
func material_cost() -> int:
	return int(_sum(&"material_cost"))


func is_active() -> bool:
	return not active_curses().is_empty()


func reset() -> void:
	selected_curse = &""
	_rolled.clear()
	changed.emit()
