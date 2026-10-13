class_name RegionTemplates
extends RefCounted

## 区域模板集合与挑选逻辑。全部有默认值，不配置也能跑。

static var _defaults: Array[RegionTemplate] = []
static var _fallback: RegionTemplate = null


## 默认模板集：按房间类型给出尺寸倾向，形状不限（沿用按种子决定的形状）。
static func defaults() -> Array[RegionTemplate]:
	if not _defaults.is_empty():
		return _defaults
	_defaults = [
		_make(&"start", RoomType.Kind.START, 112, 176, 2.0),
		_make(&"combat", RoomType.Kind.COMBAT, 144, 224, 3.0),
		_make(&"reward", RoomType.Kind.REWARD, 112, 192, 2.0),
		_make(&"shop", RoomType.Kind.SHOP, 112, 160, 2.0),
		_make(&"rest", RoomType.Kind.REST, 112, 160, 2.0),
		_make(&"event", RoomType.Kind.EVENT, 128, 192, 2.0),
		_make(&"boss", RoomType.Kind.BOSS, 176, 224, 3.0),
	]
	return _defaults


static func _make(id_value: StringName, kind: int, low: int, high: int, template_weight: float) -> RegionTemplate:
	var template := RegionTemplate.create(id_value, low, high, template_weight)
	template.allowed_types = PackedInt32Array([kind])
	return template


## 加权挑选一个匹配 (房间类型, 门朝向, 形状) 的模板；没有匹配时降级到通用模板。
static func pick(kind: int, doors: int, shape_hint: int, rng: RandomNumberGenerator, templates: Array = []) -> RegionTemplate:
	var pool: Array = templates if not templates.is_empty() else defaults()
	var candidates: Array[RegionTemplate] = []
	var total: float = 0.0
	for entry: RegionTemplate in pool:
		if not entry.matches(kind, doors, shape_hint):
			continue
		candidates.append(entry)
		total += entry.weight
	if candidates.is_empty():
		return fallback()
	var roll: float = rng.randf() * total
	for entry: RegionTemplate in candidates:
		roll -= entry.weight
		if roll <= 0.0:
			return entry
	return candidates[candidates.size() - 1]


## 降级模板：不限形状、不限类型、支持两侧门、使用最大尺寸范围。
static func fallback() -> RegionTemplate:
	if _fallback == null:
		_fallback = RegionTemplate.create(&"fallback", RegionTemplate.MIN_EXTENT, RegionTemplate.MAX_EXTENT, 1.0)
	return _fallback