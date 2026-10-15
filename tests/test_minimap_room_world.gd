extends SceneTree

## 小地图 → 房间系统的运行时接线：进过的房间才显示房型，没进过的一律问号。
##
## godot --headless --path . --script res://tests/test_minimap_room_world.gd
##
## 不静态引用 GameWorld：等 autoload 注册完成后再加载运行场景，避免测试编译期提前引用单例。

const WORLD_SCENE: String = "res://scenes/game/game_world.tscn"

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
	var scene: PackedScene = load(WORLD_SCENE) as PackedScene
	_check(scene != null, "局内场景可加载")
	if scene == null:
		quit(1)
		return
	var world: Node2D = scene.instantiate() as Node2D
	root.add_child(world)
	world.set_process(false)
	var player: Node2D = world.get("player") as Node2D
	if player != null:
		player.set_physics_process(false)
	var spawner: Node = world.get("monster_spawner") as Node
	if spawner != null:
		spawner.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	await process_frame

	await _test_binding(world)

	print("MINIMAP ROOM WORLD: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 开局：小地图绑的是本层房间图，起点算已探索，其余房间都是问号。
func _test_binding(world: Node2D) -> void:
	var generator: WorldGenerator = world.get("_generator") as WorldGenerator
	_check(generator != null, "世界生成器已就绪")
	if generator == null:
		return
	var graph: FloorRoomGraph = generator.run as FloorRoomGraph
	var minimap: Minimap = world.get_node_or_null("GameHUD/HUD/Minimap") as Minimap
	_check(minimap != null, "HUD 上有小地图")
	_check(graph != null, "本层房间图已生成")
	if minimap == null or graph == null:
		return
	var start: int = graph.start_node()

	_check(minimap._graph == graph, "小地图绑定本层房间图，不再采样地形")
	_check(minimap._slots.size() == graph.types.size(), "小地图槽位覆盖全部房间")
	_check(minimap._current_node == start, "小地图当前房间 = 起点")
	_check(minimap.visible_nodes().has(start), "紧凑模式窗口包含起点")

	var visited: Dictionary = world.get("_visited_rooms")
	_check(visited.has(start), "起点记入已探索")
	_check(visited.size() == 1, "开局只探索了起点（%d）" % visited.size())
	_check(minimap._visited.has(start), "已探索状态已推给小地图")
	_check(_glyph_of(graph, minimap, start) != MinimapLayout.UNKNOWN_GLYPH, "起点显示房型图标")

	var unvisited: int = _find_unvisited(graph, visited)
	_check(unvisited >= 0, "本局有未进入的房间")
	if unvisited >= 0:
		_check(_glyph_of(graph, minimap, unvisited) == MinimapLayout.UNKNOWN_GLYPH, "没进过的房间显示问号")

	# 走进下一个房间：已探索表增长，小地图跟着更新，当前房间跟着高亮。
	var target: int = _forward_target(graph, start)
	_check(target >= 0, "起点有向前的门")
	if target < 0:
		return
	world.call("_enter_map", target)
	await process_frame
	var after: Dictionary = world.get("_visited_rooms")
	_check(after.has(target), "新房间记入已探索")
	_check(after.size() == 2, "已探索表只多一个房间（%d）" % after.size())
	_check(minimap._current_node == target, "小地图当前房间已切换")
	_check(minimap._visited.has(target), "小地图拿到新房间的已探索状态")
	_check(_glyph_of(graph, minimap, target) != MinimapLayout.UNKNOWN_GLYPH, "新房间显示房型图标")

	# 展开 / 收回：展开画整层，收回回到右上角紧凑窗口。
	minimap.set_expanded(true)
	_check(minimap.is_expanded(), "按 M 展开全屏房间图")
	_check(minimap.visible_nodes().size() == graph.types.size(), "展开模式画出整层房间")
	minimap.set_expanded(false)
	_check(not minimap.is_expanded(), "再按 M 收回右上角")
	_check(
		minimap.visible_nodes() == MinimapLayout.window_nodes(minimap._slots, target, 2),
		"收回后只剩当前房间前后各 2 列"
	)


## 房间在小地图上的实际字符：未探索是问号，已探索是房型汉字。
func _glyph_of(graph: FloorRoomGraph, minimap: Minimap, node_id: int) -> String:
	return MinimapLayout.glyph_for(MinimapLayout.kind_of(graph, node_id), minimap._visited.has(node_id))


func _find_unvisited(graph: FloorRoomGraph, visited: Dictionary) -> int:
	for node_id: int in graph.types.keys():
		if not visited.has(node_id):
			return node_id
	return -1


func _forward_target(graph: FloorRoomGraph, node_id: int) -> int:
	var targets: PackedInt32Array = graph.next_nodes.get(node_id, PackedInt32Array())
	return int(targets[0]) if not targets.is_empty() else -1
