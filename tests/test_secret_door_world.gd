extends SceneTree

## 秘密房词条门的运行时接线测试：宿主房立门、未开门封路、开门后放行。
##
## godot --headless --path . --script res://tests/test_secret_door_world.gd
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
	await process_frame
	await process_frame

	await _test_host_gate(world)

	print("SECRET DOOR WORLD: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 进宿主房立门 → 出口被封 → 带词条开门 → 出口放行。
func _test_host_gate(world: Node2D) -> void:
	var generator: WorldGenerator = world.get("_generator") as WorldGenerator
	_check(generator != null, "世界生成器已就绪")
	if generator == null:
		return
	var graph: FloorRoomGraph = generator.run as FloorRoomGraph
	var host: int = _find_host(graph)
	var secret: int = -1
	if host >= 0:
		secret = int(graph.secret_targets_of(host)[0])
	_check(host >= 0 and secret >= 0, "本局存在词条门宿主与秘密房")
	if host < 0 or secret < 0:
		return

	# 进宿主房，房间道具与词条门应当随之生成。
	world.call("_enter_map", host)
	await process_frame
	await process_frame
	var door: SecretDoorProp = _find_closed_door(world)
	_check(door != null, "宿主房立起了词条门")
	if door == null:
		return
	_check(door.target_world_node == secret, "词条门指向秘密房")
	var kind: int = int(graph.room_data(host).secret_door.get("kind", -1))
	_check(door.kind == kind, "词条门类型与房间数据一致")

	# 没有词条时：门打不开，出口被封住，玩家只能走别的门。
	_check(not door.can_open(), "没有对应词条时打不开")
	_check(not door.attempt_open(), "没有对应词条时 attempt_open 失败")
	_check(bool(world.call("_is_sealed_secret_gate", secret)), "未开门时该出口被封")

	# 注入满足条件的词条后开门：出口放行，本局记录已开。
	var trait_id: StringName = SecretDoor.trait_of(kind)
	var level: int = SecretDoor.level_of(kind)
	door.trait_levels_provider = func() -> Array:
		return [{"id": trait_id, "level": level}]
	_check(door.can_open(), "带对应词条后可以打开")
	_check(door.attempt_open(), "带对应词条时开门成功")
	await process_frame
	_check(not bool(world.call("_is_sealed_secret_gate", secret)), "开门后出口放行")
	var opened: Dictionary = world.get("_opened_secret_doors")
	_check(opened != null and opened.has(secret), "本局记录了已开的门")

	# 进秘密房：它自己没有秘密子节点，回程出口不该被封。
	world.call("_enter_map", secret)
	await process_frame
	await process_frame
	_check(not bool(world.call("_is_sealed_secret_gate", host)), "秘密房回宿主的出口不被封")
	_check(_find_closed_door(world) == null, "秘密房里不再生成词条门")


## 本局第一个挂着秘密房的宿主世界 node_id。
func _find_host(graph: FloorRoomGraph) -> int:
	if graph == null:
		return -1
	for ids: PackedInt32Array in graph.floors:
		for node_id: int in ids:
			if not graph.secret_targets_of(node_id).is_empty():
				return node_id
	return -1


## 当前场上的词条门；跨所有地图实体根查找，避免依赖具体父节点。
## 只认还没开的门：开过的门要留到淡出动画结束才释放，不算「还立着」。
func _find_closed_door(tree_root: Node) -> SecretDoorProp:
	for node: Node in tree_root.get_tree().get_nodes_in_group("secret_doors"):
		var door: SecretDoorProp = node as SecretDoorProp
		if door != null and not door.is_open():
			return door
	return null
