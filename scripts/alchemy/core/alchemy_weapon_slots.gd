class_name AlchemyWeaponSlots
extends RefCounted

## 武器炼金槽：武器上挂载炼金组合的槽位（纯逻辑，不碰场景树）。
##
## 临时槽：战斗中的炼金把组合装进来，默认 1 个、最多 2 个；装第 3 个会挤掉最旧的。
## 永久槽：只能由非战斗合金开出，常驻生效，不会被替换也不会过期。
## 槽位内容用 BrewCombo 快照表示，便于存档与 UI 展示。

## 初始临时槽数。
const TEMPORARY_BASE: int = 1
## 临时槽上限（升级 / 遗物最多把它抬到这里）。
const TEMPORARY_MAX: int = 2

signal changed

## 临时槽数量上限。
var temporary_limit: int = TEMPORARY_BASE
## 临时槽内容，索引 0 是最近装入的那个（当前生效）。
var temporary: Array[BrewCombo] = []
## 永久槽内容，只能靠非战斗合金开出。
var permanent: Array[BrewCombo] = []


## 设定临时槽上限；返回实际生效的上限。缩小时多余的临时槽会被丢弃。
func set_temporary_limit(value: int) -> int:
	var target: int = clampi(value, TEMPORARY_BASE, TEMPORARY_MAX)
	if target == temporary_limit:
		return temporary_limit
	temporary_limit = target
	if temporary.size() > temporary_limit:
		temporary.resize(temporary_limit)
	changed.emit()
	return temporary_limit


## 装入临时槽；返回被挤出的旧组合（没有则返回 null）。
func install_temporary(combo: BrewCombo) -> BrewCombo:
	if combo == null or combo.is_empty():
		return null
	temporary.push_front(combo.duplicate_combo())
	var evicted: BrewCombo = null
	if temporary.size() > temporary_limit:
		evicted = temporary[temporary.size() - 1]
		temporary.resize(temporary_limit)
	changed.emit()
	return evicted


## 开出一个永久槽；组合为空时拒绝，返回是否成功。
func add_permanent(combo: BrewCombo) -> bool:
	if combo == null or combo.is_empty():
		return false
	permanent.append(combo.duplicate_combo())
	changed.emit()
	return true


## 当前生效的临时组合；没有则返回 null。
func active_temporary() -> BrewCombo:
	return temporary[0] if not temporary.is_empty() else null


## 永久槽带来的常驻伤害加成（各槽组合强度之和）。
func permanent_bonus() -> float:
	var total: float = 0.0
	for combo: BrewCombo in permanent:
		total += combo.power
	return total


func temporary_count() -> int:
	return temporary.size()


func permanent_count() -> int:
	return permanent.size()


## 还有没有空闲的临时槽。
func has_free_temporary() -> bool:
	return temporary.size() < temporary_limit


func clear_temporary() -> void:
	if temporary.is_empty():
		return
	temporary.clear()
	changed.emit()


func clear() -> void:
	if temporary.is_empty() and permanent.is_empty():
		return
	temporary.clear()
	permanent.clear()
	changed.emit()


## 槽位摘要（UI 展示用）：[{"name": 组合描述, "power": 强度, "permanent": 是否永久槽}]。
func summaries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for combo: BrewCombo in temporary:
		rows.append({"name": combo.describe(), "power": combo.power, "permanent": false})
	for combo: BrewCombo in permanent:
		rows.append({"name": combo.describe(), "power": combo.power, "permanent": true})
	return rows


func to_dict() -> Dictionary:
	var temp_rows: Array = []
	for combo: BrewCombo in temporary:
		temp_rows.append(_combo_to_dict(combo))
	var perm_rows: Array = []
	for combo: BrewCombo in permanent:
		perm_rows.append(_combo_to_dict(combo))
	return {"temporary_limit": temporary_limit, "temporary": temp_rows, "permanent": perm_rows}


func from_dict(data: Dictionary) -> void:
	temporary_limit = clampi(int(data.get("temporary_limit", TEMPORARY_BASE)), TEMPORARY_BASE, TEMPORARY_MAX)
	temporary.clear()
	for row: Variant in data.get("temporary", []):
		if row is Dictionary:
			temporary.append(_combo_from_dict(row as Dictionary))
	if temporary.size() > temporary_limit:
		temporary.resize(temporary_limit)
	permanent.clear()
	for row: Variant in data.get("permanent", []):
		if row is Dictionary:
			permanent.append(_combo_from_dict(row as Dictionary))
	changed.emit()


static func _combo_to_dict(combo: BrewCombo) -> Dictionary:
	var tags: Array = []
	for tag: StringName in combo.effect_tags:
		tags.append(String(tag))
	return {
		"tags": tags,
		"name": combo.describe(),
		"power": combo.power,
		"duration": combo.base_duration,
		"self_damage": combo.self_damage,
	}


static func _combo_from_dict(row: Dictionary) -> BrewCombo:
	var combo: BrewCombo = BrewCombo.new()
	for tag: Variant in row.get("tags", []):
		combo.effect_tags.append(StringName(tag))
	combo.power = float(row.get("power", 1.0))
	combo.base_duration = float(row.get("duration", AlchemyRules.BASE_DURATION))
	combo.self_damage = float(row.get("self_damage", 0.0))
	return combo
