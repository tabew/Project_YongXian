extends ItemData

class_name WeaponData

@export var weapon:WeaponDefinition

##附魔过的武器是独立实例，不共用模板；运行时 id 从这里发号（和药水一个套路）
const INSTANCE_ID_START:int = 400

static var _next_instance_id:int = INSTANCE_ID_START


static func next_instance_id() ->int:
	var instance_id:int = _next_instance_id
	_next_instance_id += 1

	return instance_id