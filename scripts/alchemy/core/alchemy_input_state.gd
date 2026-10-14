class_name AlchemyInputState
extends RefCounted

## 按 E 状态机（纯逻辑，不读输入、不碰场景树）：
## 非战斗按 E 立刻完全暂停打开完整炼金台；战斗中短按重复上次配方，长按进入慢动作轮盘。
## 受击打断与 Esc 只改状态，材料与时间由炼金台决定。

enum Phase { IDLE, CHARGING, MENU, WHEEL, COOLDOWN }

signal menu_opened
signal menu_closed
signal wheel_opened
signal wheel_closed
signal recipe_repeated
signal interrupted
signal phase_changed(phase: int)

var phase: int = Phase.IDLE
var in_combat: bool = false
var charge_time: float = 0.0
var cooldown_remaining: float = 0.0
## 短按 E 之后的动作硬直剩余时间；遗物「快速之手」把 stun_enabled 设为 false。
var stun_remaining: float = 0.0
var stun_enabled: bool = true

func is_menu_open() -> bool:
	return phase == Phase.MENU

func is_wheel_open() -> bool:
	return phase == Phase.WHEEL

## 只有轮盘需要慢动作；短按重复配方不暂停。
func is_slow_motion() -> bool:
	return phase == Phase.WHEEL

func press() -> void:
	if phase == Phase.COOLDOWN or phase == Phase.MENU or phase == Phase.CHARGING or phase == Phase.WHEEL:
		return
	if stun_remaining > 0.0:
		return
	if not in_combat:
		_set_phase(Phase.MENU)
		menu_opened.emit()
		return
	charge_time = 0.0
	_set_phase(Phase.CHARGING)

func release() -> void:
	match phase:
		Phase.CHARGING:
			_set_phase(Phase.IDLE)
			if stun_enabled:
				stun_remaining = AlchemyRules.SHORT_PRESS_STUN
			recipe_repeated.emit()
		Phase.WHEEL:
			_set_phase(Phase.IDLE)
			wheel_closed.emit()
		_:
			pass

func tick(delta: float) -> void:
	stun_remaining = maxf(stun_remaining - delta, 0.0)
	match phase:
		Phase.COOLDOWN:
			cooldown_remaining = maxf(cooldown_remaining - delta, 0.0)
			if cooldown_remaining <= 0.0:
				_set_phase(Phase.IDLE)
		Phase.CHARGING:
			charge_time += delta
			if charge_time >= AlchemyRules.LONG_PRESS_SECONDS:
				_set_phase(Phase.WHEEL)
				wheel_opened.emit()
		_:
			pass

## 受击打断：关轮盘、取消蓄力、材料不丢，进入 1 秒冷却。
func interrupt() -> bool:
	if phase != Phase.CHARGING and phase != Phase.WHEEL:
		return false
	var was_wheel: bool = phase == Phase.WHEEL
	cooldown_remaining = AlchemyRules.INTERRUPT_COOLDOWN
	_set_phase(Phase.COOLDOWN)
	if was_wheel:
		wheel_closed.emit()
	interrupted.emit()
	return true

## Esc：关闭炼金台 / 轮盘，不消耗材料。
func close() -> bool:
	match phase:
		Phase.MENU:
			_set_phase(Phase.IDLE)
			menu_closed.emit()
			return true
		Phase.WHEEL:
			_set_phase(Phase.IDLE)
			wheel_closed.emit()
			return true
		Phase.CHARGING:
			_set_phase(Phase.IDLE)
			return true
		_:
			return false

func _set_phase(value: int) -> void:
	if phase == value:
		return
	phase = value
	phase_changed.emit(phase)
