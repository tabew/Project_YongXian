class_name TraitCategory
extends RefCounted

## 词条类别：元素 / 行为 / 触发 / 修饰。
## 类别只负责图鉴分组、词条池裁剪优先级与配置校验，具体行为一律由 TraitCatalog 的数值表决定。

enum Kind {
	ELEMENT = 0,
	BEHAVIOR = 1,
	TRIGGER = 2,
	MODIFIER = 3,
}

const NAMES: Dictionary = {
	Kind.ELEMENT: "元素",
	Kind.BEHAVIOR: "行为",
	Kind.TRIGGER: "触发",
	Kind.MODIFIER: "修饰",
}

## 词条池超上限时保留哪一类：数字越小越先保留。
const TRIM_PRIORITY: Dictionary = {
	Kind.ELEMENT: 0,
	Kind.BEHAVIOR: 1,
	Kind.MODIFIER: 2,
	Kind.TRIGGER: 3,
}

static func name_of(kind: int) -> String:
	return NAMES.get(kind, "未知")

static func priority_of(kind: int) -> int:
	return int(TRIM_PRIORITY.get(kind, 99))

static func all_kinds() -> Array[int]:
	return [Kind.ELEMENT, Kind.BEHAVIOR, Kind.TRIGGER, Kind.MODIFIER]
