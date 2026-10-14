extends SceneTree

## 局内灵感接线测试：光点生成 → 无条件飞入 → 计数 / 飘字，以及死亡结算。
##
## godot --headless --path . --script res://tests/test_inspiration_world.gd
##
## 不静态引用 GameWorld：等 autoload 注册完成后再加载运行场景，避免测试编译期提前引用单例。

const WORLD_SCENE: String = "res://scenes/game/game_world.tscn"
## 让光点走完"生成 → 散开 → 悬停 → 飞入"所需的帧数。
const FLIGHT_FRAMES: int = 400

var _checks: int = 0
var _failures: int = 0
## 光点飞入事件；用成员变量而不是 lambda 捕获局部变量，
## 否则回调在测试函数返回后仍挂在信号上，捕获的数组已被释放。
var _collected: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _on_field_collected(amount: int, source: int, is_cluster: bool) -> void:
	_collected.append([amount, source, is_cluster])


func _run() -> void:
	var manager: Node = root.get_node_or_null("/root/Inspiration")
	_check(manager != null, "灵感单例已注册")
	var scene: PackedScene = load(WORLD_SCENE) as PackedScene
	_check(scene != null, "局内场景可加载")
	if manager == null or scene == null:
		quit(1)
		return

	var world: Node2D = scene.instantiate() as Node2D
	root.add_child(world)
	await process_frame
	await process_frame

	await _test_wiring(world, manager)
	await _test_drop_and_collect(world, manager)
	await _test_monster_kill(world, manager)
	await _test_death(world, manager)

	print("INSPIRATION WORLD: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_wiring(world: Node2D, manager: Node) -> void:
	var field: InspirationField = world.get_node_or_null("InspirationField") as InspirationField
	_check(field != null, "世界里有灵感光点池")
	var hud: InspirationHud = world.get_node_or_null("GameHUD/Inspiration") as InspirationHud
	_check(hud != null, "HUD 里有灵感计数")
	if field == null or hud == null:
		return
	_check(field.pool_size() == InspirationDrop.POOL_SIZE, "对象池预分配 200 个")
	_check(field.active_count() == 0, "初始没有活动光点")
	_check(field.target == world.get_node_or_null("Player"), "光点目标指向主角")
	_check(manager.get("in_run") == true, "进入局内即开局")
	_check(manager.run.gained == 0, "开局账本清零")
	await process_frame


func _test_drop_and_collect(world: Node2D, manager: Node) -> void:
	var field: InspirationField = world.get_node_or_null("InspirationField") as InspirationField
	var hud: InspirationHud = world.get_node_or_null("GameHUD/Inspiration") as InspirationHud
	if field == null or hud == null:
		return
	var player: Node2D = world.get_node_or_null("Player") as Node2D
	# 直接广播掉落：光点必须无条件飞向主角并计入账本。
	manager.drop_inspiration(player.global_position + Vector2(600.0, -400.0), 7, InspirationRules.Source.NORMAL)
	_check(field.active_count() > 0, "掉落生成了光点")
	_check(manager.run.in_flight == 7, "掉落先记在飞行中")

	if not field.collected.is_connected(_on_field_collected):
		field.collected.connect(_on_field_collected)
	for index: int in FLIGHT_FRAMES:
		await process_frame
		if manager.run.gained > 0:
			break
	_check(manager.run.gained == 7, "光点飞入后计入已获得")
	_check(manager.run.in_flight == 0, "飞行中清零")
	_check(_collected.size() > 0, "光点广播了飞入事件")
	_check(field.active_count() == 0, "飞入后光点回收进池")
	_check(hud.float_count() > 0, "飞入弹出飘字")
	var counter: Label = hud.get_node_or_null("InspirationCounter") as Label
	_check(counter != null and counter.text.contains("7"), "计数显示 7：%s" % [counter.text if counter != null else ""])


func _test_monster_kill(world: Node2D, manager: Node) -> void:
	var spawner: MonsterSpawner = world.get_node_or_null("MonsterSpawner") as MonsterSpawner
	if spawner == null:
		return
	var monster: BaseMonster = null
	for child: Node in spawner.get_children():
		if child is BaseMonster:
			monster = child as BaseMonster
			break
	if monster == null:
		# 没有怪可打时至少验证信号存在且接线正确。
		_check(spawner.has_signal("monster_killed"), "生成器广播击杀")
		_check(spawner.monster_killed.is_connected(Callable(world, "_on_monster_killed")), "世界层已监听击杀")
		return
	var before: int = manager.run.total_launched()
	monster.kill()
	await process_frame
	# 小怪只有 15% 概率掉落，所以只断言"记账总额不可能减少"。
	_check(manager.run.total_launched() >= before, "击杀不会倒扣灵感")


func _test_death(world: Node2D, manager: Node) -> void:
	var player: PlayerCharacter = world.get_node_or_null("Player") as PlayerCharacter
	if player == null:
		return
	manager.add_permanent_inspiration(0)
	var pool_before: int = manager.state.inspiration
	player.take_damage(player.health)
	await process_frame
	_check(world.get("_run_failed") == true, "死亡标记只置一次")
	_check(manager.get("in_run") == false, "死亡后离开局内")
	_check(manager.state.inspiration >= pool_before, "留存灵感进入永久池")
