class_name InspirationRun
extends RefCounted

## 一局游戏内的灵感账本（纯逻辑）。
## 负责累计来源、死亡结算（损失 + 留存）与通关结算（贤者之石）。

## 局内已获得的灵感（光点飞入后才计入）。
var gained: int = 0
## 还在飞的光点金额（尚未计入 gained）。
var in_flight: int = 0
## 来源统计：Source -> 数量。
var by_source: Dictionary = {}


func reset() -> void:
	gained = 0
	in_flight = 0
	by_source.clear()


## 掉落产生：先进入"飞行中"，光点飞入后再 collect。
func launch(amount: int, source: int) -> int:
	var value: int = maxi(amount, 0)
	if value <= 0:
		return 0
	in_flight += value
	by_source[source] = int(by_source.get(source, 0)) + value
	return value


## 光点飞入：从"飞行中"转入已获得。
func collect(amount: int) -> int:
	var value: int = clampi(amount, 0, in_flight)
	in_flight -= value
	gained += value
	return value


func total_launched() -> int:
	return gained + in_flight


func source_total(source: int) -> int:
	return int(by_source.get(source, 0))


## 死亡：损失所有局内灵感，按留存等级保留少量。
func death(retention_level: int) -> Dictionary:
	var result: Dictionary = InspirationRules.death_split(gained, retention_level)
	result["discarded_in_flight"] = in_flight
	gained = int(result["kept"])
	in_flight = 0
	return result


## 通关：贤者之石结算。材料 counts 为 {quality: 数量}。
func settle(material_counts: Dictionary, difficulty_tier: int, performance_bonus: int = 0, codex_completion: float = 0.0, boss_material_count: int = 0) -> Dictionary:
	var result: Dictionary = InspirationRules.settlement(
		gained, material_counts, difficulty_tier, performance_bonus, codex_completion, boss_material_count
	)
	result["by_source"] = by_source.duplicate()
	return result
