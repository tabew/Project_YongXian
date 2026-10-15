class_name MonsterDifficulty
extends RefCounted

## 每次进入有敌人预算的房间推进一档；前七档遵循固定增量，之后用自然对数平滑续接。
const EARLY_MULTIPLIERS := [1.0, 1.5, 2.0, 2.4, 2.8, 3.1, 3.4]
const LOG_GAIN: float = 0.7
const LOG_SPAN: float = 3.0


static func multiplier_for_entry(entry: int) -> float:
	var index: int = maxi(entry, 1)
	if index <= EARLY_MULTIPLIERS.size():
		return EARLY_MULTIPLIERS[index - 1]
	return EARLY_MULTIPLIERS.back() + LOG_GAIN * log(1.0 + float(index - EARLY_MULTIPLIERS.size()) / LOG_SPAN)
