extends SceneTree

## 局内地图 → 世界骨架的适配测试。
##
## godot --headless --path . --script res://tests/test_run_map_world.gd
##
## 覆盖四件事：
## 1. 编号规则：世界编号 = 层 × 2 + 变体，且与局内 node_id 双向可逆。
## 2. 硬校验：MapValidator 在多个种子 / 配置下全部通过（含可达性与死路）。
## 3. 出口方向：除 Boss 与秘密房侧门，每个房间都至少有一条向前的门。
## 4. 选门面板：清空房间后列出 1~3 条路线，并带材料预告与抗性 / 弱点。

const SEEDS: Array[int] = [1, 42, 777, 31337, 20261008]
## 硬校验遍历的种子数量；两个配置各跑一遍。
const SWEEP_SEEDS: int = 40
const SWEEP_FLOORS: int = 2

var _checks: int = 0
var _failures: int = 0
## 面板选门回调；用成员变量而不是 lambda 捕获局部变量，避免回调比局部变量活得久。
var _chosen: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _on_door_chosen(data_node_id: int) -> void:
	_chosen.append(data_node_id)


func _run() -> void:
	_test_numbering()
	_test_validate_sweep()
	_test_forward_exits()
	_test_secret_side_door()
	_test_door_panel()
	print("RUN MAP WORLD: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _plan(seed_value: int, floor_index: int, config: RunMapConfig = null) -> FloorRoomGraph:
	var floor: FloorData = RunMapGenerator.generate(seed_value, floor_index, config)
	return FloorRoomGraph.plan_from_floor(floor, MapConfig.new(), seed_value)


## 世界生成器的编号是"层 × 2 + 变体"，局内地图的 node_id 只在本图内部有意义。
func _test_numbering() -> void:
	for seed_value: int in SEEDS:
		var graph: FloorRoomGraph = _plan(seed_value, 0)
		var floor: FloorData = graph.floor
		_check(graph.planned_from_floor, "种子 %d 骨架标记来自局内地图" % seed_value)
		_check(not graph.floors.is_empty(), "种子 %d 骨架有层" % seed_value)
		var seen: Dictionary = {}
		for depth: int in graph.floors.size():
			var ids: PackedInt32Array = graph.floors[depth]
			_check(not ids.is_empty(), "种子 %d 第 %d 层不为空" % [seed_value, depth])
			for variant: int in ids.size():
				var world_id: int = ids[variant]
				_check(world_id == RunGraph.node_id(depth, variant), "世界编号 = 层 × 2 + 变体")
				_check(not seen.has(world_id), "种子 %d 世界编号 %d 不重复" % [seed_value, world_id])
				seen[world_id] = true
				var data_node: int = graph.data_node_of(world_id)
				_check(data_node >= 0, "世界编号 %d 有对应房间数据" % world_id)
				_check(graph.world_node_of(data_node) == world_id, "世界编号与局内编号双向可逆")
				_check(graph.room_data(world_id) != null, "能取回房间数据")
				_check(graph.biome_of(world_id) >= 0, "房间有群系")
				_check(graph.kind_name_of(world_id) != "未知", "房间类型有名字")
		_check(seen.size() == floor.rooms.size(), "种子 %d 每个局内房间都进了骨架（%d / %d）" % [
			seed_value, seen.size(), floor.rooms.size(),
		])
		_check(graph.main_path.size() == graph.floors.size(), "每层一个主干节点")
		_check(graph.types.size() == floor.rooms.size(), "类型表覆盖全部房间")
		_check(graph.kind_name_of(graph.final_node()) == RoomKind.name_of(RoomKind.Kind.BOSS), "末层是 Boss 房")


## 适配后的骨架必须过世界层的全部硬校验，否则玩到一半会走进死路。
func _test_validate_sweep() -> void:
	var configs: Array[RunMapConfig] = [RunMapConfig.prototype(), RunMapConfig.full()]
	for config: RunMapConfig in configs:
		for seed_value: int in range(1, SWEEP_SEEDS + 1):
			for floor_index: int in SWEEP_FLOORS:
				var floor: FloorData = RunMapGenerator.generate(seed_value, floor_index, config)
				var problems: PackedStringArray = MapValidator.validate(
					RunMapBuilder.build_from_floor(seed_value, floor, MapConfig.new())
				)
				_check(problems.is_empty(), "种子 %d 层 %d 世界校验通过：%s" % [
					seed_value, floor_index, ", ".join(problems),
				])


## 世界生成器的出口是单向推进的：缺一条向前的门，后半层就会从起点断开。
func _test_forward_exits() -> void:
	for seed_value: int in SEEDS:
		var graph: FloorRoomGraph = _plan(seed_value, 0)
		var final: int = graph.final_node()
		for world_id: int in graph.types.keys():
			if world_id == final:
				continue
			var targets: PackedInt32Array = graph.next_nodes[world_id]
			_check(not targets.is_empty(), "种子 %d 节点 %d 不是死路" % [seed_value, world_id])
			_check(targets.size() <= 3, "种子 %d 节点 %d 出口不超过 3 条" % [seed_value, world_id])
			var forward: int = 0
			for target: int in targets:
				if RunGraph.floor_of(target) > RunGraph.floor_of(world_id):
					forward += 1
			var room: RoomData = graph.room_data(world_id)
			if room != null and room.kind == RoomKind.Kind.SECRET:
				_check(forward == 0, "秘密房没有向前的出口")
			else:
				_check(forward >= 1, "种子 %d 节点 %d 至少有一条向前的门" % [seed_value, world_id])


## 秘密房与宿主同层、占变体 1；它没有普通门，必须由宿主开出一条侧门。
func _test_secret_side_door() -> void:
	for seed_value: int in SEEDS:
		var graph: FloorRoomGraph = _plan(seed_value, 0)
		var secrets: int = 0
		for room: RoomData in graph.floor.rooms:
			if room.kind != RoomKind.Kind.SECRET:
				continue
			secrets += 1
			var secret: int = graph.world_node_of(room.node_id)
			_check(secret >= 0, "秘密房有世界编号")
			_check(RunGraph.variant_of(secret) == RunGraph.BRANCH_VARIANT, "秘密房占变体 1")
			var host: int = -1
			for neighbour: int in graph.floor.neighbours(room.node_id):
				if neighbour != room.node_id:
					host = graph.world_node_of(neighbour)
					break
			_check(host >= 0, "秘密房有宿主")
			if host < 0:
				continue
			_check(RunGraph.floor_of(secret) == RunGraph.floor_of(host), "秘密房与宿主同层")
			_check(graph.next_nodes[host].has(secret), "宿主开出一条通往秘密房的门")
			_check(graph.next_nodes[secret].has(host), "秘密房回落到宿主")
			_check(graph.room_data(secret).kind == RoomKind.Kind.SECRET, "秘密房数据挂对了")
		_check(secrets == RunMapConfig.prototype().secret_rooms, "种子 %d 秘密房数量与配置一致" % seed_value)


## 清空房间后的选门面板：列出门、显示材料预告与抗性 / 弱点、点击回传局内编号。
func _test_door_panel() -> void:
	var graph: FloorRoomGraph = _plan(20261008, 0)
	var busiest: RoomData = null
	for room: RoomData in graph.floor.rooms:
		if room.kind == RoomKind.Kind.SECRET or room.kind == RoomKind.Kind.BOSS:
			continue
		if busiest == null or room.doors.size() > busiest.doors.size():
			busiest = room
	_check(busiest != null and not busiest.doors.is_empty(), "有一间房带门")
	if busiest == null or busiest.doors.is_empty():
		return

	var panel := DoorChoicePanel.new()
	root.add_child(panel)
	_check(not panel.is_showing(), "面板默认隐藏")
	panel.door_chosen.connect(_on_door_chosen)

	panel.show_choices(busiest)
	_check(panel.is_showing(), "有门时面板显示")
	_check(panel.row_count() == busiest.doors.size(), "行数与门数一致（%d）" % busiest.doors.size())
	_check(panel.row_count() >= 1 and panel.row_count() <= 3, "列出 1~3 条路线")

	var list: Node = panel.find_child("Doors", true, false)
	_check(list != null and list.get_child_count() == busiest.doors.size(), "门列表行数正确")
	if list != null and list.get_child_count() > 0:
		var row: Button = list.get_child(0) as Button
		var text: String = " ".join(_labels_of(row))
		_check(text.contains(busiest.doors[0].room_kind_name()), "行首显示房间类型")
		_check(text.contains("材料"), "行有材料预告")
		_check(text.contains("抗性") and text.contains("弱点"), "行有抗性 / 弱点")
		_chosen.clear()
		row.pressed.emit()
		_check(_chosen.size() == 1 and _chosen[0] == busiest.doors[0].to_node, "点击行回传局内地图 node_id")

	panel.hide_choices()
	_check(not panel.is_showing() and panel.row_count() == 0, "隐藏后面板清空")
	_check(_plan(20261008, 0).world_node_of(busiest.doors[0].to_node) >= 0, "门目标能换算成世界编号")
	panel.queue_free()


func _labels_of(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is Label:
		out.append((node as Label).text)
	for child: Node in node.get_children():
		out.append_array(_labels_of(child))
	return out
