# ===== AI 新增文件 (护己：带这个属性的药水不作用于使用者自己) =====
class_name SelfExempt
extends AlchemicalData

## 护己：带这个属性的药水，效果不会落到使用者自己身上。
## 它是"药水级"的修饰属性（不作用于生物），所以没有 buff 字段，
## 药水破碎时由 PotionProjectile 把它从生效列表里摘出来，改为把使用者记进
## 药水模型的 metadata；圆形范围与爆炸效果都会读这个 metadata 跳过使用者。

##使用者记录在药水模型 metadata 上的键：范围与爆炸都读它
const EXEMPT_META: StringName = &"exempt_target"


##药水级修饰标记：PotionProjectile 用它判断是否把使用者排除在效果之外
func exempts_user() -> bool:
	return true


##目前不参与反应（以后要配方就在 match 里按枚举写，写法参照 heal.gd）
func interact(_attribute: Array[AlchemicalData], _which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	return result


##本身不对生物产生效果：真正的逻辑在药水破碎/爆炸那一侧
func use_effect(_object: Node = null) -> void:
	pass
