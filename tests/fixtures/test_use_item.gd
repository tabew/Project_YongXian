extends ItemData

class_name TestUseItem
##测试用道具：把 use() 的消耗值固定成一个可控的数，用来验证背包按返回值扣数量。
##只给测试脚本用，不进 ItemListGlobal 的正式模板清单。

##本次使用要消耗几份：0=不消耗，正数=消耗这么多
var consume_amount: int = 0


func use(_user: Node = null) -> int:
	return consume_amount
