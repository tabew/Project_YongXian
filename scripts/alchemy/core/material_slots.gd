class_name MaterialSlots
extends RefCounted

## 素材槽：默认 2 格，遗物 / 升级可扩到 3~4 格。
## 每格只放 1 种材料（材料 id），实际数量由 AlchemyBag 统一持有。

signal changed

const EMPTY: int = -1

var slots: Array[int] = []

func _init(count: int = AlchemyRules.DEFAULT_MATERIAL_SLOTS) -> void:
	var total: int = clampi(count, 1, AlchemyRules.MAX_MATERIAL_SLOTS)
	for index: int in range(total):
		slots.append(EMPTY)

func slot_count() -> int:
	return slots.size()

## 扩容素材槽，上限 AlchemyRules.MAX_MATERIAL_SLOTS。
func expand_by(extra: int) -> int:
	var target: int = clampi(slots.size() + extra, 1, AlchemyRules.MAX_MATERIAL_SLOTS)
	while slots.size() < target:
		slots.append(EMPTY)
	changed.emit()
	return slots.size()

## 往指定格放材料；格子越界返回 false。
func place(index: int, material_id: int) -> bool:
	if index < 0 or index >= slots.size() or material_id < 0:
		return false
	slots[index] = material_id
	changed.emit()
	return true

## 放进第一个空格；没有空格返回 -1。
func place_first_free(material_id: int) -> int:
	for index: int in range(slots.size()):
		if slots[index] == EMPTY:
			slots[index] = material_id
			changed.emit()
			return index
	return -1

func clear_slot(index: int) -> void:
	if index < 0 or index >= slots.size() or slots[index] == EMPTY:
		return
	slots[index] = EMPTY
	changed.emit()

func clear_all() -> void:
	var dirty: bool = false
	for index: int in range(slots.size()):
		if slots[index] != EMPTY:
			slots[index] = EMPTY
			dirty = true
	if dirty:
		changed.emit()

func material_at(index: int) -> int:
	if index < 0 or index >= slots.size():
		return EMPTY
	return slots[index]

## 按槽返回材料 id（含重复）；同一个材料放两格会算两份层数。
func material_ids() -> Array[int]:
	var ids: Array[int] = []
	for material_id: int in slots:
		if material_id != EMPTY:
			ids.append(material_id)
	return ids

func unique_ids() -> Array[int]:
	var ids: Array[int] = []
	for material_id: int in material_ids():
		if not ids.has(material_id):
			ids.append(material_id)
	return ids

func is_empty() -> bool:
	return material_ids().is_empty()

func has_free_slot() -> bool:
	return slots.has(EMPTY)
