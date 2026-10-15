extends SceneTree

## 秘密房词条门单元测试：需求表、词条判定、出口封闭与开门流程。
##
## godot --headless --path . --script res://tests/test_secret_door.gd

const SEEDS: Array[int] = [1, 7, 99, 20261014, 424242]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_test_requirements()
	_test_matches()
	_test_levels_from()
	_test_text()
	_test_world_binding()
	_test_door_node()
	print("SECRET DOOR: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 8 种门的名称唯一，且需求词条都在词条表里注册、等级至少 1。
func _test_requirements() -> void:
	_check(SecretDoor.COUNT == 8, "词条门共 8 种")
	_check(SecretDoor.NAMES.size() == SecretDoor.COUNT, "名称表长度与门数一致")
	var seen: Dictionary = {}
	for kind: int in SecretDoor.COUNT:
		var name: String = SecretDoor.name_of(kind)
		_check(not name.is_empty(), "门有名称：%d" % kind)
		_check(not seen.has(name), "门名称唯一：%s" % name)
		seen[name] = true
		var trait_id: StringName = SecretDoor.trait_of(kind)
		_check(TraitCatalog.has_trait(trait_id), "需求词条已注册：%s -> %s" % [name, String(trait_id)])
		_check(SecretDoor.level_of(kind) >= 1, "需求等级至少 I：%s" % name)


## 判定语义：够等级开、超等级开、缺词条 / 等级不足不开。
func _test_matches() -> void:
	for kind: int in SecretDoor.COUNT:
		var trait_id: StringName = SecretDoor.trait_of(kind)
		var level: int = SecretDoor.level_of(kind)
		_check(SecretDoor.matches(kind, {trait_id: level}), "同级满足开门：%s" % SecretDoor.name_of(kind))
		_check(SecretDoor.matches(kind, {trait_id: level + 2}), "超额满足开门：%s" % SecretDoor.name_of(kind))
		_check(not SecretDoor.matches(kind, {}), "缺词条不开门：%s" % SecretDoor.name_of(kind))
		_check(not SecretDoor.matches(kind, {&"__none__": 9}), "无关词条不开门：%s" % SecretDoor.name_of(kind))
		if level > 1:
			_check(not SecretDoor.matches(kind, {trait_id: level - 1}), "等级不足不开门：%s" % SecretDoor.name_of(kind))
	_check(not SecretDoor.matches(-1, {}), "越界门类型返回 false")
	_check(not SecretDoor.matches(SecretDoor.COUNT, {}), "越界门类型返回 false")


## 词条快照压表：同词条取最高级，空 id 跳过，非字典条目忽略。
func _test_levels_from() -> void:
	var levels: Dictionary = SecretDoor.levels_from([
		{"id": &"fire", "level": 2},
		{"id": &"fire", "level": 4},
		{"id": &"ice", "level": 1},
		{"id": &"", "level": 5},
	])
	_check(int(levels.get(&"fire", 0)) == 4, "同词条取最高等级")
	_check(int(levels.get(&"ice", 0)) == 1, "其他词条保留")
	_check(not levels.has(&""), "空词条 id 不入表")
	_check(SecretDoor.levels_from([]).is_empty(), "空快照得到空表")
	var snapshot: Dictionary = SecretDoor.levels_from([{"id": &"fire", "level": 2}])
	_check(SecretDoor.matches(SecretDoor.Kind.FIRE, snapshot), "快照可直接用于判定")
	_check(not SecretDoor.matches(SecretDoor.Kind.ICE, snapshot), "快照只满足对应词条")


## 提示文案：词条名与门名都出现在文字里。
func _test_text() -> void:
	for kind: int in SecretDoor.COUNT:
		var trait_name: String = SecretDoor.trait_name_of(kind)
		_check(not trait_name.is_empty(), "词条有中文名：%d" % kind)
		var text: String = SecretDoor.requirement_text(kind)
		_check(text.contains(SecretDoor.name_of(kind)), "提示含门名：%s" % text)
		_check(text.contains(trait_name), "提示含词条名：%s" % text)


## 世界装配：宿主有词条门数据，秘密房是宿主的秘密子节点，且出口在 gate_links 里。
func _test_world_binding() -> void:
	for seed_value: int in SEEDS:
		var generator: WorldGenerator = RunMapBuilder.build(seed_value, 0, RunMapConfig.prototype(), MapConfig.new())
		var graph: FloorRoomGraph = generator.run as FloorRoomGraph
		_check(graph != null, "世界骨架是 FloorRoomGraph（种子 %d）" % seed_value)
		if graph == null:
			continue
		var hosts: int = 0
		var secret_total: int = 0
		for node_id: int in _all_world_ids(generator):
			var room: RoomData = graph.room_data(node_id)
			if room == null:
				continue
			var children: PackedInt32Array = graph.secret_targets_of(node_id)
			if room.kind == RoomKind.Kind.SECRET:
				secret_total += 1
				_check(children.is_empty(), "秘密房自己不带秘密子节点（%d）" % node_id)
				continue
			if not room.has_secret_door():
				_check(children.is_empty(), "普通房没有秘密子节点（%d）" % node_id)
				continue
			hosts += 1
			_check(children.size() == 1, "宿主只挂一个秘密房（%d）" % node_id)
			var target: int = int(children[0])
			var secret_room: RoomData = graph.room_data(target)
			_check(secret_room != null and secret_room.kind == RoomKind.Kind.SECRET, "宿主挂的是秘密房")
			_check(int(room.secret_door.get("target", -1)) == graph.data_node_of(target), "秘密门目标与房间图一致")
			var kind: int = int(room.secret_door.get("kind", -1))
			_check(kind >= 0 and kind < SecretDoor.COUNT, "秘密门类型合法")
			_check(String(room.secret_door.get("trait", "")) == String(SecretDoor.trait_of(kind)), "秘密门需求词条一致")
			_check(int(room.secret_door.get("level", 0)) == SecretDoor.level_of(kind), "秘密门需求等级一致")
			_check(String(room.secret_door.get("name", "")) == SecretDoor.name_of(kind), "秘密门名称一致")
			# 世界层要能从 gate_links 里找到这扇门来封路。
			var found: bool = false
			for link: Dictionary in generator.gate_links(node_id):
				if int(link["target"]) == target:
					found = true
					break
			_check(found, "宿主出口里有通往秘密房的连接（%d -> %d）" % [node_id, target])
		_check(hosts >= 1, "每层至少一个词条门（种子 %d）" % seed_value)
		_check(secret_total == hosts, "秘密房数量与词条门数量一致（种子 %d）" % seed_value)


## 门节点：没词条打不开，够词条一次开门并广播。
func _test_door_node() -> void:
	var levels: Dictionary = {}
	var door := SecretDoorProp.new()
	door.trait_levels_provider = func() -> Array:
		var entries: Array = []
		for trait_id: StringName in levels:
			entries.append({"id": trait_id, "level": int(levels[trait_id])})
		return entries
	door.bind(SecretDoor.Kind.EXPLODE, 4242)
	root.add_child(door)
	var trait_id: StringName = SecretDoor.trait_of(SecretDoor.Kind.EXPLODE)

	_check(door.target_world_node == 4242, "门绑定目标")
	_check(not door.can_open(), "没有词条时打不开")
	_check(not door.attempt_open(), "没有词条时 attempt_open 失败")
	_check(not door.is_open(), "失败后仍是关闭状态")

	levels[trait_id] = 0
	_check(not door.can_open(), "等级为 0 视为没有词条")

	levels[trait_id] = SecretDoor.level_of(SecretDoor.Kind.EXPLODE)
	_check(door.can_open(), "等级达标后可以打开")
	var opened: Array = []
	door.opened.connect(func(kind: int) -> void: opened.append(kind))
	_check(door.attempt_open(), "达标时开门成功")
	_check(door.is_open(), "开门后标记为已开")
	_check(opened.size() == 1 and int(opened[0]) == SecretDoor.Kind.EXPLODE, "开门广播一次且带门类型")
	_check(not door.attempt_open(), "重复开门不再触发")
	_check(not door.can_open(), "已开的门不再可开")
	door.queue_free()


func _all_world_ids(generator: WorldGenerator) -> Array[int]:
	var result: Array[int] = []
	for ids: PackedInt32Array in generator.run.floors:
		for node_id: int in ids:
			result.append(node_id)
	return result
