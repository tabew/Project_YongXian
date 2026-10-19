
class_name IceCrystal
extends IngredientData

## 冰晶：右键扔出，落地后对圈内目标施加迟缓；左键不使用。

const THROW_SPEED: float = 340.0
const THROW_RADIUS: float = 120.0


func left_use(_player: PlayerCharacter) -> int:
	return 0


func right_use(player: PlayerCharacter) -> int:
	if player == null:
		return 0
	return 1 if IngredientThrow.launch(player, self, THROW_SPEED, THROW_RADIUS, 0.0) else 0
