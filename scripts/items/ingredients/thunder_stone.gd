
class_name ThunderStone
extends IngredientData

## 雷石：左键原地召唤一道雷击（自己不会被劈），右键丢出去，命中后在落点召唤一次雷击。

const THROW_SPEED: float = 340.0
const THROW_RADIUS: float = 120.0


##左键：原地雷击
func left_use(player: PlayerCharacter) -> int:
	if player == null or not is_instance_valid(player) or for_use_attribute.is_empty():
		return 0
	var attribute: AlchemicalData = for_use_attribute[0]

	if attribute == null:
		return 0
	#落雷会打范围，这里把自己标成豁免对象，召唤者不该被自己的雷劈到
	player.set_meta(SelfExempt.EXEMPT_META, player)
	attribute.use_effect(player)
	player.remove_meta(SelfExempt.EXEMPT_META)
	return 1


##右键：丢出去；命中/落地后由弹体在落点落一道雷
func right_use(player: PlayerCharacter) -> int:
	if player == null:
		return 0
	return 1 if IngredientThrow.launch(player, self, THROW_SPEED, THROW_RADIUS, 0.0) else 0
