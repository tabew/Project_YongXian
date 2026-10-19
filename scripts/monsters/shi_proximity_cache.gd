class_name ShiProximityCache
extends RefCounted

## 史莱姆的局部检索索引：同一物理帧每类分组只扫描一次，全群共享。
const CELL_SIZE: float = 64.0
static var _tree_id: int = 0
static var _frames: Dictionary = {}
static var _indices: Dictionary = {}
static var rebuilds: int = 0

static func invalidate() -> void:
	_frames.clear()
	_indices.clear()

static func nearby(owner: Node2D, group: StringName, radius: float) -> Array[Node]:
	var tree: SceneTree = owner.get_tree()
	if tree.get_instance_id() != _tree_id:
		_tree_id = tree.get_instance_id()
		invalidate()
	var frame: int = Engine.get_physics_frames()
	if _frames.get(group, -1) != frame:
		var buckets: Dictionary = {}
		for node: Node in tree.get_nodes_in_group(group):
			if not node is Node2D or node.is_queued_for_deletion() or not (node as Node2D).is_visible_in_tree():
				continue
			var key: Vector2i = _cell((node as Node2D).global_position)
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(node)
		_indices[group] = buckets
		_frames[group] = frame
		rebuilds += 1
	var result: Array[Node] = []
	var center: Vector2i = _cell(owner.global_position)
	# 一格移动余量避免本帧先移动的目标跨桶边界后短暂漏检。
	var reach: int = ceili((radius + float(WorldGenerator.TILE_SIZE)) / CELL_SIZE)
	var index: Dictionary = _indices[group]
	for y: int in range(center.y - reach, center.y + reach + 1):
		for x: int in range(center.x - reach, center.x + reach + 1):
			for candidate: Variant in index.get(Vector2i(x, y), []):
				if is_instance_valid(candidate):
					result.append(candidate as Node)
	return result

static func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))
