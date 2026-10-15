extends SceneTree

## 箱庭切换与远端战斗、探索和道具功能的集成回归。
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 24681357)
	var scene: PackedScene = load("res://scenes/game/game_world.tscn")
	var world: Node2D = scene.instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	# 此处检查切图状态保存；怪物攻击另由现有怪物回归验证。
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	var player: PlayerCharacter = world.player
	var minimap: Minimap = world.hud.minimap
	var bag: Node = world.get_node("GameHUD/BagUi")
	var alchemy: Node = world.get_node("GameHUD/Alchemy")
	_check(_training_dummy_count(world) == 0, "局内不再生成训练靶")
	_check(bag != null and alchemy != null, "背包和炼金界面保留")
	_check(player.weapon_controller.equipped_weapon.id == &"longsword", "原长剑配置保留")
	_check(player.equip_weapon_by_id(&"long_staff"), "按 id 装备武器接口仍可用")
	var equipped: WeaponDefinition = player.weapon_controller.equipped_weapon
	_check(equipped.id == &"long_staff", "原长棍配置仍可装备")
	_check((world.hud.get_node("WeaponLabel") as Label).text.contains(equipped.display_name), "原武器HUD信号仍同步")
	player.take_damage(3)
	var remaining_health: int = player.health
	var drop_scene: PackedScene = load("res://scenes/items/ingredients/herb.tscn")
	var drop: Node2D = drop_scene.instantiate() as Node2D
	world.monster_spawner.add_child(drop)
	drop.global_position = player.global_position + Vector2(24, 24)
	var drop_position: Vector2 = drop.global_position
	minimap.set_expanded(true)
	world._enter_map(2)
	_check(player.health == remaining_health, "切换箱庭不会恢复生命值")
	_check(player.weapon_controller.equipped_weapon == equipped, "切换箱庭保留装备")
	_check(is_instance_valid(drop) and not drop.is_visible_in_tree() and not drop.can_process(), "离图保存掉落物并隐藏暂停")
	_check(drop.global_position.is_equal_approx(drop_position), "保存掉落物不改变所属地图坐标")
	_check(minimap.is_expanded(), "切图保持全屏房间图")
	_check(world.get_node("GameHUD/BagUi") == bag and world.get_node("GameHUD/Alchemy") == alchemy, "切图保留背包与炼金实例")
	for _frame: int in range(20):
		await process_frame
	for child: Node in world.monster_spawner.get_children():
		if child is BaseMonster:
			var tile: Vector2i = WorldGenerator.world_to_tile((child as BaseMonster).global_position)
			var local: Vector2i = tile - player.active_map.origin
			_check(player.active_map.contains_local(local.x, local.y), "隐藏邻居预加载不会留下跨图怪物")
	world._enter_map(0)
	_check(drop.is_visible_in_tree() and drop.can_process(), "回原箱庭恢复地上掉落物")
	_check(drop.global_position.is_equal_approx(drop_position), "返回后掉落物位置保持")
	_check(player.health == remaining_health, "原路返回也不会补满生命")
	minimap.set_expanded(false)
	_check(
		minimap.visible_nodes() == MinimapLayout.window_nodes(minimap._slots, world._current_node, 2),
		"收起后回到当前房间前后各 2 列"
	)
	_check(minimap._graph == world._generator.run, "小地图始终绑当前局内房间图")
	player.collide_with_terrain = false
	var outside: Vector2 = WorldGenerator.tile_to_world(player.active_map.origin - Vector2i.ONE)
	_check(not player.can_stand_at(outside), "关闭地形碰撞仍不能进入箱庭间隙")
	player.velocity = Vector2(-player.max_speed, 0)
	player.global_position = WorldGenerator.tile_to_world(player.active_map.origin + Vector2i(0, int(player.active_map.center.y)))
	player._integrate_movement(1.0)
	var local_player: Vector2i = WorldGenerator.world_to_tile(player.global_position) - player.active_map.origin
	_check(player.active_map.contains_local(local_player.x, local_player.y), "关闭地形碰撞时移动仍受当前箱庭边界限制")
	world.build_world(97231)
	_check(player.health == player.max_health, "重建世界保持原生命重置行为")
	_check(world.get_node("GameHUD/BagUi") == bag and world.get_node("GameHUD/Alchemy") == alchemy, "重建地图不重建背包或炼金界面")
	_check(player.weapon_controller.weapon_changed.get_connections().size() == 1, "重建地图不重复绑定武器HUD")
	await process_frame
	_check(not is_instance_valid(drop), "重建世界清理上一世界地图掉落物")
	_check(_training_dummy_count(world) == 0, "重建世界也不会生成训练靶")
	world.queue_free()
	await process_frame
	print("MAP_INTEGRATION: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _training_dummy_count(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child is TrainingDummy:
			count += 1
	return count
