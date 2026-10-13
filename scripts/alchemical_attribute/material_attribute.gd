class_name MaterialAttribute
extends AlchemicalData

## 材料本性：矿物提供骨架，木质提供纤维，两者反应产生固结属性。
## product_id < 0 表示惰性终产物；本属性不提供治疗或生命恢复。
@export var product_id: int = -1


func interact(attributes: Array[AlchemicalData], which: int = 1) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []
	if product_id < 0:
		return result
	for peer: AlchemicalData in attributes:
		if not can_interact_with(peer):
			continue
		if which == 2:
			result.append(self)
			result.append(peer)
		else:
			var product: AlchemicalData = AlchemicalAttributeList.create(product_id)
			if product != null:
				result.append(product)
		break
	return result
