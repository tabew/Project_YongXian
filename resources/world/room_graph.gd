class_name RoomGraph
extends RunGraph

## 带类型的房间图：在既有 RunGraph 拓扑（层 + 主干/岔路）之上补房间类型、主路径与关键房间。
##
## 拓扑直接复用 RunGraph，不新建重复结构；本类只做增量。
## 结构是纯数据、不含节点，可在工作线程构造。
##
## 边即拓扑：主干可以走主路或拐进同层岔路，岔路汇回下一层主干，
## 所以每有一条岔路就自然形成一个可返回的环，不存在死路。

var config: MapConfig = null
## 派生本骨架用的种子。
var plan_seed: int = 0
## 选中的节奏模板下标，-1 表示没有模板。
var template_index: int = -1
## 布局变体，用于同种子下的多次尝试。
var variant_index: int = 0
## node_id -> RoomType.Kind
var types: Dictionary = {}
## 起点到 Boss 的主路径（主干节点 id，按层顺序）。
var main_path: PackedInt32Array = PackedInt32Array()
## 岔路节点 id（一级分支）。
var branch_nodes: PackedInt32Array = PackedInt32Array()
## 关键房间：RoomType.Kind -> PackedInt32Array(node_id)
var key_nodes: Dictionary = {}


static func plan(seed_value: int, config: MapConfig = null, variant: int = 0) -> RoomGraph:
	var graph := RoomGraph.new()
	graph.config = config if config != null else MapConfig.new()
	graph.build_topology(graph.config.floor_count, graph.config.resolved_branch_floors())
	graph.plan_seed = seed_value
	graph.variant_index = variant
	graph._build_plan(seed_value, variant)
	return graph


# ------------------------------------------------------------ 查询

func type_of(node_id: int) -> int:
	return types.get(node_id, RoomType.Kind.COMBAT)


func is_main_path(node_id: int) -> bool:
	return main_path.has(node_id)


## 主路径上某类型节点的数量。
func main_path_type_count(kind: int) -> int:
	var count: int = 0
	for node_id: int in main_path:
		if types.get(node_id, RoomType.Kind.COMBAT) == kind:
			count += 1
	return count


func has_branch(node_id: int) -> bool:
	return branch_nodes.has(node_id)


## 某类关键房间的节点 id；没有则返回空数组。
func nodes_of_type(kind: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for node_id: int in types.keys():
		if types[node_id] == kind:
			result.append(node_id)
	return result


## 某类关键房间的第一个节点；没有则返回 -1。
func key_node(kind: int) -> int:
	var list: PackedInt32Array = key_nodes.get(kind, PackedInt32Array())
	return list[0] if not list.is_empty() else -1


## 节点所属层距 Boss 还有几层（Boss 层为 0）。
func floors_to_boss(node_id: int) -> int:
	return floors.size() - 1 - RunGraph.floor_of(node_id)


# ------------------------------------------------------------ 生成

func _build_plan(seed_value: int, variant: int) -> void:
	main_path.clear()
	branch_nodes.clear()
	types.clear()
	key_nodes.clear()

	for floor_index: int in floors.size():
		var ids: PackedInt32Array = floors[floor_index]
		main_path.append(ids[0])
		if ids.size() > 1:
			branch_nodes.append(ids[1])

	for node_id: int in main_path:
		types[node_id] = RoomType.Kind.COMBAT
	types[main_path[0]] = RoomType.Kind.START
	types[main_path[main_path.size() - 1]] = RoomType.Kind.BOSS

	_assign_main_types(seed_value, variant)
	_assign_branch_types(seed_value, variant)
	_collect_key_nodes()


## 主路径类型：随机选一个节奏模板，按模板给主路径分配类型。
## 模板只决定节奏（战斗/奖励/商店/休息的排列），关键房间的数量与位置再由配置强制校正。
func _assign_main_types(seed_value: int, variant: int) -> void:
	var interior: Array[int] = _interior_floors()
	if interior.is_empty():
		return
	var rng: RandomNumberGenerator = MapRng.new(seed_value).rng(MapRng.Stream.ROOM, variant * 97)
	var templates: Array = config.resolved_rhythm_templates()
	template_index = rng.randi_range(0, templates.size() - 1) if not templates.is_empty() else -1
	var template: Array = templates[template_index] if template_index >= 0 else []
	var rhythm_kinds: Array[int] = _resize_template(template, interior.size())

	var safe: Array[int] = _key_candidate_floors()
	var assignment: Dictionary = {}
	var displaced: Dictionary = {}
	for index: int in interior.size():
		var floor_index: int = interior[index]
		var kind: int = rhythm_kinds[index]
		# 贴着 Boss 的层不能放关键房间：降级为战斗，稍后挪到安全的层。
		if RoomType.is_key(kind) and not safe.has(floor_index):
			displaced[kind] = displaced.get(kind, 0) + 1
			kind = RoomType.Kind.COMBAT
		assignment[floor_index] = kind

	_reconcile_key_counts(assignment, displaced)
	_ensure_main_combat(assignment)

	for floor_index: int in assignment.keys():
		types[main_node_at(floor_index)] = assignment[floor_index]


## 岔路房间：战斗或奖励，按权重抽样。
func _assign_branch_types(seed_value: int, variant: int) -> void:
	var rng: RandomNumberGenerator = MapRng.new(seed_value).rng(MapRng.Stream.ROOM, 1 + variant * 97)
	for node_id: int in branch_nodes:
		var kind: int = RoomType.Kind.COMBAT
		# 贴着 Boss 的岔路只放战斗，避免关键房间紧邻 Boss。
		if floors_to_boss(node_id) > config.boss_key_buffer and rng.randf() < config.branch_reward_chance:
			kind = RoomType.Kind.REWARD
		types[node_id] = kind


func _collect_key_nodes() -> void:
	key_nodes.clear()
	for kind: int in RoomType.KEY_KINDS:
		key_nodes[kind] = PackedInt32Array()
	for node_id: int in types.keys():
		var kind: int = types[node_id]
		if not RoomType.is_key(kind):
			continue
		var list: PackedInt32Array = key_nodes[kind]
		list.append(node_id)
		key_nodes[kind] = list


# ------------------------------------------------------------ 辅助

## 可以放关键房间的层：非首尾层，且与 Boss 保持 boss_key_buffer 层距离。
func _key_candidate_floors() -> Array[int]:
	var result: Array[int] = []
	for floor_index: int in range(1, floors.size() - 1):
		if floor_index < floors.size() - 1 - config.boss_key_buffer:
			result.append(floor_index)
	return result


## 全部中间层（不含起点层与 Boss 层）。
func _interior_floors() -> Array[int]:
	var result: Array[int] = []
	for floor_index: int in range(1, floors.size() - 1):
		result.append(floor_index)
	return result


func main_node_at(floor_index: int) -> int:
	return node_id(floor_index, MAIN_VARIANT)


## 中间优先的访问顺序，让关键房间尽量分散。
func _spread_order(candidates: Array[int]) -> Array[int]:
	var order: Array[int] = []
	if candidates.is_empty():
		return order
	var middle: int = candidates.size() / 2
	for step: int in candidates.size():
		var offset: int = (step + 1) / 2
		var index: int = middle + (offset if step % 2 == 1 else -offset)
		index = clampi(index, 0, candidates.size() - 1)
		if not order.has(index):
			order.append(index)
	var result: Array[int] = []
	for index: int in order:
		result.append(candidates[index])
	return result


## 把模板伸缩到指定长度：只增删战斗位，不丢关键房间。
func _resize_template(template: Array, length: int) -> Array[int]:
	var kinds: Array[int] = []
	for value: Variant in template:
		kinds.append(int(value))
	if kinds.is_empty():
		kinds.append(RoomType.Kind.COMBAT)
	while kinds.size() > length:
		var removed: bool = false
		for index: int in range(kinds.size() - 1, -1, -1):
			if kinds[index] == RoomType.Kind.COMBAT:
				kinds.remove_at(index)
				removed = true
				break
		if not removed:
			kinds.remove_at(kinds.size() - 1)
	while kinds.size() < length:
		kinds.insert(maxi(kinds.size() - 1, 0), RoomType.Kind.COMBAT)
	return kinds


## 关键房间的数量与位置校正：先压上限，再补下限，最后补回被挪走的关键房间。
func _reconcile_key_counts(assignment: Dictionary, displaced: Dictionary) -> void:
	_demote_kind(assignment, RoomType.Kind.REWARD, config.max_rewards)
	var minimums: Dictionary = {
		RoomType.Kind.SHOP: config.shop_count,
		RoomType.Kind.REST: config.min_rests,
		RoomType.Kind.REWARD: config.min_rewards,
	}
	for kind: int in minimums.keys():
		var shortfall: int = int(minimums[kind]) - _count_kind(assignment, kind)
		if shortfall > 0:
			_place_kind(assignment, kind, shortfall)
	for kind: int in displaced.keys():
		if kind == RoomType.Kind.REWARD and _count_kind(assignment, kind) >= config.max_rewards:
			continue
		_place_kind(assignment, kind, int(displaced[kind]))


## 至少一个非 Boss 主线战斗房；先让出超额关键房间，再考虑可选事件房。
func _ensure_main_combat(assignment: Dictionary) -> void:
	for floor_index: int in assignment.keys():
		if floor_index < floors.size() - 2 and assignment[floor_index] == RoomType.Kind.COMBAT:
			return
	var minimums: Dictionary = {
		RoomType.Kind.SHOP: config.shop_count,
		RoomType.Kind.REST: config.min_rests,
		RoomType.Kind.REWARD: config.min_rewards,
	}
	for floor_index: int in range(floors.size() - 3, 0, -1):
		var kind: int = assignment.get(floor_index, RoomType.Kind.COMBAT)
		if minimums.has(kind) and _count_kind(assignment, kind) > int(minimums[kind]):
			assignment[floor_index] = RoomType.Kind.COMBAT
			return
	for floor_index: int in _interior_floors():
		if floor_index >= floors.size() - 2:
			continue
		if assignment.get(floor_index, RoomType.Kind.COMBAT) == RoomType.Kind.EVENT:
			assignment[floor_index] = RoomType.Kind.COMBAT
			return


func _count_kind(assignment: Dictionary, kind: int) -> int:
	var count: int = 0
	for floor_index: int in assignment.keys():
		if assignment[floor_index] == kind:
			count += 1
	return count


## 把 count 个空闲的安全层改成 kind；优先中间层，保证关键房间分散。
func _place_kind(assignment: Dictionary, kind: int, count: int) -> void:
	var placed: int = 0
	for floor_index: int in _spread_order(_key_candidate_floors()):
		if placed >= count:
			break
		if assignment.get(floor_index, RoomType.Kind.COMBAT) != RoomType.Kind.COMBAT:
			continue
		assignment[floor_index] = kind
		placed += 1


## 把超过上限的 kind 降级为战斗。
func _demote_kind(assignment: Dictionary, kind: int, limit: int) -> void:
	var floors: Array[int] = []
	for floor_index: int in assignment.keys():
		if assignment[floor_index] == kind:
			floors.append(floor_index)
	floors.sort()
	while floors.size() > limit:
		assignment[floors.pop_back()] = RoomType.Kind.COMBAT


# ------------------------------------------------------------ 校验与调试

## 骨架硬约束（图级）。返回失败原因，空数组表示通过。
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	var path_len: int = main_path.size()
	if path_len < config.min_path_len or path_len > config.max_path_len:
		problems.append("主路径长度 %d 不在 [%d,%d]" % [path_len, config.min_path_len, config.max_path_len])
	var branch_count: int = branch_nodes.size()
	if branch_count < config.min_branches or branch_count > config.max_branches:
		problems.append("分支数量 %d 不在 [%d,%d]" % [branch_count, config.min_branches, config.max_branches])
	if type_of(main_path[0]) != RoomType.Kind.START:
		problems.append("起点类型不是 START")
	if type_of(main_path[path_len - 1]) != RoomType.Kind.BOSS:
		problems.append("Boss 类型不是 BOSS")

	var shops: PackedInt32Array = key_nodes.get(RoomType.Kind.SHOP, PackedInt32Array())
	if shops.size() < config.shop_count:
		problems.append("商店数量 %d < %d" % [shops.size(), config.shop_count])
	var main_rewards: int = main_path_type_count(RoomType.Kind.REWARD)
	if main_rewards < config.min_rewards or main_rewards > config.max_rewards:
		problems.append("主路径奖励房间数量 %d 不在 [%d,%d]" % [main_rewards, config.min_rewards, config.max_rewards])
	var rests: PackedInt32Array = key_nodes.get(RoomType.Kind.REST, PackedInt32Array())
	if rests.size() < config.min_rests:
		problems.append("休息点数量 %d < %d" % [rests.size(), config.min_rests])

	for kind: int in RoomType.KEY_KINDS:
		for node_id: int in key_nodes.get(kind, PackedInt32Array()):
			if floors_to_boss(node_id) <= config.boss_key_buffer:
				problems.append("关键房间 %s 距 Boss 过近（第 %d 层）" % [
					RoomType.name_of(kind), RunGraph.floor_of(node_id) + 1
				])
			if not is_main_path(node_id) and not has_branch(node_id):
				problems.append("关键房间 %s 不在主路径或一级分支上" % RoomType.name_of(kind))
	return problems


## 主路径类型序列（含起点与 Boss），调试用。
func rhythm() -> PackedStringArray:
	var result: PackedStringArray = []
	for node_id: int in main_path:
		result.append(RoomType.short_name(type_of(node_id)))
	return result


func describe_rooms() -> String:
	var lines: PackedStringArray = []
	lines.append("房间图 模板#%d %s：%s" % [template_index, config.describe(), " ".join(rhythm())])
	for floor_index: int in floors.size():
		var ids: PackedInt32Array = floors[floor_index]
		var parts: PackedStringArray = []
		for node_id: int in ids:
			var mark: String = "主干" if RunGraph.variant_of(node_id) == MAIN_VARIANT else "岔路"
			parts.append("%s#%d %s" % [mark, node_id, RoomType.name_of(type_of(node_id))])
		lines.append("  第 %d 层：%s" % [floor_index + 1, "，".join(parts)])
	return "\n".join(lines)
