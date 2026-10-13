extends SceneTree

## 房间图骨架验收：主路径/分支范围、起终点类型、关键房间位置与可达层级。
## godot --headless --path . --script res://tools/test_room_graph.gd

const SEEDS: Array[int] = [1, 7, 18473, 97231, 24681357, 2147483646]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var rhythms: Dictionary = {}
	var branch_sigs: Dictionary = {}
	for seed_value: int in SEEDS:
		var graph: RoomGraph = RoomGraph.plan(seed_value)
		_check(graph.validate().is_empty(), "骨架校验失败 seed=%d %s" % [seed_value, graph.validate()])
		_check(graph.main_path.size() >= graph.config.min_path_len
			and graph.main_path.size() <= graph.config.max_path_len,
			"主路径长度越界 seed=%d len=%d" % [seed_value, graph.main_path.size()])
		_check(graph.branch_nodes.size() >= graph.config.min_branches
			and graph.branch_nodes.size() <= graph.config.max_branches,
			"分支数量越界 seed=%d n=%d" % [seed_value, graph.branch_nodes.size()])
		_check(graph.type_of(graph.main_path[0]) == RoomType.Kind.START, "起点不是 START seed=%d" % seed_value)
		_check(graph.type_of(graph.main_path[graph.main_path.size() - 1]) == RoomType.Kind.BOSS, "终点不是 BOSS seed=%d" % seed_value)

		for kind: int in RoomType.KEY_KINDS:
			var list: PackedInt32Array = graph.key_nodes.get(kind, PackedInt32Array())
			for node_id: int in list:
				_check(graph.floors_to_boss(node_id) > graph.config.boss_key_buffer,
					"关键房间距 Boss 过近 seed=%d %s" % [seed_value, RoomType.name_of(kind)])
				_check(graph.is_main_path(node_id) or graph.has_branch(node_id),
					"关键房间不在主路径/一级分支 seed=%d" % seed_value)
		_check(graph.nodes_of_type(RoomType.Kind.SHOP).size() >= graph.config.shop_count, "商店不足 seed=%d" % seed_value)
		_check(graph.nodes_of_type(RoomType.Kind.REWARD).size() >= graph.config.min_rewards, "奖励房不足 seed=%d" % seed_value)
		_check(graph.nodes_of_type(RoomType.Kind.REST).size() >= graph.config.min_rests, "休息点不足 seed=%d" % seed_value)

		# 每条岔路都汇回主干，构成可返回的环；不存在只进不出的死路。
		for node_id: int in graph.branch_nodes:
			var targets: PackedInt32Array = graph.next_nodes.get(node_id, PackedInt32Array())
			_check(targets.size() == 1 and graph.is_main_path(targets[0]), "岔路没有汇回主干 seed=%d node=%d" % [seed_value, node_id])
		for node_id: int in graph.main_path:
			_check(not graph.next_nodes.get(node_id, PackedInt32Array()).is_empty()
				or node_id == graph.main_path[graph.main_path.size() - 1],
				"主干存在死路 seed=%d node=%d" % [seed_value, node_id])

		rhythms[seed_value] = " ".join(graph.rhythm())
		var signature: PackedStringArray = []
		for node_id: int in graph.branch_nodes:
			signature.append(str(graph.type_of(node_id)))
		branch_sigs[seed_value] = "".join(signature)
		var replica: RoomGraph = RoomGraph.plan(seed_value)
		_check(" ".join(replica.rhythm()) == rhythms[seed_value], "同种子骨架不一致 seed=%d" % seed_value)
		print("ROOM_GRAPH seed=%d %s | 分支=%s" % [seed_value, rhythms[seed_value], branch_sigs[seed_value]])

	# 不同种子的骨架应存在差异（节奏或岔路类型不同）。
	var distinct: Dictionary = {}
	for seed_value: int in SEEDS:
		distinct["%s|%s" % [rhythms[seed_value], branch_sigs[seed_value]]] = true
	_check(distinct.size() > 1, "所有种子骨架完全相同，缺少随机性")
	_check_template_compliance()
	print("ROOM_GRAPH_TEST: checks=%d failures=%d distinct=%d" % [_checks, _failures, distinct.size()])
	quit(0 if _failures == 0 else 1)


## 节奏模板合规：单一模板且约束刚好满足时，主路径类型必须与模板逐位一致。
func _check_template_compliance() -> void:
	var config := MapConfig.new()
	config.floor_count = 7
	config.branch_floors = [2, 4]
	config.min_path_len = 5
	config.max_path_len = 9
	config.min_branches = 1
	config.max_branches = 4
	config.shop_count = 1
	config.min_rewards = 1
	config.max_rewards = 2
	config.min_rests = 0
	config.boss_key_buffer = 1
	config.rhythm_templates = [[
		RoomType.Kind.COMBAT, RoomType.Kind.REWARD, RoomType.Kind.COMBAT,
		RoomType.Kind.SHOP, RoomType.Kind.COMBAT,
	]]
	var graph: RoomGraph = RoomGraph.plan(4242, config)
	_check(" ".join(graph.rhythm()) == "P C R C $ C B",
		"主路径节奏与模板不一致：%s" % " ".join(graph.rhythm()))
	_check(graph.template_index == 0, "模板下标没有记录")
	_check(graph.validate().is_empty(), "模板配置骨架校验失败 %s" % graph.validate())

	# 多模板时，不同种子应能选中不同模板。
	var picked: Dictionary = {}
	for seed_value: int in SEEDS:
		picked[RoomGraph.plan(seed_value).template_index] = true
	_check(picked.size() > 1, "多模板下没有抽到不同模板")
	print("ROOM_GRAPH_TEMPLATE: rhythm=%s templates_used=%d" % [" ".join(graph.rhythm()), picked.size()])
