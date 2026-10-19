extends SceneTree

## 宝箱奖励验收：材料照旧落地，另有概率开出武器与随机配方药水。

var _checks: int = 0
var _failures: int = 0
var _weapons: int = 0
var _potions: int = 0
var _materials: int = 0
var _bad_potion: int = 0
var _bad_spot: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var generator := WorldGenerator.new(20261019)
	var holder := Node2D.new()
	root.add_child(holder)
	var opened_chests: int = 0
	var rare_chests: int = 0
	for spec: MapSpec in generator.map_specs():
		var population: Dictionary = generator.population_for(spec.node_id)
		for entry: Dictionary in population["chests"]:
			var chest := WorldChest.new()
			chest.bind(entry, generator)
			holder.add_child(chest)
			chest.position = WorldGenerator.tile_to_world(entry["tile"])
			if not chest.open():
				chest.queue_free()
				continue
			opened_chests += 1
			if bool(entry["rare"]):
				rare_chests += 1
			for child: Node in holder.get_children():
				if not child is GroundPickup:
					continue
				var pickup := child as GroundPickup
				if pickup.data is PotionData:
					_potions += 1
					var potion := pickup.data as PotionData
					if potion.alchemical_attribute.size() < 1 or potion.alchemical_attribute.size() > 3:
						_bad_potion += 1
					if potion.id <= 300:
						_bad_potion += 1
				elif pickup.data is WeaponData:
					_weapons += 1
				else:
					_materials += 1
				var tile: Vector2i = WorldGenerator.world_to_tile(pickup.global_position)
				if not generator.is_walkable(tile):
					_bad_spot += 1
			# 清掉这一轮掉出来的东西，避免下一口箱子重复计数
			for child: Node in holder.get_children():
				if child is GroundPickup:
					holder.remove_child(child)
					child.queue_free()
			chest.queue_free()
	print("CHEST_REWARDS chests=%d rare=%d materials=%d weapons=%d potions=%d" % [
		opened_chests, rare_chests, _materials, _weapons, _potions])
	_check(opened_chests >= 20, "chest_sample_is_big_enough")
	_check(_materials > 0, "chest_still_drops_materials")
	_check(_weapons > 0, "chest_can_drop_weapons")
	_check(_potions > 0, "chest_can_drop_potions")
	_check(_bad_potion == 0, "potion_recipes_are_valid")
	_check(_bad_spot == 0, "bonus_loot_lands_on_walkable_tiles")
	print("CHEST_REWARDS: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
