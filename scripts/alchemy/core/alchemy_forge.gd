class_name AlchemyForge
extends RefCounted

## 非战斗合金 / 重铸：把背包里的材料转换成另一种材料。
##
## 合金：两种同品质材料熔成一件更高品质材料（品质 +1），候选按「共享词条数」加权。
## 重铸：一件材料换成同品质的另一种材料，同样按共享词条加权。
## 纯逻辑，只读 MaterialCatalog，不碰背包实例；消耗由 AlchemyStation 负责。

## 合金消耗：两种材料各 1 个。
const ALLOY_COST_PER_MATERIAL: int = 1
## 重铸消耗：1 个材料。
const REFORGE_COST: int = 1
## 最高品质（传说），无法再合金。
const MAX_ALLOY_QUALITY: int = 3

signal changed

## 当前选中的合金 / 重铸材料（供非战斗面板展示与确认）。
var alloy_selection: Array[int] = []
var reforge_selection: int = -1


## ── 合金 ────────────────────────────────────────────────────────────────

## 两种材料能否合金：都是炼金材料、id 不同、同品质且未到最高品质。
static func can_alloy(a: int, b: int) -> bool:
	if a == b or not MaterialCatalog.has_material(a) or not MaterialCatalog.has_material(b):
		return false
	var quality_a: int = quality_of(a)
	if quality_a != quality_of(b) or quality_a >= MAX_ALLOY_QUALITY:
		return false
	return not alloy_candidates(a, b).is_empty()


## 合金产物候选：品质 +1、与任一原料共享至少一个词条 id 的材料。
static func alloy_candidates(a: int, b: int) -> Array[int]:
	var target_quality: int = quality_of(a) + 1
	var shared: Array[StringName] = _trait_ids(a) + _trait_ids(b)
	var result: Array[int] = []
	for id: int in MaterialCatalog.all_ids():
		if quality_of(id) != target_quality:
			continue
		for trait_id: StringName in _trait_ids(id):
			if shared.has(trait_id):
				result.append(id)
				break
	return result


## 按共享词条数加权抽取合金产物；无法合金返回 -1。
static func alloy(a: int, b: int, rng: RandomNumberGenerator) -> int:
	if not can_alloy(a, b):
		return -1
	var candidates: Array[int] = alloy_candidates(a, b)
	var shared: Array[StringName] = _trait_ids(a) + _trait_ids(b)
	return _weighted_pick(candidates, shared, rng)


## ── 重铸 ────────────────────────────────────────────────────────────────

## 同品质的其它材料（重铸候选）。
static func reforge_candidates(material_id: int) -> Array[int]:
	if not MaterialCatalog.has_material(material_id):
		return []
	var quality: int = quality_of(material_id)
	var result: Array[int] = []
	for id: int in MaterialCatalog.all_ids():
		if id != material_id and quality_of(id) == quality:
			result.append(id)
	return result


static func can_reforge(material_id: int) -> bool:
	return not reforge_candidates(material_id).is_empty()


## 按共享词条数加权抽取同品质的另一种材料；无法重铸返回 -1。
static func reforge(material_id: int, rng: RandomNumberGenerator) -> int:
	var candidates: Array[int] = reforge_candidates(material_id)
	if candidates.is_empty():
		return -1
	return _weighted_pick(candidates, _trait_ids(material_id), rng)


## ── 选择状态（非战斗面板用）──────────────────────────────────────────

## 选 / 取消一种合金原料；最多两种，重复点击同一种会取消。
func toggle_alloy_material(material_id: int) -> bool:
	if not MaterialCatalog.has_material(material_id):
		return false
	var index: int = alloy_selection.find(material_id)
	if index >= 0:
		alloy_selection.remove_at(index)
	elif alloy_selection.size() < 2:
		alloy_selection.append(material_id)
	else:
		alloy_selection = [alloy_selection[1], material_id]
	changed.emit()
	return true


func clear_alloy_selection() -> void:
	if alloy_selection.is_empty():
		return
	alloy_selection.clear()
	changed.emit()


func alloy_ready() -> bool:
	return alloy_selection.size() == 2 and can_alloy(alloy_selection[0], alloy_selection[1])


func set_reforge_material(material_id: int) -> bool:
	if not MaterialCatalog.has_material(material_id):
		return false
	reforge_selection = material_id
	changed.emit()
	return true


func reforge_ready() -> bool:
	return reforge_selection >= 0 and can_reforge(reforge_selection)


## ── 内部 ────────────────────────────────────────────────────────────────

static func quality_of(material_id: int) -> int:
	return int(MaterialCatalog.definition_of(material_id).get("quality", 0))


## 材料的词条 id 列表。
static func _trait_ids(material_id: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Variant in MaterialCatalog.definition_of(material_id).get("traits", []):
		if entry is Dictionary:
			ids.append(StringName((entry as Dictionary).get("id", &"")))
	return ids


## 按「与参考词条共享的数量」加权抽取；全无共享时等概率。
static func _weighted_pick(candidates: Array[int], reference: Array[StringName], rng: RandomNumberGenerator) -> int:
	var weights: Array[float] = []
	var total: float = 0.0
	for id: int in candidates:
		var weight: float = 1.0
		for trait_id: StringName in _trait_ids(id):
			if reference.has(trait_id):
				weight += 2.0
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var roll: float = rng.randf() * total
	for index: int in range(candidates.size()):
		roll -= weights[index]
		if roll <= 0.0:
			return candidates[index]
	return candidates[candidates.size() - 1]
