class_name BrewPresets
extends RefCounted

## 快速预设：把一套素材槽布局存下来，之后一键复原。
## 只保存材料 id 序列与查询逻辑，不碰背包 / 素材槽实例；实际取用材料由 AlchemyStation 负责。
##
## 预设格数由升级「快速预设 +1」决定：基础 1 格，最多 3 层升级 → 4 格。

const BASE_SLOT_COUNT: int = 1
const MAX_SLOT_COUNT: int = 4
## 一个预设最多记几种材料，与素材槽上限一致。
const MAX_MATERIALS_PER_PRESET: int = AlchemyRules.MAX_MATERIAL_SLOTS

signal changed

var slot_count: int = BASE_SLOT_COUNT
## 每个元素是一组材料 id（去重保序）。
var _presets: Array = []

func _init(count: int = BASE_SLOT_COUNT) -> void:
	slot_count = clampi(count, 0, MAX_SLOT_COUNT)
	for _index: int in range(slot_count):
		_presets.append([])

## 升级「快速预设 +1」时扩容；缩容会丢弃超出部分。
func set_slot_count(count: int) -> void:
	var clamped: int = clampi(count, 0, MAX_SLOT_COUNT)
	if clamped == slot_count:
		return
	while _presets.size() < clamped:
		_presets.append([])
	while _presets.size() > clamped:
		_presets.remove_at(_presets.size() - 1)
	slot_count = clamped
	changed.emit()

func preset_count() -> int:
	return _presets.size()

## 第 index 个预设的材料 id 序列（副本）。
func preset_at(index: int) -> Array[int]:
	var result: Array[int] = []
	if index < 0 or index >= _presets.size():
		return result
	for id: Variant in _presets[index]:
		result.append(int(id))
	return result

func is_empty(index: int) -> bool:
	return preset_at(index).is_empty()

## 存预设：去重保序，最多 MAX_MATERIALS_PER_PRESET 种；越界返回 false。
func store(index: int, material_ids: Array[int]) -> bool:
	if index < 0 or index >= _presets.size():
		return false
	var unique: Array[int] = []
	for id: int in material_ids:
		if id < 0 or unique.has(id):
			continue
		unique.append(id)
		if unique.size() >= MAX_MATERIALS_PER_PRESET:
			break
	_presets[index] = unique
	changed.emit()
	return true

func clear(index: int) -> bool:
	if index < 0 or index >= _presets.size() or (_presets[index] as Array).is_empty():
		return false
	_presets[index] = []
	changed.emit()
	return true

func clear_all() -> void:
	for index: int in range(_presets.size()):
		_presets[index] = []
	changed.emit()

## 预设需要的材料 id → 数量（每个素材槽 1 个）。
func requirements(index: int) -> Dictionary:
	var result: Dictionary = {}
	for id: int in preset_at(index):
		result[id] = int(result.get(id, 0)) + 1
	return result

## 背包里的材料是否够用；available 为 id → 数量。
func can_apply(index: int, available: Dictionary) -> bool:
	if is_empty(index):
		return false
	for id: int in requirements(index):
		if int(available.get(id, 0)) < int(requirements(index)[id]):
			return false
	return true

## 第一个空预设的下标；没有空位返回 -1。
func first_empty_index() -> int:
	for index: int in range(_presets.size()):
		if (_presets[index] as Array).is_empty():
			return index
	return -1
