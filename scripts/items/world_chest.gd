class_name WorldChest
extends Node2D

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
	get_node("/root/AudioManager").play_sfx(&"pickup_material", global_position)
	queue_redraw()
	return true


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
