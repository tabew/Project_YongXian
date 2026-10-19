class_name WorldEvent
extends Node2D

## 第一版可交互事件：草丛搜索。
##
## 事件本身是地图实体根里的固定点，不依赖 GrassView 的懒加载生命周期。
## 事件被消耗后隐藏；地图实体根离开当前区域时由 GameWorld 统一暂停。

signal consumed_event(event: WorldEvent)

const GRASS_POTION: StringName = &"grass_potion"
const POTION_TEMPLATE: PotionData = preload("res://resources/items/potions/potion_model.tres")
const POTION_ATTRIBUTES: Array = [
	preload("res://resources/alchemical_attribute/heal.tres"),
	preload("res://resources/alchemical_attribute/continuous_heal.tres"),
	preload("res://resources/alchemical_attribute/guard.tres"),
	preload("res://resources/alchemical_attribute/haste.tres"),
	preload("res://resources/alchemical_attribute/powerful.tres"),
	preload("res://resources/alchemical_attribute/agility.tres"),
	preload("res://resources/alchemical_attribute/fortify.tres"),
	preload("res://resources/alchemical_attribute/swift.tres"),
	preload("res://resources/alchemical_attribute/sanctuary.tres"),
	preload("res://resources/alchemical_attribute/stamina.tres"),
]
const MATERIAL_POOL: Array[int] = [0, 1, 2]

var event_id: StringName = &""
var event_seed: int = 0
var consumed: bool = false

var _highlighted: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time: float = 0.0


func bind(id_value: StringName, seed_value: int) -> void:
	event_id = id_value
	event_seed = seed_value
	_rng.seed = seed_value
	consumed = false
	visible = true
	set_process(true)
	queue_redraw()


func prompt_text() -> String:
	match event_id:
		GRASS_POTION:
			return "E · 搜索草丛"
	return "E · 调查"


func can_interact(player: PlayerCharacter) -> bool:
	return (
		not consumed
		and player != null
		and player.inventory != null
		and is_inside_tree()
		and is_visible_in_tree()
		and can_process()
	)


func set_highlighted(value: bool) -> void:
	if _highlighted == value:
		return
	_highlighted = value
	queue_redraw()


func interact(player: PlayerCharacter) -> bool:
	if not can_interact(player):
		return false
	match event_id:
		GRASS_POTION:
			_give_grass_reward(player)
		_:
			_notify("这里什么也没有留下")
	_finish()
	return true


## 子类完成交互后统一走这里：标记消耗、隐藏并停止绘制刷新。
func _finish() -> void:
	consumed = true
	_highlighted = false
	visible = false
	set_process(false)
	consumed_event.emit(self)


func _ready() -> void:
	# 草丛的前层 z=1；事件必须画在草上，否则会被草丛盖住。
	z_index = 2


func _item_list() -> Node:
	return get_node_or_null("/root/ItemListGlobal")


func _notify(message: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit_signal("notification", message)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _give_grass_reward(player: PlayerCharacter) -> void:
	# 草丛以药水为主，少量材料作为变化。
	if _rng.randf() < 0.78 and _give_potion(player, "草丛里找到一瓶"):
		return
	var item_id: int = MATERIAL_POOL[_rng.randi_range(0, MATERIAL_POOL.size() - 1)]
	_give_item(player, item_id, _rng.randi_range(2, 4), "草丛里找到")


func _create_potion() -> PotionData:
	var potion := POTION_TEMPLATE.duplicate() as PotionData
	if potion == null:
		return null
	var template := POTION_ATTRIBUTES[_rng.randi_range(0, POTION_ATTRIBUTES.size() - 1)] as AlchemicalData
	if template == null:
		return null
	var attribute := template.duplicate() as AlchemicalData
	if attribute == null:
		return null
	if attribute.max_level > 0:
		attribute.level = _rng.randi_range(1, mini(attribute.max_level, 2))
	else:
		attribute.level = 1
	var attributes: Array[AlchemicalData] = [attribute]
	potion.alchemical_attribute = attributes
	potion.name = "%s药水" % attribute.name
	var item_list := _item_list()
	if item_list == null:
		return null
	potion.id = PotionData.next_potion_id()
	while not bool(item_list.call("register_instance", potion)):
		potion.id = PotionData.next_potion_id()
	return potion


func _give_item(
	player: PlayerCharacter,
	item_id: int,
	amount: int,
	prefix: String = "获得"
) -> bool:
	var item_list := _item_list()
	if item_list == null:
		return false
	var template := item_list.call("get_template", item_id) as ItemData
	if template == null:
		return false
	player.inventory.add_item(item_id, amount)
	_notify("%s %s ×%d" % [prefix, template.name, amount])
	return true


func _give_potion(player: PlayerCharacter, prefix: String = "获得") -> bool:
	var potion: PotionData = _create_potion()
	if potion == null:
		return false
	player.inventory.add_item(potion.id, 1)
	_notify("%s%s" % [prefix, potion.name])
	return true


## 从背包里偷一瓶药水或最多两份材料；没有可偷物品时返回空字典。
func _steal_random(player: PlayerCharacter) -> Dictionary:
	var candidates: Array[int] = []
	for item_id: int in player.inventory.items.keys():
		if int(player.inventory.items[item_id]) <= 0:
			continue
		var data := player.inventory.get_item_template(item_id)
		if data is PotionData or data is IngredientData:
			candidates.append(item_id)
	if candidates.is_empty():
		return {}
	var chosen: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var data := player.inventory.get_item_template(chosen)
	var amount: int = 1 if data is PotionData else mini(int(player.inventory.items[chosen]), 2)
	player.inventory.remove_item(chosen, amount)
	return {"item_id": chosen, "amount": amount}


func _restore_item(player: PlayerCharacter, item_id: int, amount: int) -> void:
	if item_id < 0 or amount <= 0:
		return
	player.inventory.add_item(item_id, amount)


func _item_name(item_id: int) -> String:
	var item_list := _item_list()
	if item_list == null:
		return "物品"
	var data := item_list.call("get_template", item_id) as ItemData
	return data.name if data != null else "物品"


func _is_damage_target(body: Node2D) -> bool:
	return body is PlayerCharacter or body is BaseMonster


func _draw() -> void:
	var bob: float = sin(_time * 2.4) * 1.5
	# 草丛底座
	draw_circle(Vector2(0, 5), 10.0, Color("23351f", 0.22))
	for index: int in 7:
		var x: float = float(index - 3) * 2.8
		var top := Vector2(x + sin(_time * 1.3 + float(index)) * 1.2, -10.0 - float(posmod(index * 3, 5)))
		draw_line(Vector2(x * 0.7, 5.0), top, Color("5b8a44"), 2.0)
		draw_line(top, top + Vector2(3.0, -2.0), Color("85b35d"), 1.0)
	# 药水瓶
	var bottle := Vector2(0, -3 + bob)
	draw_rect(Rect2(bottle + Vector2(-4, -2), Vector2(8, 9)), Color("4d3b33"))
	draw_rect(Rect2(bottle + Vector2(-3, -1), Vector2(6, 6)), Color("8fd6c0"))
	draw_rect(Rect2(bottle + Vector2(-1, -5), Vector2(2, 4)), Color("d7d0b4"))
	draw_circle(bottle + Vector2(0, 2), 1.4, Color("e6fff3"))
	# 微光提示
	var pulse: float = 0.45 + sin(_time * 3.0) * 0.2
	draw_circle(Vector2(8, -13 + bob), 1.6, Color(1.0, 0.94, 0.55, pulse))
	draw_line(Vector2(7, -13 + bob), Vector2(9, -13 + bob), Color(1, 1, 0.85, pulse), 1.0)
	draw_line(Vector2(8, -14 + bob), Vector2(8, -12 + bob), Color(1, 1, 0.85, pulse), 1.0)
	if _highlighted:
		draw_arc(Vector2(0, 0), 17.0, 0.0, TAU, 24, Color("ffe6a0"), 1.2)
