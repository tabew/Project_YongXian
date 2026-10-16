extends IngredientData

func left_use(player: PlayerCharacter) -> int:
	for attribute: AlchemicalData in for_use_attribute:
		if attribute == null or not attribute.has_method("use_effect"):
			continue
		attribute.use_effect(player)
	return 1