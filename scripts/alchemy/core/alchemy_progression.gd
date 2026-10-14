class_name AlchemyProgression
extends RefCounted

## 升级与遗物：把「玩家已经拿到的永久强化」聚合成一组派生修正。
##
## 纯逻辑，不依赖场景树；配置全部来自 ProgressionCatalog。
## 数值型修正相加、布尔型修正取或、slow_motion_scale 取最小，
## AlchemyStation 只读这里的派生字段，不关心玩家具体拿了哪些条目。

signal changed

## 升级 id → 层数。
var _upgrade_levels: Dictionary = {}
## 已获得的遗物 id 集合。
var _relics: Dictionary = {}


## ── 升级 ────────────────────────────────────────────────────────────────

func upgrade_level(id: StringName) -> int:
	return int(_upgrade_levels.get(id, 0))


func has_upgrade(id: StringName) -> bool:
	return upgrade_level(id) > 0


## 加层数：按配置的 max_level 截断；返回新的层数（非法 id 返回 0）。
func add_upgrade(id: StringName, levels: int = 1) -> int:
	if levels <= 0 or not ProgressionCatalog.has_upgrade(id):
		return upgrade_level(id)
	var cap: int = ProgressionCatalog.max_level_of(id)
	var current: int = upgrade_level(id)
	var updated: int = clampi(current + levels, 0, cap)
	if updated == current:
		return current
	_upgrade_levels[id] = updated
	changed.emit()
	return updated


func is_upgrade_maxed(id: StringName) -> bool:
	return upgrade_level(id) >= ProgressionCatalog.max_level_of(id)


## ── 遗物 ────────────────────────────────────────────────────────────────

func has_relic(id: StringName) -> bool:
	return bool(_relics.get(id, false))


## 获得遗物：重复获得返回 false。
func add_relic(id: StringName) -> bool:
	if not ProgressionCatalog.has_relic(id) or has_relic(id):
		return false
	_relics[id] = true
	changed.emit()
	return true


func relic_count() -> int:
	return _relics.size()


func owned_relics() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: Variant in _relics.keys():
		ids.append(StringName(id))
	ids.sort()
	return ids


func upgrade_count() -> int:
	var total: int = 0
	for level: Variant in _upgrade_levels.values():
		total += int(level)
	return total


## ── 修正聚合 ────────────────────────────────────────────────────────────

## 原始聚合表：数值相加、布尔取或、slow_motion_scale 取最小。
func modifiers() -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in _active_entries():
		var modifier: Dictionary = entry.get("modifier", {})
		# 绑定到具体元素的加成只在 element_level_plus() 里按元素取用，不进通用聚合。
		var bound_element: StringName = StringName(modifier.get(&"element_id", &""))
		for key: Variant in modifier:
			var name: StringName = StringName(key)
			var value: Variant = modifier[key]
			if name == &"element_level_plus" and bound_element != &"":
				continue
			if name in ProgressionCatalog.MIN_KEYS:
				result[name] = minf(float(result.get(name, value)), float(value))
			elif name in ProgressionCatalog.FLAG_KEYS:
				result[name] = bool(result.get(name, false)) or bool(value)
			elif name == &"element_id":
				continue
			else:
				result[name] = float(result.get(name, 0.0)) + float(value)
	return result


## 升级 / 遗物条目按「先升级后遗物」的顺序展开，供聚合使用。
func _active_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: StringName in ProgressionCatalog.all_upgrade_ids():
		if upgrade_level(id) > 0:
			var entry: Dictionary = ProgressionCatalog.upgrade_of(id).duplicate(true)
			var modifier: Dictionary = entry.get("modifier", {})
			for key: Variant in modifier:
				var name: StringName = StringName(key)
				# 布尔与取最小值类修正不随层数放大，避免把 true 乘成 0。
				if name == &"element_id" or name in ProgressionCatalog.FLAG_KEYS \
						or name in ProgressionCatalog.MIN_KEYS:
					continue
				modifier[key] = float(modifier[key]) * float(upgrade_level(id))
			entries.append(entry)
	for id: StringName in owned_relics():
		entries.append(ProgressionCatalog.relic_of(id))
	return entries


func _number(key: StringName) -> float:
	return float(modifiers().get(key, 0.0))


func _flag(key: StringName) -> bool:
	return bool(modifiers().get(key, false))


## ── 派生修正（AlchemyStation 只读这些）────────────────────────────────

## 素材槽额外格数（升级 + 遗物）。
func slot_plus() -> int:
	return int(_number(&"slot_plus"))


## 背包额外格数。
func bag_plus() -> int:
	return int(_number(&"bag_plus"))


## 材料堆叠上限倍率（1.0 为基准）。
func stack_multiplier() -> float:
	return maxf(1.0 + _number(&"stack_multiplier_plus"), 0.1)


## 快速预设额外格数。
func preset_plus() -> int:
	return int(_number(&"preset_plus"))


## 武器临时炼金槽额外格数（默认 1 个，最多 2 个）。
func weapon_slot_plus() -> int:
	return int(_number(&"weapon_slot_plus"))


## 炼金稳定加成（作用于持续时长公式）。
func stability_bonus() -> float:
	return _number(&"stability_bonus")


## 热量冷却倍率（1.0 为基准）。
func heat_cooldown_multiplier() -> float:
	return maxf(1.0 + _number(&"heat_cooldown_plus"), 0.1)


## 吸附范围额外格数。
func adsorb_tiles_plus() -> float:
	return _number(&"adsorb_tiles_plus")


## 慢动作倍率：没有相关升级 / 遗物时用基准值，否则取配置里最小的那个。
func slow_motion_scale() -> float:
	var aggregated: Dictionary = modifiers()
	if not aggregated.has(&"slow_motion_scale"):
		return AlchemyRules.SLOW_MOTION_SCALE
	return clampf(float(aggregated[&"slow_motion_scale"]), 0.05, 1.0)


## 替换爆发强度比例：基准 50% + 爆发强化 / 爆发大师 / 爆发符文。
func burst_ratio() -> float:
	return clampf(AlchemyRules.REPLACEMENT_BURST_RATIO + _number(&"burst_bonus"), 0.0, 3.0)


## 热量积累倍率：热量减缓每层 -50%，最低 0。
func heat_gain_multiplier() -> float:
	return clampf(1.0 - _number(&"heat_slow"), 0.0, 1.0)


## 过载惩罚时长倍率：过热缩短每层 -50%，最低 10%。
func overload_duration_multiplier() -> float:
	return clampf(1.0 - _number(&"overload_shorten"), 0.1, 1.0)


## 副作用减免（0~1），供自伤计算使用。
func side_effect_reduction() -> float:
	return clampf(_number(&"side_effect_reduction"), 0.0, 1.0)


## 暴击率加成。
func crit_bonus() -> float:
	return _number(&"crit_bonus")


## 指定元素词条的等级加成（元素亲和 + 对应元素遗物）。
func element_level_plus(element_id: StringName) -> int:
	var bonus: int = int(_number(&"element_level_plus"))
	for entry: Dictionary in _active_entries():
		var modifier: Dictionary = entry.get("modifier", {})
		if StringName(modifier.get(&"element_id", &"")) == element_id:
			bonus += int(float(modifier.get(&"element_level_plus", 0.0)))
	return bonus


## 反应效果加成（反应大师）。
func reaction_bonus() -> float:
	return _number(&"reaction_bonus")


## 持续时间加成（时间沙漏）。
func duration_bonus() -> float:
	return _number(&"duration_bonus")


## 光 + 暗反应加成（湮灭之种）。
func annihilation_bonus() -> float:
	return _number(&"annihilation_bonus")


## 炼金瞬间无敌时长。
func invuln_seconds() -> float:
	return maxf(_number(&"invuln_seconds"), 0.0)


func uninterruptible() -> bool:
	return _flag(&"uninterruptible")


func fire_guaranteed() -> bool:
	return _flag(&"fire_guaranteed")


func poison_safe() -> bool:
	return _flag(&"poison_safe")


func random_mutation() -> bool:
	return _flag(&"random_mutation")


func overload_material_safe() -> bool:
	return _flag(&"overload_material_safe")


func overload_no_weapon_disable() -> bool:
	return _flag(&"overload_no_weapon_disable")


func interrupt_no_heat() -> bool:
	return _flag(&"interrupt_no_heat")


func no_stun() -> bool:
	return _flag(&"no_stun")


func chaos_random() -> bool:
	return _flag(&"chaos_random")


func living_safe() -> bool:
	return _flag(&"living_safe")


func no_time_cost() -> bool:
	return _flag(&"no_time_cost")


## ── 存档 ────────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var upgrades: Dictionary = {}
	for id: Variant in _upgrade_levels.keys():
		upgrades[String(id)] = int(_upgrade_levels[id])
	var relics: Array[String] = []
	for id: StringName in owned_relics():
		relics.append(String(id))
	return {"upgrades": upgrades, "relics": relics}


func from_dict(data: Dictionary) -> void:
	_upgrade_levels.clear()
	_relics.clear()
	var upgrades: Dictionary = data.get("upgrades", {})
	for key: Variant in upgrades:
		var id: StringName = StringName(key)
		if ProgressionCatalog.has_upgrade(id):
			_upgrade_levels[id] = clampi(int(upgrades[key]), 0, ProgressionCatalog.max_level_of(id))
	for value: Variant in data.get("relics", []):
		var relic_id: StringName = StringName(value)
		if ProgressionCatalog.has_relic(relic_id):
			_relics[relic_id] = true


func reset() -> void:
	_upgrade_levels.clear()
	_relics.clear()
	changed.emit()
