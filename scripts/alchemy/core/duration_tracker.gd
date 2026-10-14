class_name DurationTracker
extends RefCounted

## 效果持续时间：按秒倒计时；非战斗与慢动作中暂停。
## 相同组合叠加用 extend 累加时间，不重置已经走过的时间。

var total: float = 0.0
var remaining: float = 0.0
var active: bool = false

func start(duration: float) -> void:
	total = maxf(duration, 0.0)
	remaining = total
	active = remaining > 0.0

## 相同组合叠加：时间相加，无硬上限。
func extend(duration: float) -> void:
	var extra: float = maxf(duration, 0.0)
	total += extra
	remaining += extra
	if remaining > 0.0:
		active = true

## 推进倒计时；paused 为真（非战斗 / 慢动作）时冻结。返回本次是否刚好结束。
func tick(delta: float, paused: bool) -> bool:
	if not active or paused:
		return false
	remaining = maxf(remaining - delta, 0.0)
	if remaining > 0.0:
		return false
	active = false
	return true

func clear() -> void:
	total = 0.0
	remaining = 0.0
	active = false

func is_active() -> bool:
	return active and remaining > 0.0

func ratio() -> float:
	return remaining / total if total > 0.0 else 0.0
