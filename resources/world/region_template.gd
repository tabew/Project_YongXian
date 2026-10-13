class_name RegionTemplate
extends RefCounted

## 区域模板：一个区域箱庭的形状、尺寸范围、允许的房间类型与门的朝向。
##
## 这是"拼接"层的模板结构。现有生成器负责把区域放到世界网格上并对齐门，
## 模板只负责挑选可用的区域规格，不改变网格放置与门对齐逻辑。

## 尺寸下限 / 上限，与 MapSpec 的默认范围一致。
const MIN_EXTENT: int = 112
const MAX_EXTENT: int = 224

## 门朝向位掩码。
const DOOR_WEST: int = 1
const DOOR_EAST: int = 2
const DOOR_BOTH: int = DOOR_WEST | DOOR_EAST

var id: StringName = &""
## 形状下标；-1 表示不限形状（沿用按种子决定的形状，保证六类轮廓都能出现）。
var shape: int = -1
var min_extent: int = MIN_EXTENT
var max_extent: int = MAX_EXTENT
## 允许的房间类型；空数组表示不限。
var allowed_types: PackedInt32Array = PackedInt32Array()
## 支持的门朝向。
var door_sides: int = DOOR_BOTH
var weight: float = 1.0
## 边界地形候选；空数组表示沿用默认（森林 / 针叶林 / 山地）。
var boundary_kinds: PackedInt32Array = PackedInt32Array()


static func create(id_value: StringName, min_size: int, max_size: int, template_weight: float = 1.0) -> RegionTemplate:
	var template := RegionTemplate.new()
	template.id = id_value
	template.min_extent = min_size
	template.max_extent = max_size
	template.weight = template_weight
	return template


func allows(kind: int) -> bool:
	return allowed_types.is_empty() or allowed_types.has(kind)


func supports_doors(doors: int) -> bool:
	return (doors & ~door_sides) == 0


func matches(kind: int, doors: int, shape_hint: int) -> bool:
	if not allows(kind) or not supports_doors(doors):
		return false
	return shape == -1 or shape == shape_hint