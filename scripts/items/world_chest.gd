class_name WorldChest
extends Node2D

## 除材料外，宝箱还会按概率再开出一件武器或一瓶随机配方药水。
## 珍稀箱概率更高；同一口箱子用坐标做种子，重开世界前结果稳定。
const WEAPON_CHANCE: float = 0.12
const WEAPON_CHANCE_RARE: float = 0.35
const POTION_CHANCE: float = 0.25
const POTION_CHANCE_RARE: float = 0.50
## 宝箱能开出的武器：跳过开局自带的长剑/长枪，避免开出重复的起手武器。
const WEAPON_IDS: Array[int] = [202, 203, 204]

## 宝箱保留在地图实体根中，只允许开启一次。
var opened: bool = false
var rare: bool = false
var loot: Array[Dictionary] = []
var _generator: WorldGenerator = null
var _highlighted: bool = false


func bind(entry: Dictionary, generator: WorldGenerator) -> void:
	rare = entry["rare"]
	loot.assign(entry["loot"])
	_generator = generator
	queue_redraw()


func display_name() -> String:
	return "珍稀宝箱" if rare else "补给宝箱"


func set_highlighted(value: bool) -> void:
	if _highlighted != value:
		_highlighted = value
		queue_redraw()


func open() -> bool:
	if opened or not is_inside_tree() or not is_visible_in_tree() or not can_process():
		return false
	opened = true
	_highlighted = false
	var items: Node = get_node("/root/ItemListGlobal")
	for entry: Dictionary in loot:
		var data: IngredientData = items.get_template(int(entry["item_id"])) as IngredientData
		if data == null:
			continue
		var pickup := GroundPickup.new()
		pickup.name = "ChestLoot_%d_%d" % [entry["tile"].x, entry["tile"].y]
		pickup.bind(data, int(entry["amount"]), _generator)
		get_parent().add_child(pickup)
		pickup.global_position = WorldGenerator.tile_to_world(entry["tile"])
	_spawn_bonus()
	get_node("/root/AudioManager").play_sfx(&"pickup_material", global_position)
	queue_redraw()
	return true


## 按概率再开出一件武器 / 一瓶随机配方药水，落在箱子旁可站的那一格。
func _spawn_bonus() -> void:
	var items: Node = get_node_or_null("/root/ItemListGlobal")
	var parent: Node = get_parent()
	if items == null or parent == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _roll_seed()
	var index: int = 0
	if rng.randf() < (WEAPON_CHANCE_RARE if rare else WEAPON_CHANCE):
		var weapon_id: int = WEAPON_IDS[rng.randi_range(0, WEAPON_IDS.size() - 1)]
		var weapon: ItemData = items.get_template(weapon_id) as ItemData
		if weapon != null:
			_drop(weapon, parent, index)
			index += 1
	if rng.randf() < (POTION_CHANCE_RARE if rare else POTION_CHANCE):
		var potion: PotionData = PotionData.create_random(rng)
		if potion != null:
			_drop(potion, parent, index)


## 附加奖励落在箱子四邻里第一个可站的格子上，保证能走过去捡。
func _drop(item: ItemData, parent: Node, index: int) -> void:
	var tile: Vector2i = WorldGenerator.world_to_tile(global_position)
	var spot: Vector2i = tile
	if _generator != null:
		for offset: Vector2i in [
			Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
		]:
			if _generator.is_walkable(tile + offset):
				spot = tile + offset
				break
	var pickup := GroundPickup.new()
	pickup.name = "ChestBonus_%d_%d" % [int(spot.x), int(spot.y)]
	pickup.bind(item, 1, _generator)
	parent.add_child(pickup)
	pickup.global_position = WorldGenerator.tile_to_world(spot) + Vector2(float(index) * 6.0, 0.0)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit_signal("notification", "宝箱开出：%s" % item.name)


## 同一口箱子结果稳定：坐标 + 稀有度做种子。
func _roll_seed() -> int:
	var tile: Vector2i = WorldGenerator.world_to_tile(global_position)
	return hash("%d:%d:%d" % [tile.x, tile.y, 1 if rare else 0])


func _draw() -> void:
	var trim := Color("dfbd62") if rare else Color("b6b69c")
	draw_rect(Rect2(-12, 5, 25, 5), Color("2d3026", 0.4))
	draw_rect(Rect2(-12, -8, 24, 16), Color("3e3027"))
	draw_rect(Rect2(-10, -6, 20, 12), Color("95603c"))
	draw_rect(Rect2(-9, -5, 18, 3), Color("bc8c51"))
	if opened:
		draw_rect(Rect2(-12, -17, 24, 10), Color("4a352a"))
		draw_rect(Rect2(-10, -15, 20, 6), Color("bb925d"))
		draw_rect(Rect2(-9, -5, 18, 6), Color("352c25"))
	else:
		draw_line(Vector2(-10, -1), Vector2(10, -1), Color("493427"), 2)
		for x: int in [-8, 6]:
			draw_rect(Rect2(x, -7, 3, 14), trim)
		draw_rect(Rect2(-2, -3, 4, 6), trim.lightened(0.25))
		draw_rect(Rect2(0, -1, 1, 2), Color("493427"))
		if rare:
			draw_rect(Rect2(15, -13, 2, 6), trim)
			draw_rect(Rect2(13, -11, 6, 2), trim)
	if _highlighted:
		draw_rect(Rect2(-15, -12, 30, 23), Color("ffe6a0"), false, 1)
