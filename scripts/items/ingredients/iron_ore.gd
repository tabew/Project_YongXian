
class_name IronOre
extends IngredientData

## 铁矿：左键使用，给手上那把武器附上"锋利"（同级或更低不会顶替）。

const SHARPNESS: AlchemicalData = preload("res://resources/alchemical_attribute/sharpness.tres")


func left_use(player: PlayerCharacter) -> int:
	if player == null or player.inventory == null:
		return 0
	var inventory: Inventory = player.inventory
	var slot: int = inventory.handy_selected
	var item_id: int = inventory.get_handy_slot_id(slot)

	if item_id < 0:
		return 0
	var data: WeaponData = inventory.get_item_template(item_id) as WeaponData

	if data == null or data.weapon == null:
		return 0
	if not data.weapon.add_enchant(SHARPNESS):
		return 0
	#武器定义变了，让玩家重新装备一次，附魔立刻生效
	inventory.get_item_data[data.id] = data
	inventory.inventory_update.emit()
	inventory.handy_selection_changed.emit()
	return 1
