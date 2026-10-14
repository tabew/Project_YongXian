extends SceneTree

## 场景元素 / 可破坏物单元测试：配置同族、点位规划、元素吸附与可破坏物掉落。
##
## godot --headless --path . --script res://tests/test_room_props.gd

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
	_test_catalog_family()
	_test_plan_validity()
	_test_plan_determinism()
	_test_element_node()
	_test_breakable_node()
	print("ROOM PROPS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 吸附产出的材料必须与元素词条同族，且材料都在材料表里注册。
func _test_catalog_family() -> void:
	for entry: Dictionary in SceneElementCatalog.ELEMENTS:
		var id: StringName = entry["id"]
		var material_id: int = SceneElementCatalog.material_of(id)
		_check(MaterialCatalog.has_material(material_id), "元素材料已注册：%s -> %d" % [String(id), material_id])
		if not MaterialCatalog.has_material(material_id):
			continue
		var element_traits: Array = SceneElementCatalog.traits_of(id)
		if element_traits.is_empty():
			continue
		var material_traits: Array = MaterialCatalog.definition_of(material_id).get("traits", [])
		var shared: bool = false
		for trait_id: StringName in element_traits:
			for material_trait: Dictionary in material_traits:
				if StringName(material_trait.get("id", &"")) == trait_id:
					shared = true
		_check(shared, "元素词条与材料同族：%s" % String(id))
	for entry: Dictionary in BreakableCatalog.BREAKABLES:
		var id: StringName = entry["id"]
		_check(MaterialCatalog.has_material(BreakableCatalog.material_of(id)), "可破坏物材料已注册：%s" % String(id))


## 规划出的点位必须可走、非水、离门口够远、彼此留间距，且数量受配额约束。
func _test_plan_validity() -> void:
	_check(RoomProps.plan(null, null, null).is_empty(), "空输入返回空计划")
	var total_elements: int = 0
	var total_breakables: int = 0
	for seed_value: int in SEEDS:
		var generator: WorldGenerator = RunMapBuilder.build(seed_value, 0, RunMapConfig.prototype(), MapConfig.new())
		_check(generator != null and generator.run != null, "世界可装配：%d" % seed_value)
		if generator == null or generator.run == null:
			continue
		for world_id: int in _all_world_ids(generator):
			var room: RoomData = generator.run.room_data(world_id)
			var spec: MapSpec = generator.map_spec(world_id)
			if room == null or spec == null:
				continue
			var plan: Array[Dictionary] = RoomProps.plan(generator, spec, room)
			var elements: int = 0
			var breakables: int = 0
			var blocked: Array[Vector2i] = [WorldGenerator.world_to_tile(generator.entry_position(world_id))]
			for link: Dictionary in generator.gate_links(world_id):
				blocked.append(link["point"])
			var tiles: Array[Vector2i] = []
			for entry: Dictionary in plan:
				var kind: int = int(entry["kind"])
				var tile: Vector2i = entry["tile"]
				var local: Vector2i = tile - spec.origin
				if kind == RoomProps.Kind.ELEMENT:
					elements += 1
					_check(SceneElementCatalog.has_element(entry["id"]), "元素 id 已配置：%s" % String(entry["id"]))
				else:
					breakables += 1
					_check(BreakableCatalog.has_breakable(entry["id"]), "可破坏物 id 已配置：%s" % String(entry["id"]))
				_check(MaterialCatalog.has_material(int(entry["material_id"])), "点位材料已注册：%d" % world_id)
				_check(int(entry["amount"]) >= 1, "点位数量至少 1：%d" % world_id)
				_check(spec.contains_local(local.x, local.y), "点位在箱庭内：%d" % world_id)
				_check(generator.is_walkable(tile), "点位可走：%d" % world_id)
				_check(not Terrain.is_water(generator.sample_terrain(tile)), "点位不在水里：%d" % world_id)
				for point: Vector2i in blocked:
					var delta: Vector2i = tile - point
					_check(maxi(absi(delta.x), absi(delta.y)) > RoomProps.SAFE_RADIUS, "点位离入口/出口够远：%d" % world_id)
				tiles.append(tile)
			_check(elements <= RoomProps.MAX_ELEMENTS, "元素数量不超上限：%d" % world_id)
			_check(breakables <= RoomProps.MAX_BREAKABLES, "可破坏物数量不超上限：%d" % world_id)
			for index: int in tiles.size():
				for other_index: int in range(index + 1, tiles.size()):
					_check(Vector2(tiles[index] - tiles[other_index]).length_squared() >= RoomProps.MIN_SPACING * RoomProps.MIN_SPACING, "点位间距达标：%d" % world_id)
			total_elements += elements
			total_breakables += breakables
	_check(total_elements > 0, "原型层至少铺出 1 个场景元素")
	_check(total_breakables > 0, "原型层至少铺出 1 个可破坏物")


## 同种子两次装配与规划的结果必须完全一致。
func _test_plan_determinism() -> void:
	var first: WorldGenerator = RunMapBuilder.build(20261014, 0, RunMapConfig.prototype(), MapConfig.new())
	var second: WorldGenerator = RunMapBuilder.build(20261014, 0, RunMapConfig.prototype(), MapConfig.new())
	var first_ids: Array[int] = _all_world_ids(first)
	var second_ids: Array[int] = _all_world_ids(second)
	_check(first_ids == second_ids, "两次装配的房间编号一致")
	for index: int in mini(first_ids.size(), second_ids.size()):
		var world_id: int = first_ids[index]
		var other_id: int = second_ids[index]
		var plan_a: Array[Dictionary] = RoomProps.plan(first, first.map_spec(world_id), first.run.room_data(world_id))
		var plan_b: Array[Dictionary] = RoomProps.plan(second, second.map_spec(other_id), second.run.room_data(other_id))
		var identical: bool = plan_a.size() == plan_b.size()
		if identical:
			for entry_index: int in plan_a.size():
				var a: Dictionary = plan_a[entry_index]
				var b: Dictionary = plan_b[entry_index]
				if a["kind"] != b["kind"] or a["id"] != b["id"] or a["tile"] != b["tile"] or a["material_id"] != b["material_id"] or a["amount"] != b["amount"]:
					identical = false
		_check(identical, "同种子点位一致：%d" % world_id)


## 元素节点：长按进度 → 产出材料 → 冷却 → 可再次吸附。
func _test_element_node() -> void:
	var element := SceneElement.new()
	root.add_child(element)
	element.bind({"id": &"brazier", "material_id": 1002, "amount": 1, "traits": [&"fire"]})
	_check(element.display_name == "火盆", "元素名字来自配置表")
	_check(element.can_interact_from(element.global_position), "贴脸可交互")
	_check(not element.can_interact_from(element.global_position + Vector2(SceneElement.INTERACT_RADIUS + 8.0, 0.0)), "超出半径不可交互")
	var produced: Dictionary = element.advance_hold(SceneElement.HOLD_SECONDS * 0.5)
	_check(produced.is_empty(), "长按一半不产出")
	_check(element.hold_ratio() > 0.4 and element.hold_ratio() < 0.6, "长按进度可读")
	element.set_highlighted(true)
	element.set_highlighted(false)
	_check(element.hold_ratio() == 0.0, "取消高亮清零长按")
	produced = element.advance_hold(SceneElement.HOLD_SECONDS)
	_check(int(produced.get("material_id", -1)) == 1002 and int(produced.get("amount", 0)) == 1, "长按到底产出材料")
	_check(not element.is_ready_to_absorb(), "产出后进入冷却")
	_check(not element.can_interact_from(element.global_position), "冷却中不可交互")
	_check(element.cooldown_ratio() == 1.0, "冷却从满开始")
	element._process(SceneElement.COOLDOWN_SECONDS + 0.01)
	_check(element.is_ready_to_absorb(), "冷却结束可再次吸附")
	_check(element.cooldown_ratio() == 0.0, "冷却归零")
	element.queue_free()


## 可破坏物节点：受击到零血 → 广播携带材料与数量。
func _test_breakable_node() -> void:
	var prop := BreakableProp.new()
	root.add_child(prop)
	prop.bind({"id": &"wooden_crate", "material_id": 1013, "amount": 2})
	_check(prop.display_name == "木箱", "可破坏物名字来自配置表")
	_check(prop.health != null and prop.health.max_health == BreakableProp.DEFAULT_HEALTH, "血量已建立")
	var events: Array = []
	prop.broken.connect(func(prop_id: StringName, material_id: int, amount: int) -> void: events.append([prop_id, material_id, amount]))
	var hit := CombatHit.new()
	hit.damage = BreakableProp.DEFAULT_HEALTH + 1.0
	prop.health.receive_hit(hit)
	_check(prop.is_broken(), "打碎后标记完成")
	_check(events.size() == 1, "打碎广播一次")
	if events.size() == 1:
		_check(events[0][0] == &"wooden_crate" and int(events[0][1]) == 1013 and int(events[0][2]) == 2, "打碎携带材料与数量")
	prop.queue_free()


func _all_world_ids(generator: WorldGenerator) -> Array[int]:
	var result: Array[int] = []
	for ids: PackedInt32Array in generator.run.floors:
		for node_id: int in ids:
			result.append(node_id)
	return result
