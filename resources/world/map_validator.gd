class_name MapValidator
extends RefCounted

## 地图硬约束校验：不合格就换种子重生成，保证地图不崩。
##
## 校验只在新生成地图时执行，不参与逐帧逻辑。

## 校验整张地图；返回失败原因，空数组表示通过。
static func validate(generator: WorldGenerator) -> PackedStringArray:
	var problems := PackedStringArray()
	if generator == null or generator.run == null:
		problems.append("生成器为空")
		return problems
	# 1 / 7 骨架：主路径长度、分支数量、起终点类型、关键房间位置。
	problems.append_array(generator.run.validate())
	# 2 / 3 连通与可达：起点到 Boss、全部节点与关键房间。
	problems.append_array(_check_reachability(generator.run))
	# 4 无区域重叠。
	problems.append_array(_check_overlap(generator))
	# 5 门对齐。
	problems.append_array(_check_gates(generator))
	# 6 无死锁。
	problems.append_array(_check_dead_ends(generator.run))
	return problems


## 生成一张通过硬校验的地图。不通过就在同一主种子下换布局变体重试；
## 超过上限用问题最少的候选兜底。世界身份（种子）始终不变。
static func build_valid(seed_value: int, config: MapConfig = null) -> WorldGenerator:
	var effective: MapConfig = config if config != null else MapConfig.new()
	var best: WorldGenerator = null
	var best_problems: int = 2147483647
	for attempt: int in effective.max_retries + 1:
		var candidate: WorldGenerator = WorldGenerator.new(seed_value, effective, attempt)
		var problems: PackedStringArray = validate(candidate)
		if problems.is_empty():
			return candidate
		if problems.size() < best_problems:
			best_problems = problems.size()
			best = candidate
		push_warning("地图校验失败（第 %d 次，种子 %d 变体 %d）：%s" % [attempt + 1, seed_value, attempt, ", ".join(problems)])
	push_warning("达到重试上限 %d，改用问题最少的候选地图（%d 个问题）" % [effective.max_retries, best_problems])
	return best


# ------------------------------------------------------------ 分项检查

static func _check_reachability(run: RoomGraph) -> PackedStringArray:
	var problems := PackedStringArray()
	var start: int = run.start_node()
	var final: int = run.final_node()
	var seen: Dictionary = {start: true}
	var queue: Array[int] = [start]
	var head: int = 0
	while head < queue.size():
		var node: int = queue[head]
		head += 1
		for target: int in run.next_nodes.get(node, PackedInt32Array()):
			if not seen.has(target):
				seen[target] = true
				queue.append(target)
	if not seen.has(final):
		problems.append("起点到 Boss 不可达")
	for node_id: int in run.types.keys():
		if not seen.has(node_id):
			problems.append("节点 %d 从起点不可达" % node_id)
	for kind: int in RoomType.KEY_KINDS:
		for node_id: int in run.key_nodes.get(kind, PackedInt32Array()):
			if not seen.has(node_id):
				problems.append("关键房间 %s#%d 不可达" % [RoomType.name_of(kind), node_id])
	return problems


static func _check_dead_ends(run: RoomGraph) -> PackedStringArray:
	var problems := PackedStringArray()
	var final: int = run.final_node()
	for node_id: int in run.types.keys():
		var targets: PackedInt32Array = run.next_nodes.get(node_id, PackedInt32Array())
		if targets.is_empty() and node_id != final:
			problems.append("节点 %d 是死路" % node_id)
	return problems


static func _check_overlap(generator: WorldGenerator) -> PackedStringArray:
	var problems := PackedStringArray()
	var specs: Array[MapSpec] = generator.map_specs()
	for i: int in specs.size():
		for j: int in range(i + 1, specs.size()):
			var a := Rect2i(specs[i].origin, specs[i].extent)
			var b := Rect2i(specs[j].origin, specs[j].extent)
			if a.intersects(b):
				problems.append("区域 %d 与 %d 重叠" % [specs[i].node_id, specs[j].node_id])
	var previous: Array[MapSpec] = []
	for ids: PackedInt32Array in generator.run.floors:
		var column: Array[MapSpec] = []
		for id: int in ids:
			column.append(generator.map_spec(id))
		column.sort_custom(func(a: MapSpec, b: MapSpec) -> bool: return a.origin.y < b.origin.y)
		for index: int in column.size():
			var region: MapSpec = column[index]
			if region.origin.x != column[0].origin.x or region.extent.x != column[0].extent.x:
				problems.append("同列区域东西边界未对齐")
			if index > 0 and column[index - 1].origin.y + column[index - 1].extent.y != region.origin.y:
				problems.append("同列区域存在空隙或重叠")
		if not previous.is_empty():
			if previous[0].origin.x + previous[0].extent.x != column[0].origin.x:
				problems.append("相邻箱庭列没有贴合")
			var shared: bool = false
			for left: MapSpec in previous:
				for right: MapSpec in column:
					shared = shared or mini(left.origin.y + left.extent.y, right.origin.y + right.extent.y) - maxi(left.origin.y, right.origin.y) >= 12
			if not shared:
				problems.append("相邻箱庭列只有角落接触")
		previous = column
	return problems


static func _check_gates(generator: WorldGenerator) -> PackedStringArray:
	var problems := PackedStringArray()
	var expected_edges: int = 0
	for spec: MapSpec in generator.map_specs():
		expected_edges += generator.run.exit_count(spec.node_id)
	var links: Array[Dictionary] = generator.connections()
	if links.size() != expected_edges:
		problems.append("连接数量 %d 与出口数量 %d 不一致" % [links.size(), expected_edges])
	var link_count: int = 0
	for spec: MapSpec in generator.map_specs():
		link_count += generator.gate_links(spec.node_id).size()
	if link_count != expected_edges * 2:
		problems.append("图边没有对应双向出口")
	for connection: Dictionary in links:
		var source: MapSpec = generator.map_spec(connection["from"])
		var target: MapSpec = generator.map_spec(connection["to"])
		if source == null or target == null:
			problems.append("连接引用了不存在的区域")
			continue
		var source_y: int = source.east_gates[connection["exit"]]
		var target_y: int = target.west_gates[connection["entrance"]]
		if source_y < 0 or source_y >= source.extent.y:
			problems.append("出口 y 越界 区域 %d" % source.node_id)
		if target_y < 0 or target_y >= target.extent.y:
			problems.append("入口 y 越界 区域 %d" % target.node_id)
	return problems