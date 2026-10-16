extends ItemData

class_name TestUseItem
## 测试用道具：固定 left_use() 的消耗值，验证背包按返回值扣数量。
##只给测试脚本用，不进 ItemListGlobal 的正式模板清单。

##本次使用要消耗几份：0=不消耗，正数=消耗这么多
var consume_amount: int = 0


func left_use(_user: PlayerCharacter) -> int:
	return consume_amount
