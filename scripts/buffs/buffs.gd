
class_name Buffs
extends RefCounted

## 施加 buff 的唯一入口。炼金属性、道具、怪物攻击、事件系统都用它，
## 目标可以是实体本身（玩家/怪物/训练靶）
## 找不到就返回 false，调用方不用关心目标有没有 buff 容器。

##buff 容器在实体下的约定名字
const HOLDER_NAME: String = "Buffs"

# ===== AI 修改开始 (标记类效果的约定) =====
##隐身标记：宿主实现 set_buff_flag(&"invisible", active) 时生效
const FLAG_INVISIBLE: StringName = &"invisible"
##隐身时的整体透明度（三个实体共用同一个值）
const INVISIBLE_ALPHA: float = 0.35
# ===== AI 修改结束 =====


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
