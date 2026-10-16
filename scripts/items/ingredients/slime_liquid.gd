extends IngredientData
##凝液：右键投掷，泼出一片减速

const THROW_SPEED: float = 320.0
const THROW_RADIUS: float = 48.0


func right_use(player: PlayerCharacter) -> int:
	return 1 if IngredientThrow.launch(player, self, THROW_SPEED, THROW_RADIUS, 0.0) else 0
