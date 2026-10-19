extends SceneTree

## godot --headless --path . --script res://tools/test_event_types.gd
##
## 所有可交互事件和可拆解陷阱的运行时验收。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").set("world_seed", 24681357)
	var world: Node = (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("GameHUD/BagUi").hide()
	world.get_node("GameHUD/Alchemy").hide()
	var player: PlayerCharacter = world.player

	# 炼金残影：送药水
	var spirit := AlchemySpiritEvent.new()
	_add_event(world, spirit, &"alchemy_spirit", 1)
	var before: int = _inventory_total(player.inventory)
	_check(spirit.prompt_text().contains("炼金残影"), "alchemy_spirit_prompt")
	_check(spirit.interact(player), "alchemy_spirit_interact")
	_check(spirit.consumed and not spirit.visible, "alchemy_spirit_finishes")
	_check(_inventory_total(player.inventory) > before, "alchemy_spirit_rewards")

	# 可疑药水：第一次调查，第二次拿取；至少有一个种子会触发偷窃
	player.inventory.add_item(0, 5)
	var theft_tested: bool = false
	for seed_value: int in range(1, 31):
		var suspicious := SuspiciousPotionEvent.new()
		_add_event(world, suspicious, &"suspicious_potion", seed_value)
		_check(suspicious.interact(player), "suspicious_potion_reveal")
		_check(suspicious.prompt_text().contains("拿走"), "suspicious_potion_second_prompt")
		_check(suspicious.interact(player), "suspicious_potion_take")
		if suspicious.prompt_text().contains("取回"):
			theft_tested = true
			var after_theft: int = _inventory_total(player.inventory)
			_check(suspicious.interact(player), "suspicious_potion_recover")
			_check(suspicious.consumed, "suspicious_potion_recover_finishes")
			_check(_inventory_total(player.inventory) > after_theft, "suspicious_potion_returns_item")
			suspicious.queue_free()
			break
		suspicious.queue_free()
	_check(theft_tested, "suspicious_potion_can_steal")

	# 捕兽夹：踩到受伤，拆解拿石头
	var bear := BearTrapEvent.new()
	_add_event(world, bear, &"bear_trap", 2)
	var stone_before: int = player.inventory.get_count(1)
	var health_before: float = player.health
	_check(bear.prompt_text().contains("捕兽夹"), "bear_trap_prompt")
	bear._on_body_entered(player)
	_check(player.health < health_before, "bear_trap_damages")
	_check(bear.interact(player), "bear_trap_disarm")
	_check(bear.consumed, "bear_trap_finishes")
	_check(player.inventory.get_count(1) == stone_before + 2, "bear_trap_rewards_stone")

	# 绊索：踩到受伤，拆解拿木棍
	var tripwire := TripwireEvent.new()
	_add_event(world, tripwire, &"tripwire", 3)
	var stick_before: int = player.inventory.get_count(2)
	health_before = player.health
	_check(tripwire.prompt_text().contains("绊索"), "tripwire_prompt")
	tripwire._on_body_entered(player)
	_check(player.health < health_before, "tripwire_damages")
	_check(tripwire.interact(player), "tripwire_disarm")
	_check(tripwire.consumed, "tripwire_finishes")
	_check(player.inventory.get_count(2) == stick_before + 2, "tripwire_rewards_stick")

	# 毒蘑菇：给材料，可能受伤
	var mushroom := PoisonMushroomEvent.new()
	_add_event(world, mushroom, &"poison_mushroom", 4)
	var herb_before: int = player.inventory.get_count(0)
	_check(mushroom.prompt_text().contains("毒蘑菇"), "poison_mushroom_prompt")
	_check(mushroom.interact(player), "poison_mushroom_interact")
	_check(mushroom.consumed, "poison_mushroom_finishes")
	_check(player.inventory.get_count(0) == herb_before + 2, "poison_mushroom_rewards_herb")

	# 陷阱宝箱：先检查，再拆机关；成功给奖励，失败受伤
	var chest := TrappedChestEvent.new()
	_add_event(world, chest, &"trapped_chest", 5)
	var total_before: int = _inventory_total(player.inventory)
	health_before = player.health
	_check(chest.prompt_text().contains("检查"), "trapped_chest_prompt")
	_check(chest.interact(player), "trapped_chest_inspect")
	_check(chest.prompt_text().contains("拆除"), "trapped_chest_second_prompt")
	_check(chest.interact(player), "trapped_chest_disarm")
	_check(chest.consumed, "trapped_chest_finishes")
	_check(
		_inventory_total(player.inventory) > total_before or player.health < health_before,
		"trapped_chest_has_outcome"
	)

	print("EVENT_TYPES: checks=%d failures=%d" % [_checks, _failures])
	world.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)


func _add_event(world: Node, event: WorldEvent, event_id: StringName, seed_value: int) -> void:
	event.bind(event_id, seed_value)
	world.add_child(event)


func _inventory_total(inventory: Inventory) -> int:
	var total: int = 0
	for item_id: int in inventory.items.keys():
		total += int(inventory.items[item_id])
	return total