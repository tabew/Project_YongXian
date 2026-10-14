class_name AlchemyBag
extends RefCounted

## 格子制材料背包：固定格数、按格堆叠、可锁定。
## 一种材料占一格并向上叠到该材料的堆叠上限；锁定格不会被消耗或覆盖。

signal changed

const DEFAULT_CAPACITY: int = 12
const EMPTY_SLOT: int = -1

var capacity: int = DEFAULT_CAPACITY
## 堆叠上限倍率：升级「堆叠上限 +20%」等抬高它；1.0 为基准。
var stack_multiplier: float = 1.0
## 每格：{"material_id": int, "amount": int, "locked": bool}
var slots: Array[Dictionary] = []

func _init(slot_capacity: int = DEFAULT_CAPACITY) -> void:
	capacity = maxi(slot_capacity, 1)
	for index: int in range(capacity):
		slots.append({"material_id": EMPTY_SLOT, "amount": 0, "locked": false})

## 扩容：升级“背包扩容 +2 格”等直接加格数。
func expand_by(extra_slots: int) -> int:
	if extra_slots <= 0:
		return capacity
	for index: int in range(extra_slots):
		slots.append({"material_id": EMPTY_SLOT, "amount": 0, "locked": false})
	capacity = slots.size()
	changed.emit()
	return capacity

## 放入材料，返回实际放进去的数量；背包满时返回值会小于 amount。
func add(material_id: int, amount: int) -> int:
	if material_id < 0 or amount <= 0:
		return 0
	var stack_limit: int = _stack_limit(material_id)
	var remaining: int = amount
	var added: int = 0
	# 先并入已有的未锁定同种格
	for slot: Dictionary in slots:
		if remaining <= 0:
			break
		if int(slot["material_id"]) != material_id or bool(slot["locked"]):
			continue
		var room: int = stack_limit - int(slot["amount"])
		if room <= 0:
			continue
		var put: int = mini(room, remaining)
		slot["amount"] = int(slot["amount"]) + put
		remaining -= put
		added += put
	# 再找空格
	for slot: Dictionary in slots:
		if remaining <= 0:
			break
		if int(slot["material_id"]) != EMPTY_SLOT:
			continue
		var put: int = mini(stack_limit, remaining)
		slot["material_id"] = material_id
		slot["amount"] = put
		remaining -= put
		added += put
	if added > 0:
		changed.emit()
	return added

## 消耗材料，返回实际扣掉的数量；锁定格不参与。
func remove(material_id: int, amount: int) -> int:
	if material_id < 0 or amount <= 0:
		return 0
	var remaining: int = amount
	var removed: int = 0
	for slot: Dictionary in slots:
		if remaining <= 0:
			break
		if int(slot["material_id"]) != material_id or bool(slot["locked"]):
			continue
		var take: int = mini(int(slot["amount"]), remaining)
		slot["amount"] = int(slot["amount"]) - take
		remaining -= take
		removed += take
		if int(slot["amount"]) <= 0:
			slot["material_id"] = EMPTY_SLOT
			slot["amount"] = 0
	if removed > 0:
		changed.emit()
	return removed

func count(material_id: int) -> int:
	var total: int = 0
	for slot: Dictionary in slots:
		if int(slot["material_id"]) == material_id:
			total += int(slot["amount"])
	return total

## 按格返回持有的材料 id（含重复），供素材槽按槽取用。
func material_ids() -> Array[int]:
	var ids: Array[int] = []
	for slot: Dictionary in slots:
		if int(slot["material_id"]) != EMPTY_SLOT and int(slot["amount"]) > 0:
			ids.append(int(slot["material_id"]))
	return ids

func used_slot_count() -> int:
	return material_ids().size()

func is_full() -> bool:
	return used_slot_count() >= capacity

func slot_at(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	return slots[index]

func set_locked(index: int, locked: bool) -> bool:
	if index < 0 or index >= slots.size():
		return false
	slots[index]["locked"] = locked
	changed.emit()
	return true

func is_locked(index: int) -> bool:
	if index < 0 or index >= slots.size():
		return false
	return bool(slots[index]["locked"])

## 过载惩罚：随机一种材料损失一半。
func lose_half_of_random_material(rng: RandomNumberGenerator) -> Dictionary:
	var ids: Array[int] = material_ids()
	if ids.is_empty():
		return {}
	var picked: int = ids[rng.randi_range(0, ids.size() - 1)]
	var owned: int = count(picked)
	var lost: int = ceili(float(owned) * AlchemyRules.OVERLOAD_MATERIAL_LOSS_RATIO)
	var removed: int = remove(picked, lost)
	return {"material_id": picked, "lost": removed} if removed > 0 else {}

func _stack_limit(material_id: int) -> int:
	var definition: Dictionary = MaterialCatalog.definition_of(material_id)
	if definition.is_empty():
		return 99
	var base: int = maxi(int(definition.get("max_stack", 99)), 1)
	# 向下取整，保证 99 这类基数在 +20% 时仍落在整数堆叠上。
	return maxi(int(floor(float(base) * maxf(stack_multiplier, 0.1))), 1)
