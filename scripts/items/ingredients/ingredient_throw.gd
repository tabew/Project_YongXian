class_name IngredientThrow
extends RefCounted


static func launch(player: PlayerCharacter, data: IngredientData, speed: float, radius: float, duration: float) -> bool:
	if player == null or player.get_parent() == null or data == null:
		return false

	var model: ItemModel = data.create_model()

	if model == null:
		return false

	model.collision_layer = 0
	model.collision_mask = 4
	model.freeze = true
	model.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC

	player.get_parent().add_child(model)

	var origin: Vector2 = player.global_position

	model.global_position = origin

	var aim: Vector2 = player.get_global_mouse_position() - origin
	var direction: Vector2 = aim.normalized() if aim.length() > 1.0 else Vector2.RIGHT
	var flight: PotionProjectile = PotionProjectile.new()

	model.add_child(flight)
	flight.start(player, direction, speed, radius, duration, level_zero(data.for_use_attribute))

	return true


static func level_zero(attributes: Array[AlchemicalData]) -> Array[AlchemicalData]:
	var result: Array[AlchemicalData] = []

	for attribute: AlchemicalData in attributes:
		if attribute == null:
			continue
		var copy: AlchemicalData = attribute.duplicate() as AlchemicalData

		copy.level = 0
		result.append(copy)

	return result
