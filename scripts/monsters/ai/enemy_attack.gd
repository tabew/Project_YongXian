class_name EnemyAttack
extends RefCounted

## 统一攻击接口。怪物只需要实现"能不能打"和"怎么打"，
## 状态转换、冷却计时、丢失视野处理仍然由 EnemyBrain 统一负责。

## 攻击实现自带的有效距离；返回 <= 0 时使用 EnemyAIConfig.attack_range_tiles。
func attack_range() -> float:
	return 0.0


## 成功出手后的冷却。
func attack_cooldown() -> float:
	return 0.0


## 出手失败（例如没有弹药、落点不可达）后的短重试冷却；0 表示不设冷却。
func failed_attack_cooldown() -> float:
	return 0.0


func setup(_host: BaseMonster, _ai_config: EnemyAIConfig) -> void:
	pass


## 当前是否满足出手条件（距离/视线之外的前置条件）。不包含冷却。
func can_attack(_host: BaseMonster, _target: Node2D) -> bool:
	return false


## 真正出手。返回 true 表示动作已开始。
func perform_attack(_host: BaseMonster, _target: Node2D) -> bool:
	return false


## 攻击动作（前摇/后摇/跳跃）是否正在占用怪物；占用时状态机暂停决策。
func is_busy() -> bool:
	return false


func update(_host: BaseMonster, _delta: float) -> void:
	pass


## 进入 / 离开 Attack 状态时调用，用于重置出手意图。
func set_attacking(_value: bool) -> void:
	pass


## 被打断（受击、丢失目标）时调用，用于取消正在进行的动作。
func cancel(_host: BaseMonster) -> void:
	pass
