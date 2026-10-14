extends SceneTree

## 材料背包单元测试：格子制、堆叠、锁定、扩容、过载损失。

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	_test_defaults()
	_test_stacking()
	_test_capacity()
	_test_remove()
	_test_locking()
	_test_expand()
	_test_overload_loss()
	_test_stack_multiplier()
	print("ALCHEMY BAG: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 堆叠上限倍率：升级「堆叠上限 +20%」直接抬高单格容量。
func _test_stack_multiplier() -> void:
	var base: AlchemyBag = AlchemyBag.new()
	base.add(1001, 99)
	_check(int(base.slots[0]["amount"]) == 99, "基准单格堆到 99")
	var doubled: AlchemyBag = AlchemyBag.new()
	doubled.stack_multiplier = 2.0
	doubled.add(1001, 200)
	_check(int(doubled.slots[0]["amount"]) == 198, "堆叠倍率 2.0 把单格上限抬到 198")
	var halved: AlchemyBag = AlchemyBag.new()
	halved.stack_multiplier = 0.5
	halved.add(1001, 500)
	_check(int(halved.slots[0]["amount"]) == 49, "堆叠倍率 0.5 把单格上限压到 49")
	_check(halved.count(1001) == 500, "压低上限后材料仍能分格放下")

func _test_defaults() -> void:
	var bag: AlchemyBag = AlchemyBag.new()
	_check(bag.capacity == AlchemyBag.DEFAULT_CAPACITY, "默认背包 12 格")
	_check(bag.slots.size() == 12, "初始化 12 个空格")
	_check(bag.used_slot_count() == 0, "初始没有占用格子")
	_check(bag.count(1001) == 0, "初始没有材料")
	_check(bag.material_ids().is_empty(), "初始材料 id 列表为空")
	_check(bag.slot_at(0).get("material_id", -2) == AlchemyBag.EMPTY_SLOT, "空格是 -1")
	_check(bag.slot_at(99).is_empty(), "越界取格返回空字典")

func _test_stacking() -> void:
	var bag: AlchemyBag = AlchemyBag.new()
	_check(bag.add(1001, 30) == 30, "放入 30 个毒菇")
	_check(bag.count(1001) == 30, "数量累计正确")
	_check(bag.used_slot_count() == 1, "同种材料占一格")
	# 水银堆叠上限 20：25 个要占两格。
	_check(bag.add(1021, 25) == 25, "放入 25 个水银")
	_check(bag.used_slot_count() == 3, "超过堆叠上限自动另开一格")
	_check(bag.count(1021) == 25, "跨格数量累计正确")
	_check(bag.add(-1, 5) == 0, "非法材料 id 放不进去")
	_check(bag.add(1001, 0) == 0, "数量为 0 不放")

func _test_capacity() -> void:
	var bag: AlchemyBag = AlchemyBag.new(1)
	_check(bag.add(1001, 50) == 50, "单格背包放入 50 个")
	_check(bag.is_full(), "没有空格即视为满")
	_check(bag.add(1001, 60) == 49, "仍能叠进已有的未满格")
	_check(bag.count(1001) == 99, "叠到该材料的堆叠上限 99")
	_check(bag.add(1002, 5) == 0, "无空格且无法叠加时放不下")

func _test_remove() -> void:
	var bag: AlchemyBag = AlchemyBag.new()
	bag.add(1001, 30)
	_check(bag.remove(1001, 10) == 10, "消耗 10 个")
	_check(bag.count(1001) == 20, "消耗后剩余 20")
	_check(bag.remove(1001, 999) == 20, "超量消耗只扣现有数量")
	_check(bag.count(1001) == 0, "清空后数量为 0")
	_check(bag.used_slot_count() == 0, "清空的格自动回收")
	_check(bag.remove(1001, 5) == 0, "没有的材料消耗 0")

func _test_locking() -> void:
	var bag: AlchemyBag = AlchemyBag.new()
	bag.add(1001, 10)
	_check(bag.set_locked(0, true), "锁定第 0 格")
	_check(bag.is_locked(0), "读取锁定状态")
	_check(bag.remove(1001, 5) == 0, "锁定格不参与消耗")
	_check(bag.count(1001) == 10, "锁定材料数量不变")
	_check(bag.add(1001, 5) == 5, "锁定格不能并入，另开一格")
	_check(bag.count(1001) == 15, "新格正常累计")
	_check(not bag.set_locked(99, true), "越界锁定失败")
	_check(not bag.is_locked(99), "越界读取锁定为假")

func _test_expand() -> void:
	var bag: AlchemyBag = AlchemyBag.new()
	_check(bag.expand_by(3) == 15, "扩容 +3 格")
	_check(bag.slots.size() == 15, "格子数组同步增长")
	_check(bag.expand_by(0) == 15, "扩容 0 格不变")
	_check(bag.expand_by(-2) == 15, "负数扩容不变")

func _test_overload_loss() -> void:
	var bag: AlchemyBag = AlchemyBag.new()
	_check(bag.lose_half_of_random_material(RandomNumberGenerator.new()).is_empty(), "空背包没有材料可损失")
	bag.add(1001, 10)
	bag.add(1002, 8)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var report: Dictionary = bag.lose_half_of_random_material(rng)
	_check(not report.is_empty(), "过载随机损失一种材料")
	_check(int(report["lost"]) == 5 or int(report["lost"]) == 4, "损失量是该材料的一半（向上取整）")
	_check(bag.count(int(report["material_id"])) < 10, "被选中的材料数量下降")
