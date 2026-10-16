
class_name StatModifier
extends Resource

## buff 对某一条属性的修改。数值按 buff 等级线性放大：value + value_per_level × (等级-1)

enum Mode
{
	FLAT,        ## 直接加减：base + value
	PERCENT_ADD, ## 按基准的百分比加减：base × (1 + value)
	MULTIPLY,    ## 叠乘：(1 + value) 相乘，多个乘子连乘
}

##要改的属性名。约定见各实体 read_stat/apply_stat：
##move_speed(玩家 max_speed / 怪物 ai_config.move_speed)、defense、damage_taken(倍率，1.0=正常)
@export var stat: StringName = &"defense"

##修改方式
@export var mode: Mode = Mode.FLAT

##基础数值
@export var value: float = 0.0

##每高一级额外增加多少
@export var value_per_level: float = 0.0


##本等级下的数值：0 级就是基础值，每高一级 +value_per_level
func amount(level: int) -> float:
	return value + value_per_level * float(maxi(level, 0))
