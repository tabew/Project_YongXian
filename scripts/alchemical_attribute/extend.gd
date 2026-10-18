
class_name Extend
extends AlchemicalData

## 延时：药水级修饰。让同一瓶药水里其它带持续时间的效果更久：
## 施加的 buff 时长、作用圈留存时长都会按倍率放大。本身不直接作用于生物。

##基础的时长加成比例（0.5 = 延长 50%）
@export var duration_bonus: float = 0.5
##每级追加的比例
@export var duration_bonus_per_level: float = 0.25


##时长倍率：1.0 表示不变
func duration_scale_total() -> float:
	return 1.0 + duration_bonus + duration_bonus_per_level * float(maxi(level, 0))


##没有炼药反应配方

