extends SceneTree

## 局内地图生成单元测试：结构、保底、环路、门、热量曲线、确定性、配置表完整性。

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
	_test_catalog_integrity()
	_test_prototype_shape()
	_test_guarantees()
	_test_heat_curve()
	_test_connectivity_and_doors()
	_test_secret_room()
	_test_determinism()
	_test_full_config()
	print("RUN MAP: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 配置表之间不能出现悬空引用。
func _test_catalog_integrity() -> void:
	_check(RegionThemeCatalog.THEMES.size() == 13, "13 个区域主题")
	for theme_id: StringName in RegionThemeCatalog.ids():
		var theme: RegionTheme = RegionThemeCatalog.create(theme_id)
		_check(theme != null, "主题可实例化：" + String(theme_id))
		_check(not theme.material_ids.is_empty(), "主题有材料：" + String(theme_id))
		for material_id: int in theme.material_ids:
			_check(MaterialCatalog.has_material(material_id), "材料 %d 已注册（%s）" % [material_id, String(theme_id)])
		for element: StringName in theme.scene_elements:
			_check(SceneElementCatalog.has_element(element), "场景元素已配置：%s" % String(element))
	for element_id: StringName in [&"brazier", &"poison_pool", &"iron_bar", &"gear_pile", &"rift"]:
		_check(SceneElementCatalog.has_element(element_id), "核心场景元素存在：" + String(element_id))
	var seen_breakables: Dictionary = {}
	for theme_id: StringName in BreakableCatalog.THEME_BREAKABLES:
		for breakable_id: StringName in BreakableCatalog.THEME_BREAKABLES[theme_id]:
			seen_breakables[breakable_id] = true
	for breakable_id: StringName in seen_breakables:
		_check(BreakableCatalog.has_breakable(breakable_id), "可破坏物已配置：" + String(breakable_id))
		_check(MaterialCatalog.has_material(BreakableCatalog.material_of(breakable_id)), "可破坏物材料已注册：" + String(breakable_id))
	_check(RoomKind.COUNT == 10, "10 种房间类型")
	_check(RoomShape.COUNT == 7, "7 种房间形状")
	_check(SecretDoor.COUNT == 8, "8 种词条门")


func _test_prototype_shape() -> void:
	var floor: FloorData = RunMapGenerator.generate(20261014, 0, RunMapConfig.prototype())
	_check(floor.regions.size() >= 2 and floor.regions.size() <= 3, "每层 2~3 个区域")
	for region: RegionData in floor.regions:
		_check(region.room_count() >= 4 and region.room_count() <= 6, "原型每区域 4~6 房间")
	_check(floor.regions[0].theme_id == &"poison_swamp", "首个区域是毒沼")
	_check(floor.regions[1].theme_id == &"mine", "第二个区域是矿洞")
	_check(floor.boss_room != null and floor.boss_room.kind == RoomKind.Kind.BOSS, "存在 Boss 房")
	_check(floor.start_room() != null and floor.start_room().depth == 0, "起点深度为 0")


func _test_guarantees() -> void:
	for seed_value: int in [1, 7, 99, 20261014, 424242]:
		var floor: FloorData = RunMapGenerator.generate(seed_value, 0, RunMapConfig.prototype())
		var decisions: Dictionary = {}
		for room: RoomData in floor.rooms:
			decisions[room.decision()] = true
		for required: int in [RoomKind.Decision.SUSTAIN, RoomKind.Decision.SWITCH, RoomKind.Decision.LURE, RoomKind.Decision.COOL]:
			_check(decisions.has(required), "种子 %d 保底决策 %d" % [seed_value, required])
		var secret_count: int = 0
		for room: RoomData in floor.rooms:
			if room.kind == RoomKind.Kind.SECRET:
				secret_count += 1
		_check(secret_count == 1, "种子 %d 恰有 1 个秘密房" % seed_value)


## 每 3~4 个战斗房后必须有冷却窗口。
func _test_heat_curve() -> void:
	var config := RunMapConfig.prototype()
	for seed_value: int in [3, 17, 555, 90210]:
		var floor: FloorData = RunMapGenerator.generate(seed_value, 0, config)
		var streak: int = 0
		var worst: int = 0
		for region: RegionData in floor.regions:
			for room: RoomData in region.rooms:
				if RoomKind.is_combat(room.kind):
					streak += 1
					worst = maxi(worst, streak)
				else:
					streak = 0
		_check(worst <= config.combat_run_limit, "种子 %d 连续战斗房不超过 %d（实际 %d）" % [seed_value, config.combat_run_limit, worst])


func _test_connectivity_and_doors() -> void:
	for seed_value: int in [2, 42, 777, 31337]:
		var floor: FloorData = RunMapGenerator.generate(seed_value, 0, RunMapConfig.prototype())
		_check(floor.is_fully_connected(), "种子 %d 全层连通" % seed_value)
		for room: RoomData in floor.rooms:
			if room.kind == RoomKind.Kind.SECRET or room.kind == RoomKind.Kind.BOSS:
				continue
			_check(room.doors.size() >= 1 and room.doors.size() <= 3, "种子 %d 房间 %d 有 1~3 个门（实际 %d）" % [seed_value, room.node_id, room.doors.size()])
			for door: DoorInfo in room.doors:
				_check(door.to_node != room.node_id, "门不指向自己")
				_check(floor.room_of(door.to_node) != null, "门目标存在")
				_check(door.theme_id == floor.room_of(door.to_node).theme_id, "门主题与目标房一致")
				_check(not door.material_preview.is_empty(), "门有材料预告")
				_check(not door.resistance.is_empty() or not door.weakness.is_empty(), "门有抗性/弱点信息")


func _test_secret_room() -> void:
	var floor: FloorData = RunMapGenerator.generate(20261014, 0, RunMapConfig.prototype())
	var hosts: int = 0
	for room: RoomData in floor.rooms:
		if not room.has_secret_door():
			continue
		hosts += 1
		var target: RoomData = floor.room_of(int(room.secret_door["target"]))
		_check(target != null and target.kind == RoomKind.Kind.SECRET, "词条门通向秘密房")
		var door_kind: int = int(room.secret_door["kind"])
		_check(SecretDoor.trait_of(door_kind) != &"", "词条门有需求词条")
		_check(SecretDoor.matches(door_kind, {SecretDoor.trait_of(door_kind): 1}), "满足词条即可开门")
		_check(not SecretDoor.matches(door_kind, {}), "无词条打不开门")
		for door: DoorInfo in room.doors:
			_check(door.to_node != target.node_id, "秘密房不出现在普通门里")
	_check(hosts == 1, "恰有一个词条门入口")


func _test_determinism() -> void:
	var a: FloorData = RunMapGenerator.generate(123456, 0, RunMapConfig.prototype())
	var b: FloorData = RunMapGenerator.generate(123456, 0, RunMapConfig.prototype())
	_check(_signature(a) == _signature(b), "同种子结果一致")
	var c: FloorData = RunMapGenerator.generate(123457, 0, RunMapConfig.prototype())
	_check(_signature(a) != _signature(c), "不同种子结果不同")


func _test_full_config() -> void:
	var config := RunMapConfig.full()
	for seed_value: int in [11, 22, 33]:
		var floor: FloorData = RunMapGenerator.generate(seed_value, 2, config)
		_check(floor.regions.size() >= config.min_regions and floor.regions.size() <= config.max_regions, "默认配置区域数在范围内")
		for region: RegionData in floor.regions:
			_check(region.room_count() >= config.min_rooms and region.room_count() <= config.max_rooms, "默认配置房间数在范围内")
		_check(floor.is_fully_connected(), "默认配置全层连通")
		var themes: Dictionary = {}
		for region: RegionData in floor.regions:
			themes[region.theme_id] = true
		_check(themes.size() == floor.regions.size(), "同层区域主题不重复")


func _signature(floor: FloorData) -> String:
	var parts := PackedStringArray()
	for room: RoomData in floor.rooms:
		parts.append("%d/%d/%d/%d" % [room.node_id, room.kind, room.shape, room.doors.size()])
	return "|".join(parts)
