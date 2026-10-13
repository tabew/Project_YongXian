class_name RunGraph
extends RefCounted

## 一局游戏的关卡图：一层一层往前推，主干之外带岔路。
##
## 节点 id = 层号 * 2 + 分支号。主干（分支 0）可以走主路，也可以拐进岔路；
## 岔路（分支 1）只汇回下一层的主干。所以玩法是"一条路串到底，中途可以拐弯"。

const FLOOR_COUNT: int = 8
const MAIN_VARIANT: int = 0
const BRANCH_VARIANT: int = 1

## 第几层有哪些节点，索引 = 层号
var floors: Array[PackedInt32Array] = []
## 节点 id -> 下一层可达的节点 id
var next_nodes: Dictionary = {}


static func node_id(floor_index: int, variant: int) -> int:
	return floor_index * 2 + variant


static func floor_of(map_node_id: int) -> int:
	return map_node_id / 2


static func variant_of(map_node_id: int) -> int:
	return map_node_id % 2


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


## 按配置重建拓扑：每层一个主干，branch_floors 里的层再挂一个岔路。
## 主干可以走主路或拐进同层岔路，岔路汇回下一层主干，所以每条岔路都构成一个环。
func build_topology(floor_count: int, branch_floors: Array[int]) -> void:
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
		floors.append(ids)

	for floor_index: int in maxi(floor_count - 1, 0):
		var upcoming: PackedInt32Array = floors[floor_index + 1]
		for current: int in floors[floor_index]:
			var targets := PackedInt32Array()
			if variant_of(current) == MAIN_VARIANT:
				# 主干：既可以直接往前走，也可以拐进下一层的岔路
				for target: int in upcoming:
					targets.append(target)
			else:
				# 岔路：只汇回下一层的主干
				targets.append(upcoming[0])
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
