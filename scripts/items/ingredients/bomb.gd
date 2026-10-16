extends IngredientData
##炸弹：右键投掷，落地或命中后在碎点爆炸

const THROW_SPEED: float = 360.0
const THROW_RADIUS: float = 200.0


func right_use(player: PlayerCharacter) -> int:
	return 1 if IngredientThrow.launch(player, self, THROW_SPEED, THROW_RADIUS, 0.0) else 0
