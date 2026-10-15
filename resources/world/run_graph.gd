class_name RunGraph
extends RefCounted

## 一局游戏的关卡图：一层一层往前推，主干之外带岔路。
##
## 原节点仍是层号 * 2 + 分支号；第三列额外分支使用独立编号。
## 保留主线和原岔路汇流关系，新分支经下侧岔路返回主线。

const FLOOR_COUNT: int = 8
const MAIN_VARIANT: int = 0
const BRANCH_VARIANT: int = 1
const THIRD_VARIANT: int = 2
## 保留原 floor*2+variant 的节点编号；第三列的额外节点另用保留区间。
const THIRD_NODE_BASE: int = 100

## 第几层有哪些节点，索引 = 层号
var floors: Array[PackedInt32Array] = []
## 节点 id -> 下一层可达的节点 id
var next_nodes: Dictionary = {}


static func node_id(floor_index: int, variant: int) -> int:
	return THIRD_NODE_BASE + floor_index if variant == THIRD_VARIANT else floor_index * 2 + variant


static func floor_of(map_node_id: int) -> int:
	return map_node_id - THIRD_NODE_BASE if map_node_id >= THIRD_NODE_BASE else map_node_id / 2


static func variant_of(map_node_id: int) -> int:
	return THIRD_VARIANT if map_node_id >= THIRD_NODE_BASE else map_node_id % 2


static func create() -> RunGraph:
	var graph := RunGraph.new()
	graph.build_topology(FLOOR_COUNT, default_branch_floors(FLOOR_COUNT))
	return graph


## 默认岔路层：首尾层不开岔路，与旧实现一致。
static func default_branch_floors(floor_count: int) -> Array[int]:
	var result: Array[int] = []
	for floor_index: int in range(1, maxi(floor_count - 1, 1)):
		result.append(floor_index)
	return result


## 每层一个主干及可选岔路；默认第三列还有一个可选分支。
## 原岔路仍可直接汇回主干，额外分支通过下一列下侧岔路回到主线。
func build_topology(floor_count: int, branch_floors: Array[int], third_branch: bool = false) -> void:
	floors.clear()
	next_nodes.clear()
	var branch_set: Dictionary = {}
	for floor_index: int in branch_floors:
		branch_set[floor_index] = true

	for floor_index: int in floor_count:
		var ids := PackedInt32Array()
		ids.append(node_id(floor_index, MAIN_VARIANT))
		if branch_set.has(floor_index):
			ids.append(node_id(floor_index, BRANCH_VARIANT))
			if third_branch and floor_index == 2 and floor_count >= 5 and branch_set.has(1):
				ids.append(node_id(floor_index, THIRD_VARIANT))
		floors.append(ids)

	for floor_index: int in maxi(floor_count - 1, 0):
		var upcoming: PackedInt32Array = floors[floor_index + 1]
		for current: int in floors[floor_index]:
			var targets := PackedInt32Array()
			if variant_of(current) == MAIN_VARIANT:
				# 主干保留通往下一层主干和原岔路的出口。
				for target: int in upcoming:
					if variant_of(target) != THIRD_VARIANT:
						targets.append(target)
			elif variant_of(current) == BRANCH_VARIANT:
				# 原有汇流不变；第三列下侧新区域由第二列岔路进入。
				targets.append(upcoming[0])
				if upcoming.size() > 2:
					targets.append(upcoming[2])
			else:
				# 第三列的新岔路从下侧回到下一列，保留原关卡主路径。
				targets.append(upcoming[1] if upcoming.size() > 1 else upcoming[0])
			next_nodes[current] = targets


## 这个节点有几条向前的出口（决定地图右侧开几个路口）。
func exit_count(map_node_id: int) -> int:
	var targets: PackedInt32Array = next_nodes.get(map_node_id, PackedInt32Array())
	return targets.size()


## 这个节点有没有西侧入口（第一层没有）。
func has_entrance(map_node_id: int) -> bool:
	return floor_of(map_node_id) > 0


func start_node() -> int:
	return node_id(0, MAIN_VARIANT)


func final_node() -> int:
	return node_id(floors.size() - 1, MAIN_VARIANT)


## 某个出口通向哪个节点。
func target_of(map_node_id: int, exit_index: int) -> int:
	var targets: PackedInt32Array = next_nodes.get(map_node_id, PackedInt32Array())
	if exit_index < 0 or exit_index >= targets.size():
		return -1
	return targets[exit_index]


func describe(map_node_id: int) -> String:
	return "第 %d 层%s" % [
		floor_of(map_node_id) + 1,
		"（岔路）" if variant_of(map_node_id) == BRANCH_VARIANT else "",
	]
