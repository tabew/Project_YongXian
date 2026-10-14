class_name WorkshopLayout
extends RefCounted

## 炼金工坊的布局配置：房间尺寸、出生点与各交互点的位置 / 名称 / 面板。
## 与任务书的布局图一一对应，新增交互点只改这里。

## 房间半宽 / 半高（像素），地板画在以原点为中心的矩形内。
const ROOM_HALF: Vector2 = Vector2(400.0, 320.0)
## 玩家出生点（出发门下方一点，进门就能看到全部交互点）。
const SPAWN: Vector2 = Vector2(0.0, 250.0)
## 墙体厚度。
const WALL_THICKNESS: float = 8.0

## 交互点：id / 名称 / 位置 / 面板 / 是否本期实现。
const POINTS: Array[Dictionary] = [
	{"id": &"alchemy_table", "name": "炼金台", "position": Vector2(-290.0, -200.0), "panel": &"upgrade", "implemented": true},
	{"id": &"codex_table", "name": "图鉴台", "position": Vector2(0.0, -200.0), "panel": &"codex", "implemented": false},
	{"id": &"material_vault", "name": "材料库", "position": Vector2(290.0, -200.0), "panel": &"materials", "implemented": true},
	{"id": &"relic_shelf", "name": "遗物架", "position": Vector2(-290.0, -60.0), "panel": &"relics", "implemented": false},
	{"id": &"training_ground", "name": "训练场", "position": Vector2(0.0, -60.0), "panel": &"training", "implemented": true},
	{"id": &"difficulty_altar", "name": "难度祭坛", "position": Vector2(290.0, -60.0), "panel": &"difficulty", "implemented": true},
	{"id": &"departure_gate", "name": "出发门", "position": Vector2(0.0, 60.0), "panel": &"departure", "implemented": true},
	{"id": &"achievement_wall", "name": "成就墙", "position": Vector2(-290.0, 200.0), "panel": &"achievements", "implemented": false},
	{"id": &"shop", "name": "商店", "position": Vector2(290.0, 200.0), "panel": &"shop", "implemented": false},
]


static func point_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for entry: Dictionary in POINTS:
		result.append(StringName(entry["id"]))
	return result


static func find_point(id: StringName) -> Dictionary:
	for entry: Dictionary in POINTS:
		if StringName(entry["id"]) == id:
			return entry
	return {}


static func position_of(id: StringName) -> Vector2:
	var entry: Dictionary = find_point(id)
	return entry.get("position", Vector2.ZERO)


## 只留接口、本期不实现具体内容的交互点。
static func placeholder_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for entry: Dictionary in POINTS:
		if not bool(entry.get("implemented", false)):
			result.append(StringName(entry["id"]))
	return result
