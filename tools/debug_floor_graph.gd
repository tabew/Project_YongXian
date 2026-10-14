extends SceneTree

## 打印一层局内地图适配成世界骨架后的结构，用于排查生成问题。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor: FloorData = RunMapGenerator.generate(20261008, 0, RunMapConfig.prototype())
	print("regions=", floor.regions.size(), " rooms=", floor.room_count(), " boss=", floor.boss_room != null)
	for region: RegionData in floor.regions:
		print("  区域 ", region.index, " ", region.theme_name(), " 房间数=", region.rooms.size())
	var graph: FloorRoomGraph = FloorRoomGraph.plan_from_floor(floor, MapConfig.new(), 20261008)
	print("floors=", graph.floors.size())
	for depth: int in graph.floors.size():
		var ids: PackedInt32Array = graph.floors[depth]
		var labels := PackedStringArray()
		for id: int in ids:
			labels.append("%d:%s" % [id, graph.kind_name_of(id)])
		print("  depth ", depth, " -> ", " ".join(labels) if not labels.is_empty() else "<空>")
	print("main_path=", graph.main_path.size(), " branches=", graph.branch_nodes.size())
	var problems: PackedStringArray = MapValidator.validate(RunMapBuilder.build_from_floor(20261008, floor, MapConfig.new()))
	print("validate=", "OK" if problems.is_empty() else ", ".join(problems))
	quit(0)
