
class_name BuffHolder
extends Node

## 一个实体（玩家/怪物/训练靶）身上的 buff 容器，挂成实体的直接子节点（约定名字 "Buffs"）。
##
## 宿主需要实现两个接口（没实现就只做计时与定时效果，不碰属性）：
##   read_stat(stat: StringName) -> float            读当前属性值
##   apply_stat(stat: StringName, value: float)      把算好的值写回属性
##
## 基准值规则（先认领、再算、最后记录）：
##   current = 读当前值
##   current 不等于"上次自己写回的值" → 说明别的系统改过它，把 current 认成新基准
##   计算永远只从基准出发（所以不会把 buff 反复叠乘上去），写回后再记录自己写了什么

signal buff_applied(buff: BuffData)
signal buff_upgraded(buff: BuffData)
signal buff_expired(buff: BuffData)
##buff 集合发生变化（UI 重建用）
signal changed()
##属性被写回（调试用）
signal stats_changed()

var _active: Array[Dictionary] = []
var _base: Dictionary = {}
var _written: Dictionary = {}


func _ready() -> void:
	set_physics_process(false)
	var host: Node = get_parent()
	if host == null:
		return
	#死亡清空：玩家是 defeated，怪物/训练靶是 Health.died
	if host.has_signal("defeated"):
		host.connect("defeated", _on_host_defeated)
	var health: Node = host.get_node_or_null("Health")
	if health != null and health.has_signal("died"):
		health.connect("died", _on_health_died)
	#新世界清空
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("world_ready") and not bus.world_ready.is_connected(_on_world_ready):
		bus.world_ready.connect(_on_world_ready)


##施加一个 buff：同一个 id 只保留一份，取最高级
##新等级更高 → 升级并刷新时长；等级更低 → 什么都不做（返回 false）
func apply(buff: BuffData, level: int = 1, source: Node = null) -> bool:
	if buff == null or buff.id == &"":
		return false
	var wanted: int = clampi(level, 1, maxi(buff.max_level, 1))
	var entry: Dictionary = _find(buff.id)

	if not entry.is_empty():
		if wanted < int(entry["level"]):
			return false
		entry["level"] = wanted
		entry["remaining"] = buff.duration
		entry["source"] = source
		_recompute_all()
		buff_upgraded.emit(buff)
		changed.emit()
		return true

	_active.append({
		"buff": buff,
		"level": wanted,
		"remaining": buff.duration,
		"tick": buff.tick_interval,
		"source": source,
	})
	set_physics_process(true)
	_recompute_all()
	buff_applied.emit(buff)
	changed.emit()
	return true


func remove(id: StringName) -> bool:
	var entry: Dictionary = _find(id)
	if entry.is_empty():
		return false
	var buff: BuffData = entry["buff"]
	_active.erase(entry)
	_recompute_all()
	buff_expired.emit(buff)
	changed.emit()
	return true


func clear() -> void:
	if _active.is_empty():
		return
	var expired: Array = []
	for entry in _active:
		expired.append(entry["buff"])
	_active.clear()
	set_physics_process(false)
	_recompute_all()
	for buff: BuffData in expired:
		buff_expired.emit(buff)
	changed.emit()


func has(id: StringName) -> bool:
	return not _find(id).is_empty()


func get_level(id: StringName) -> int:
	var entry: Dictionary = _find(id)
	return int(entry["level"]) if not entry.is_empty() else 0


func get_remaining(id: StringName) -> float:
	var entry: Dictionary = _find(id)
	return float(entry["remaining"]) if not entry.is_empty() else 0.0


##给 UI 的一份快照
func get_display_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _active:
		var buff: BuffData = entry["buff"]
		var duration: float = buff.duration
		var remaining: float = float(entry["remaining"])
		result.append({
			"buff": buff,
			"level": int(entry["level"]),
			"remaining": remaining,
			"ratio": clampf(remaining / duration, 0.0, 1.0) if duration > 0.0 else 1.0,
		})
	return result


func _physics_process(delta: float) -> void:
	if _active.is_empty():
		return
	var expired: Array = []
	for entry in _active:
		var buff: BuffData = entry["buff"]
		#定时效果：刷新时长不重置相位，所以持续恢复不会被无限刷新成永不触发
		if buff.has_tick():
			var left: float = float(entry["tick"]) - delta
			if left <= 0.0:
				entry["tick"] = buff.tick_interval
				_tick(entry)
			else:
				entry["tick"] = left
		if buff.duration > 0.0:
			var remaining: float = float(entry["remaining"]) - delta
			entry["remaining"] = remaining
			if remaining <= 0.0:
				expired.append(entry)
	for entry in expired:
		_active.erase(entry)
		buff_expired.emit(entry["buff"])
	if not expired.is_empty():
		_recompute_all()
		changed.emit()
	if _active.is_empty():
		set_physics_process(false)


##定时效果：扣血优先走宿主的 take_damage（玩家），否则走 Health.receive_hit；
##回血优先走宿主的 heal()（玩家），否则直接补给 HealthComponent
func _tick(entry: Dictionary) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var buff: BuffData = entry["buff"]
	var level: int = int(entry["level"])
	var health: Node = host.get_node_or_null("Health")
	var damage: float = buff.damage_amount(level)

	if damage > 0.0:
		if host.has_method("take_damage"):
			host.call("take_damage", damage)
		elif health != null and health.has_method("receive_hit"):
			var hit: CombatHit = CombatHit.new()
			hit.damage = damage
			if host is Node2D:
				hit.position = (host as Node2D).global_position
			health.call("receive_hit", hit)

	var heal: float = buff.heal_amount(level)

	if heal > 0.0:
		if host.has_method("heal"):
			host.call("heal", heal)
		elif health != null:
			var maximum: float = float(health.get("max_health"))
			var current: float = float(health.get("current_health"))
			if current > 0.0:
				health.set("current_health", minf(current + heal, maximum))
				if health.has_signal("health_changed"):
					health.emit_signal("health_changed", health.get("current_health"), maximum)


func _recompute_all() -> void:
	var stats: Dictionary = {}
	for entry in _active:
		var buff: BuffData = entry["buff"]
		for modifier: StatModifier in buff.modifiers:
			if modifier != null:
				stats[modifier.stat] = true
	#到期还原：上次写过的也要重算一遍
	for stat: StringName in _written.keys():
		stats[stat] = true
	var wrote: bool = false
	for stat: StringName in stats.keys():
		wrote = _rewrite(stat) or wrote
	if wrote:
		stats_changed.emit()


##先认领、再算、最后记录。返回 true 表示确实写回了属性
func _rewrite(stat: StringName) -> bool:
	var host: Node = get_parent()
	if host == null or not host.has_method("read_stat") or not host.has_method("apply_stat"):
		return false
	var current: float = float(host.call("read_stat", stat))
	if not _written.has(stat) or not is_equal_approx(current, float(_written[stat])):
		_base[stat] = current
	var value: float = _compute(stat, float(_base.get(stat, current)))
	host.call("apply_stat", stat, value)
	_written[stat] = float(host.call("read_stat", stat))
	return true


##基准值 + 全部生效 buff 的修改：先加算、再百分比、最后叠乘
func _compute(stat: StringName, base_value: float) -> float:
	var flat: float = 0.0
	var percent: float = 0.0
	var multiplier: float = 1.0
	for entry in _active:
		var buff: BuffData = entry["buff"]
		var level: int = int(entry["level"])
		for modifier: StatModifier in buff.modifiers:
			if modifier == null or modifier.stat != stat:
				continue
			var amount: float = modifier.amount(level)
			match modifier.mode:
				StatModifier.Mode.FLAT:
					flat += amount
				StatModifier.Mode.PERCENT_ADD:
					percent += amount
				StatModifier.Mode.MULTIPLY:
					multiplier *= 1.0 + amount
	return (base_value + flat) * (1.0 + percent) * multiplier


func _find(id: StringName) -> Dictionary:
	for entry in _active:
		var buff: BuffData = entry["buff"]
		if buff != null and buff.id == id:
			return entry
	return {}


##外部系统改完属性后，显式让这一格重新认基准
func refresh_base(stat: StringName) -> void:
	_written.erase(stat)
	_rewrite(stat)


func _on_host_defeated() -> void:
	clear()


func _on_health_died(_hit: CombatHit = null) -> void:
	clear()


func _on_world_ready(_seed_value: int = 0) -> void:
	clear()
