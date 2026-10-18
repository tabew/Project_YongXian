
class_name SelfExempt
extends AlchemicalData

## 护己：带这个属性的药水按"正负面词条"分流效果 ——
## 正面属性（治疗/增益）只作用于使用者自己；
## 负面属性（伤害/减益）作用于圈内的敌方目标，不会落到使用者身上。
## 它是"药水级"修饰属性（自己对生物没有效果，词条为 NEUTRAL），
## 药水破碎时由 PotionProjectile 把它从生效列表里摘出来，并把使用者记进药水模型的 metadata；
## 圆形范围（PotionBurst）按词条分流，爆炸（ExplodeEffect）读 metadata 跳过使用者。

##使用者记录在药水模型 metadata 上的键：范围与爆炸都读它
const EXEMPT_META: StringName = &"exempt_target"


##药水级修饰标记.PotionProjectile 用它判断是否把使用者排除在效果之外
func exempts_user() -> bool:
	return true


##目前不参与反应（以后要配方就在 match 里按枚举写，写法参照 heal.gd）


##本身不对生物产生效果

func use_effect(_object: Node = null) -> void:
	pass


func _default_polarity() -> POLARITY:
	return POLARITY.NEUTRAL

