class_name MonsterLootTable
extends Resource

## 非空有效表在真正死亡时必掉一件，权重归一化后共用同一次抽样。
@export var items: Array[IngredientData] = []
@export var weights: PackedFloat32Array = []

func choose_for_roll(roll: float) -> IngredientData:
	var total: float = 0.0
	var last: IngredientData = null
	for index: int in mini(items.size(), weights.size()):
		if items[index] != null and weights[index] > 0.0:
			total += weights[index]
			last = items[index]
	if total <= 0.0:
		return null
	var target: float = clampf(roll, 0.0, 1.0) * total
	var cumulative: float = 0.0
	for index: int in mini(items.size(), weights.size()):
		if items[index] == null or weights[index] <= 0.0:
			continue
		cumulative += weights[index]
		if target < cumulative:
			return items[index]
	return last
