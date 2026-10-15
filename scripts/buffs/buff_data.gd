# ===== AI 新增文件 (buff 的独立规则：时长、等级换算、定时效果、属性修改) =====
class_name BuffData
extends Resource

## 一个 buff 的完整规则。它和"谁施加的"无关：
## 炼金属性、道具、怪物攻击、事件都可以通过 Buffs.apply() 施加同一个 BuffData。
##
## 叠加规则（全局约定）：同一个 id 只保留一份，取最高级 ——
## 新等级更高就看升级并刷新时长，等级相同或更低则本次施加不做任何事。

##唯一标识：同一个 id 视为同一个 buff
@export var id: StringName = &""

##显示名（HUD / 提示）
@export var display_name: String = ""

##说明文本
@export_multiline var description: String = ""

##HUD 图标
@export var icon: Texture2D

##减益标记：HUD 上换个边框颜色
@export var is_debuff: bool = false

##持续时间(秒)。<= 0 表示不自动到期（只能被手动移除/清空）
@export_range(0.0, 600.0, 0.1) var duration: float = 6.0

##等级上限，施加时夹取（防止等级算飞出界）
@export_range(1, 99, 1) var max_level: int = 3

@export_group("定时效果")
##每隔多少秒跳一次。<= 0 表示不跳
@export_range(0.0, 60.0, 0.05) var tick_interval: float = 0.0
##每次跳回多少血（按等级加算）
@export var heal_per_tick: float = 0.0
@export var heal_per_tick_per_level: float = 0.0
##每次跳扣多少血（按等级加算）
@export var damage_per_tick: float = 0.0
@export var damage_per_tick_per_level: float = 0.0

@export_group("属性修改")
##对宿主属性的修改列表
@export var modifiers: Array[StatModifier] = []


func has_tick() -> bool:
	return tick_interval > 0.0 and (heal_per_tick != 0.0 or heal_per_tick_per_level != 0.0
		or damage_per_tick != 0.0 or damage_per_tick_per_level != 0.0)


func heal_amount(level: int) -> float:
	return heal_per_tick + heal_per_tick_per_level * float(maxi(level - 2, 0))


func damage_amount(level: int) -> float:
	return damage_per_tick + damage_per_tick_per_level * float(maxi(level - 2, 0))
