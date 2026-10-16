
class_name Buffs
extends RefCounted

## 施加 buff 的唯一入口。炼金属性、道具、怪物攻击、事件系统都用它，
## 目标可以是实体本身（玩家/怪物/训练靶）
## 找不到就返回 false，调用方不用关心目标有没有 buff 容器。

##buff 容器在实体下的约定名字
const HOLDER_NAME: String = "Buffs"

##隐身标记：宿主实现 set_buff_flag(&"invisible", active) 时生效
const FLAG_INVISIBLE: StringName = &"invisible"
##玩家隐身时的透明度
const INVISIBLE_ALPHA: float = 0.35
##怪物/训练靶隐身时的透明度：完全不可见
const HIDDEN_ALPHA: float = 0.0
##出手后至少显形多久（秒）
const REVEAL_SECONDS: float = 3
##伤害吸收标记：持有期间受到的伤害被反转成回复
const FLAG_ABSORB: StringName = &"damage_absorb"
##荆棘标记：持有期间受到伤害会反伤，反伤比例按 buff 等级放大
const FLAG_THORNS: StringName = &"thorns"
##荆棘每级反伤比例（占承受伤害的比例）
const THORNS_RATIO_PER_LEVEL: float = 0.35
##反伤命中的来源标识
const THORNS_WEAPON_ID: StringName = &"thorns"
##反伤链的最大深度
const THORNS_MAX_DEPTH: int = 0
##第几次反伤，记在 CombatHit 的 metadata 上（原始命中没有这个键，视作 0）
const THORNS_DEPTH_META: StringName = &"thorns_depth"

##取目标身上的 buff 容器
static func holder_of(target: Node) -> BuffHolder:
	if target == null or not is_instance_valid(target):
		return null
	if target is BuffHolder:
		return target as BuffHolder
	var named: Node = target.get_node_or_null(HOLDER_NAME)
	if named is BuffHolder:
		return named as BuffHolder
	for child: Node in target.get_children():
		if child is BuffHolder:
			return child as BuffHolder
	return null


##施加一个 buff：同 id 取最高级（升级并刷新时长），等级低于现有则不做处理
##施加一个 buff：同 id 取最高级（0 级是基础数值，逐级递增）
static func apply(target: Node, buff: BuffData, level: int = 0, source: Node = null) -> bool:
	var holder: BuffHolder = holder_of(target)
	if holder == null:
		return false
	return holder.apply(buff, level, source)


static func remove(target: Node, id: StringName) -> bool:
	var holder: BuffHolder = holder_of(target)
	return holder.remove(id) if holder != null else false


static func clear(target: Node) -> void:
	var holder: BuffHolder = holder_of(target)
	if holder != null:
		holder.clear()


static func has(target: Node, id: StringName) -> bool:
	var holder: BuffHolder = holder_of(target)
	return holder.has(id) if holder != null else false


static func display_list(target: Node) -> Array[Dictionary]:
	var holder: BuffHolder = holder_of(target)
	return holder.get_display_list() if holder != null else []


##驱散目标身上所有减益（is_debuff 的 buff），返回清掉几个
static func clear_debuffs(target: Node) -> int:
	var holder: BuffHolder = holder_of(target)
	return holder.clear_debuffs() if holder != null else 0


##给任意实体回血：优先 heal()（玩家），否则补给 HealthComponent。返回实际回了多少
static func heal_entity(target: Node, amount: float) -> float:
	if target == null or not is_instance_valid(target) or amount <= 0.0:
		return 0.0
	if target.has_method("heal"):
		target.call("heal", amount)
		return amount
	var health: Node = target.get_node_or_null("Health")

	if health == null:
		return 0.0
	var maximum: float = float(health.get("max_health"))
	var current: float = float(health.get("current_health"))

	if current <= 0.0:
		return 0.0
	var healed: float = minf(amount, maxf(maximum - current, 0.0))

	health.set("current_health", minf(current + amount, maximum))
	if health.has_signal("health_changed"):
		health.emit_signal("health_changed", health.get("current_health"), maximum)
	return healed


##吸血：攻击者按自己的 lifesteal 比例回血（source 需要实现 read_stat）
static func apply_lifesteal(source: Node, damage: float) -> void:
	if source == null or not is_instance_valid(source) or damage <= 0.0:
		return
	if not source.has_method("read_stat"):
		return
	var ratio: float = maxf(float(source.call("read_stat", &"lifesteal")), 0.0)

	if ratio <= 0.0:
		return
	heal_entity(source, damage * ratio)


##目标是否处于"伤害吸收"状态：这期间受到的伤害会变成回复
static func is_absorbing(target: Node) -> bool:
	var holder: BuffHolder = holder_of(target)
	return holder != null and holder.has_flag(FLAG_ABSORB)
