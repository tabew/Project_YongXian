class_name GameWorld
extends Node2D

## 传统 RPG 箱庭：触及出口立即换到目标入口，主视图只显示当前区域。

const TRAINING_DUMMY: PackedScene = preload("res://scenes/combat/training_dummy.tscn")
## 死亡结算完成后回到的局外场景。
const WORKSHOP_SCENE: String = "res://scenes/workshop/workshop.tscn"
## 死亡演出（爆散 + 飘字）到回工坊之间的等待。
const DEATH_RETURN_DELAY: float = 1.6

@export var spawn_training_dummy: bool = true
## 打开后每次生成世界都会打印完整地图报告（调试用）。
@export var debug_map_report: bool = false

@onready var chunk_manager: ChunkManager = $ChunkManager
@onready var monster_spawner: MonsterSpawner = $MonsterSpawner
@onready var player: PlayerCharacter = $Player
@onready var hud: Control = $GameHUD/HUD
@onready var camera: Camera2D = $Player/Camera2D
## 灵感光点对象池：掉落在这里生成，无条件飞向主角。
@onready var inspiration_field: InspirationField = $InspirationField
## 灵感计数 + 飘字。
@onready var inspiration_hud: InspirationHud = $GameHUD/Inspiration
## 清空房间后的门选择界面。
@onready var door_choice: DoorChoicePanel = $GameHUD/DoorChoice
## 通关结算界面（贤者之石）。
@onready var settlement: RunSettlementPanel = $GameHUD/Settlement

var _cottage_view: CottageView = null
var _training_dummy: TrainingDummy
var _training_dummy_map: int = -1
var _generator: WorldGenerator = null
var _current_node: int = -1
var _base_zoom: Vector2 = Vector2(2.0, 2.0)
var _hud_bound: bool = false
var _monster_map: int = -1
## 怪物已释放到地上的道具按地图保存，离图暂停，回图继续。
var _map_entity_roots: Dictionary = {}
## 每张地图的地面材料只生成一次；拾取后返回地图不会补刷。
var _material_maps: Dictionary = {}
## 每张地图的场景元素与可破坏物只生成一次；元素吸附后会自行冷却回满。
var _room_props: Dictionary = {}
## 秘密房世界 node_id -> 通往它的词条门；未开门时对应出口被封。
var _secret_doors: Dictionary = {}
## 本局已打开的词条门（秘密房世界 node_id）。跨房间保留，重进宿主不再封路。
var _opened_secret_doors: Dictionary = {}
## 本局已进入的房间；小地图没进过的房间画成问号。
var _visited_rooms: Dictionary = {}
## 当前高亮的可吸附场景元素；同一时刻只允许吸附一个。
var _nearby_element: SceneElement = null
## 吸附键是否按住；长按到满才真正吸附。
var _absorb_held: bool = false
var _nearby_pickup: GroundPickup = null
const PICKUP_RADIUS: float = 36.0
## 吸附半径：击杀/破坏掉落的材料靠近即自动收进炼金背包。
## 默认值仅作兜底；实际半径取 AlchemyStation.adsorb_radius_pixels()（磁词条会扩大）。
const ADSORB_RADIUS: float = 48.0

## 灵感掉落用的随机源：种子来自本局世界种子，保证同种子同结果。
var _inspiration_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 灵感单例（运行期查找，避免在 --script 测试里提前引用全局标识符）。
var _inspiration: InspirationManager = null
## 死亡结算只跑一次，避免 defeated 重复触发导致重复切换场景。
var _run_failed: bool = false
## 当前房间是否已清空；未清空时不开放出口，清空后弹出选门界面。
var _room_cleared: bool = false
## 通关结算只跑一次。
var _run_finished: bool = false


func _ready() -> void:
	_base_zoom = camera.zoom
	get_viewport().size_changed.connect(_on_viewport_resized)
	_setup_inspiration()
	door_choice.door_chosen.connect(_on_door_chosen)
	settlement.confirmed.connect(_on_settlement_confirmed)
	# 直接从编辑器单独运行本场景时，也要能开局。
	if GameState.world_seed == 0:
		GameState.start_new_world()
	build_world(GameState.world_seed)


func _process(_delta: float) -> void:
	if _generator == null or player.active_map == null:
		return
	_sync_training_dummy()
	_confine_map_monsters()
	_refresh_pickup()
	_adsorb_pickups()
	_update_scene_elements(_delta)
	if player.health <= 0:
		return
	_update_room_clear()
	# 未清空房间前不开放出口：打完房间才出现 2~3 个门。
	if not _room_cleared:
		return
	var spec: MapSpec = player.active_map
	var local: Vector2i = WorldGenerator.world_to_tile(player.global_position) - spec.origin
	for link: Dictionary in _generator.gate_links(_current_node):
		# 词条门没开就封住该出口，玩家只能从别的门继续推进。
		if _is_sealed_secret_gate(int(link["target"])):
			continue
		var side: int = link["side"]
		if player.velocity.x * side <= 0.1:
			continue
		if absi(local.y - int(link["y"])) > MapSpec.GATE_HALF_HEIGHT:
			continue
		if (side < 0 and local.x <= 1) or (side > 0 and local.x >= spec.extent.x - 2):
			var carried_velocity: Vector2 = player.velocity
			_enter_map(link["target"], link["arrival_side"], link["arrival_y"])
			AudioManager.play_sfx(&"gate_transition")
			# 落点与出口带分离，按住同方向即可走进新箱庭，不会立即弹回。
			player.velocity = carried_velocity
			EventBus.notification.emit("进入 %s · %s" % [_generator.run.describe(_current_node), player.active_map.shape_name()])
			return


func _unhandled_input(event: InputEvent) -> void:
	# 吸附键：按住累计进度，松开清零，避免误触把元素吸走。
	if event.is_action_pressed("absorb_element") and not event.is_echo():
		_absorb_held = true
	elif event.is_action_released("absorb_element"):
		_absorb_held = false
		if is_instance_valid(_nearby_element):
			_nearby_element.set_highlighted(false)
			_nearby_element = null
	elif event.is_action_pressed("regenerate_world"):
		regenerate_world()
	elif event.is_action_pressed("kill_all_monsters"):
		kill_all_monsters()

## 吸附：靠近的材料自动收进炼金背包，对应“击杀/破坏 → 吸附材料 → 按 E 展开”的核心循环。
func _adsorb_pickups() -> void:
	if player.health <= 0 or player.alchemy_station == null:
		return
	var entity_root: Node2D = _map_entity_roots.get(_current_node)
	var pickup_roots: Array[Node2D] = [monster_spawner]
	if entity_root != null:
		pickup_roots.append(entity_root)
	var radius: float = player.alchemy_station.adsorb_radius_pixels()
	var radius_squared: float = radius * radius
	for pickup_root: Node2D in pickup_roots:
		for child: Node in pickup_root.get_children():
			if not child is GroundPickup or child.is_queued_for_deletion():
				continue
			var pickup := child as GroundPickup
			if not pickup.is_available_for_pickup():
				continue
			if player.global_position.distance_squared_to(pickup.global_position) > radius_squared:
				continue
			if not _can_reach_pickup(pickup.global_position):
				continue
			var material_name: String = pickup.data.name
			var quantity: int = pickup.amount
			if pickup.collect(player):
				EventBus.notification.emit("吸附 %s ×%d" % [material_name, quantity])


## 场景元素：靠近高亮，长按吸附键产出一份主题材料，随后元素进入冷却。
## 长按进度记在元素上；松开或离开范围会由 set_highlighted(false) 清零，避免误触。
func _update_scene_elements(delta: float) -> void:
	if player.health <= 0 or player.alchemy_station == null:
		return
	var entity_root: Node2D = _map_entity_roots.get(_current_node)
	if entity_root == null:
		return
	var nearest: SceneElement = null
	var nearest_distance: float = SceneElement.INTERACT_RADIUS
	for child: Node in entity_root.get_children():
		if not child is SceneElement or child.is_queued_for_deletion():
			continue
		var element := child as SceneElement
		if not element.is_ready_to_absorb():
			continue
		var distance: float = player.global_position.distance_to(element.global_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = element
	if nearest != _nearby_element:
		if is_instance_valid(_nearby_element):
			_nearby_element.set_highlighted(false)
		_nearby_element = nearest
		if _nearby_element != null:
			_nearby_element.set_highlighted(true)
	if _nearby_element == null or not _absorb_held:
		return
	if player.alchemy_station.is_menu_open() or player.alchemy_station.is_wheel_open():
		return
	var produced: Dictionary = _nearby_element.advance_hold(delta)
	if produced.is_empty():
		return
	var added: int = player.alchemy_station.absorb_material(int(produced["material_id"]), int(produced["amount"]))
	if added > 0:
		AudioManager.play_sfx(&"absorb_material")
		EventBus.notification.emit("吸附 %s ×%d" % [SceneElementCatalog.name_of(_nearby_element.element_id), added])


## 可破坏物打碎：把材料落到它所在的地图里，交给已有的自动吸附流程收进炼金背包。
func _on_breakable_broken(_prop_id: StringName, material_id: int, amount: int, prop: BreakableProp) -> void:
	if not is_instance_valid(prop) or amount <= 0:
		return
	var data: IngredientData = ItemListGlobal.get_template(material_id) as IngredientData
	if data == null:
		return
	var pickup := GroundPickup.new()
	pickup.name = "Breakable_%d" % material_id
	pickup.bind(data, amount, _generator)
	var root: Node = prop.get_parent()
	if root == null:
		root = self
	root.add_child(pickup)
	pickup.global_position = prop.global_position


## 隐藏调试指令：只调用怪物死亡接口，不操作道具或其他世界实体。
func kill_all_monsters() -> void:
	kill_monsters_in_tree(get_tree())


static func kill_monsters_in_tree(tree: SceneTree) -> void:
	for monster: Node in tree.get_nodes_in_group("monsters"):
		if monster.has_method("kill"):
			monster.call("kill")


## 用指定种子重建整个世界；只有重建世界才恢复玩家生命。
func build_world(seed_value: int) -> void:
	_hud_bound = false
	_run_failed = false
	_run_finished = false
	_room_cleared = false
	_opened_secret_doors.clear()
	_visited_rooms.clear()
	door_choice.hide_choices()
	settlement.hide_panel()
	inspiration_field.clear_all()
	_clear_map_entities()
	# 局内地图由 RunMapGenerator 规划（层 → 区域 → 房间），世界生成器只负责地形与门。
	_generator = RunMapBuilder.build(seed_value, 0, RunMapConfig.prototype(), MapConfig.new())
	GameState.world_seed = _generator.world_seed
	MapRng.set_shared_master(GameState.world_seed)
	# 灵感掉落跟着本局世界种子走，同种子同结果。
	_inspiration_rng.seed = GameState.world_seed
	# 房间类型决定内容池：只有战斗 / Boss 区域刷怪。
	monster_spawner.content = MapContent.build(_generator)
	chunk_manager.setup(_generator, player)
	_enter_map(_generator.run.start_node(), 0, -1, true)
	_place_training_dummy(_generator, WorldGenerator.world_to_tile(player.global_position))
	_setup_map_monsters()
	# 初图落位并加载后才绑定，避免把上一局的位置记为已探索。
	hud.bind_world(chunk_manager, player)
	# 小地图画的是本层房间图（房型 / 主题色 / 未探索问号），不再逐格采样地形。
	hud.bind_run(_generator.run, player)
	_bind_alchemy_hud()
	_hud_bound = true
	_sync_minimap()
	if debug_map_report:
		print(MapDebug.report(_generator))
	EventBus.world_ready.emit(_generator.world_seed)
	AudioManager.play_music(&"music_wilds")


## 从当前怪物定义取群系并集；新增怪物后地图会自动支持其战斗主题。
func _map_config_for_monsters() -> MapConfig:
	var result := MapConfig.new()
	for definition: MonsterSpawnData in monster_spawner.spawn_definitions:
		if definition == null or definition.monster_scene == null or definition.max_per_chunk <= 0 or definition.chunk_spawn_chance <= 0.0:
			continue
		# 空白白名单代表不限群系，地图也无需限制。
		if definition.allowed_biomes.is_empty():
			result.combat_biomes.clear()
			return result
		for biome: int in definition.allowed_biomes:
			if not result.combat_biomes.has(biome):
				result.combat_biomes.append(biome)
	result.combat_biomes.sort()
	return result


## 一次同步完成入口落位、相机跳转与可见地图替换，不播放淡入淡出。
func _enter_map(map_node_id: int, side: int = 0, gate_y: int = -1, reset_health: bool = false) -> void:
	var spec: MapSpec = _generator.map_spec(map_node_id)
	if spec == null:
		return
	_current_node = map_node_id
	# 进过的房间要记下来：小地图只给进过的房间显示房型与主题色，其余画问号。
	_visited_rooms[map_node_id] = true
	# 换房即重新判定清空状态；旧房间的门选择界面立刻收起。
	_room_cleared = false
	door_choice.hide_choices()
	if is_instance_valid(_nearby_element):
		_nearby_element.set_highlighted(false)
	_nearby_element = null
	if _cottage_view == null:
		_cottage_view = CottageView.new()
		_cottage_view.name = "CottageView"
		add_child(_cottage_view)
		# 地形之上、角色之下，避免木地板遮住出生玩家。
		move_child(_cottage_view, chunk_manager.get_index() + 1)
	_cottage_view.bind(spec)
	player.spawn_on(_generator, _generator.entry_position(map_node_id, side, gate_y), spec, reset_health)
	_limit_camera(spec)
	chunk_manager.load_map(map_node_id)
	_setup_ground_materials(spec)
	_setup_room_props(spec)
	_refresh_pickup()
	if _hud_bound:
		_sync_training_dummy()
		_setup_map_monsters()
		_sync_minimap()


func _sync_minimap() -> void:
	hud.minimap.refresh_position()
	hud.minimap.set_room_state(_current_node, _visited_rooms)
	hud._refresh()


func _limit_camera(spec: MapSpec) -> void:
	var start: Vector2i = spec.origin * WorldGenerator.TILE_SIZE
	var finish: Vector2i = (spec.origin + spec.extent) * WorldGenerator.TILE_SIZE
	camera.limit_left = start.x
	camera.limit_top = start.y
	camera.limit_right = finish.x
	camera.limit_bottom = finish.y
	# 边缘硬停止；切图重置平滑，避免飞过地图间隙。
	camera.limit_smoothed = false
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var fit: float = maxf(viewport_size.x / float(finish.x - start.x), viewport_size.y / float(finish.y - start.y))
	camera.zoom = Vector2(maxf(_base_zoom.x, fit), maxf(_base_zoom.y, fit))
	camera.reset_smoothing()
	camera.force_update_scroll()


func _on_viewport_resized() -> void:
	if player.active_map == null:
		return
	_limit_camera(player.active_map)
	chunk_manager.prepare_visible()


func _place_training_dummy(generator: WorldGenerator, spawn_tile: Vector2i) -> void:
	if is_instance_valid(_training_dummy):
		remove_child(_training_dummy)
		_training_dummy.queue_free()
	_training_dummy = null
	_training_dummy_map = -1
	if not spawn_training_dummy:
		return
	# 保留开局附近训练靶，且候选落点必须属于初始地图。
	for offset: Vector2i in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3), Vector2i(2, 0), Vector2i(-2, 0)]:
		var tile: Vector2i = spawn_tile + offset
		var local: Vector2i = tile - player.active_map.origin
		if player.active_map.contains_local(local.x, local.y) and generator.is_walkable(tile):
			_training_dummy = TRAINING_DUMMY.instantiate() as TrainingDummy
			_training_dummy.position = WorldGenerator.tile_to_world(tile)
			_training_dummy.terrain_source = generator
			_training_dummy_map = _current_node
			add_child(_training_dummy)
			_sync_training_dummy()
			return


func _sync_training_dummy() -> void:
	if not is_instance_valid(_training_dummy):
		return
	var spec: MapSpec = _generator.map_spec(_training_dummy_map)
	if spec == null:
		return
	# 击退与回家仍由训练靶原脚本处理，外层只保证不越出所属箱庭。
	_training_dummy.global_position = _clamp_to_map(_training_dummy.global_position, spec)
	var is_active: bool = _training_dummy_map == _current_node
	_training_dummy.visible = is_active
	_training_dummy.process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED


## 切图重建存活实体，生成器保留本局击杀记录；旧区域怪物不会继续攻击。
func _setup_map_monsters() -> void:
	if chunk_manager.chunk_applied.is_connected(_on_monster_chunk_applied):
		chunk_manager.chunk_applied.disconnect(_on_monster_chunk_applied)
	# 死亡掉落会被原怪物脚本移到 spawner；保存到所属地图，避免跨图显示或攻击。
	if _monster_map >= 0:
		var previous_root: Node2D = _map_entity_root(_monster_map)
		for child: Node in monster_spawner.get_children():
			if not child is BaseMonster:
				child.reparent(previous_root, true)
	for map_id: int in _map_entity_roots.keys():
		var root: Node2D = _map_entity_roots[map_id]
		var is_active: bool = map_id == _current_node
		root.visible = is_active
		root.process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
	_monster_map = _current_node
	monster_spawner.setup(_generator, chunk_manager, player, player.active_map)
	# 新加载器长期保留整张地图，不能沿用旧版按距离卸载且等区块重铺才刷新的逻辑。
	# 只关闭 spawner 的距离回收；怪物子节点仍正常处理，切图由 setup 统一回收。
	monster_spawner.set_process(false)
	# 连接在 spawner 后面，同步过滤隐藏邻居预铺和边缘共享区块中的越界实体。
	chunk_manager.chunk_applied.connect(_on_monster_chunk_applied)
	_on_monster_chunk_applied(Vector2i.ZERO)


func _map_entity_root(map_node_id: int) -> Node2D:
	if not _map_entity_roots.has(map_node_id):
		var root := Node2D.new()
		root.name = "MapEntities_%d" % map_node_id
		add_child(root)
		move_child(root, player.get_index())
		_map_entity_roots[map_node_id] = root
	return _map_entity_roots[map_node_id]


func _clear_map_entities() -> void:
	if is_instance_valid(_nearby_pickup):
		_nearby_pickup.set_highlighted(false)
	_nearby_pickup = null
	if is_instance_valid(_nearby_element):
		_nearby_element.set_highlighted(false)
	_nearby_element = null
	_material_maps.clear()
	_room_props.clear()
	_secret_doors.clear()
	for root: Node2D in _map_entity_roots.values():
		remove_child(root)
		root.queue_free()
	_map_entity_roots.clear()
	for child: Node in monster_spawner.get_children():
		if not child is BaseMonster:
			monster_spawner.remove_child(child)
			child.queue_free()
	_monster_map = -1


func _setup_ground_materials(spec: MapSpec) -> void:
	var entity_root: Node2D = _map_entity_root(spec.node_id)
	if not _material_maps.has(spec.node_id):
		for entry: Dictionary in GroundMaterials.plan(_generator, spec):
			var data: IngredientData = ItemListGlobal.get_template(int(entry["item_id"])) as IngredientData
			if data == null:
				continue
			var pickup := GroundPickup.new()
			pickup.name = "Material_%d_%d" % [entry["tile"].x, entry["tile"].y]
			pickup.bind(data, int(entry["amount"]), _generator)
			pickup.position = WorldGenerator.tile_to_world(entry["tile"])
			entity_root.add_child(pickup)
		_material_maps[spec.node_id] = true
	_refresh_map_entity_visibility()


## 场景元素与可破坏物：每张地图只铺一次；元素靠自身冷却回满，可破坏物打碎即消失。
func _setup_room_props(spec: MapSpec) -> void:
	if _room_props.has(spec.node_id):
		return
	var room: RoomData = _current_room()
	if room == null:
		return
	var entity_root: Node2D = _map_entity_root(spec.node_id)
	for entry: Dictionary in RoomProps.plan(_generator, spec, room):
		var tile: Vector2i = entry["tile"]
		var node: Node2D = null
		if int(entry["kind"]) == RoomProps.Kind.ELEMENT:
			var element := SceneElement.new()
			element.bind(entry)
			node = element
		else:
			var prop := BreakableProp.new()
			prop.bind(entry)
			prop.broken.connect(_on_breakable_broken.bind(prop))
			node = prop
		node.name = "%s_%d_%d" % [String(entry["id"]), tile.x, tile.y]
		node.position = WorldGenerator.tile_to_world(tile)
		entity_root.add_child(node)
	_spawn_secret_door(spec, entity_root)
	_room_props[spec.node_id] = true
	_refresh_map_entity_visibility()


## 秘密房的词条门：堵在宿主房通往秘密房的出口上，带对应词条才能敲开。
## 出口坐标直接取 gate_links，和普通门走同一套定位。
func _spawn_secret_door(spec: MapSpec, entity_root: Node2D) -> void:
	var room: RoomData = _current_room()
	if room == null or not room.has_secret_door():
		return
	# secret_door 里存的是局内地图编号，出口用的是世界编号，这里必须换算一次。
	var data_target: int = int(room.secret_door.get("target", -1))
	if data_target < 0:
		return
	var target: int = _generator.run.world_node_of(data_target)
	if target < 0 or _opened_secret_doors.has(target) or _secret_doors.has(target):
		return
	var kind: int = int(room.secret_door.get("kind", SecretDoor.Kind.EXPLODE))
	for link: Dictionary in _generator.gate_links(spec.node_id):
		if int(link["target"]) != target:
			continue
		var door := SecretDoorProp.new()
		door.name = "SecretDoor_%d" % target
		door.trait_levels_provider = _active_trait_entries
		door.bind(kind, target)
		door.opened.connect(_on_secret_door_opened.bind(door))
		entity_root.add_child(door)
		# 贴着出口内侧，玩家在房间里就能看到并敲到。
		door.position = WorldGenerator.tile_to_world(link["point"]) + Vector2(-10.0 * float(link["side"]), 0.0)
		_secret_doors[target] = door
		return


## 该出口是不是一扇还没打开的词条门。
## 只认「当前真的立着词条门」的出口：门一旦打开就从表里移除，
## 万一道具没能生成也退回普通门，避免把出口永久锁死。
func _is_sealed_secret_gate(target: int) -> bool:
	return _secret_doors.has(target)


## 当前生效炼金组合的词条快照，供词条门判定。
## 只走炼金台的公开接口，不读它的内部结构。
func _active_trait_entries() -> Array:
	var entries: Array = []
	if player == null or player.alchemy_station == null:
		return entries
	var combo: BrewCombo = player.alchemy_station.active_combo()
	if combo == null:
		return entries
	for trait_instance: TraitInstance in combo.traits:
		entries.append({"id": trait_instance.id, "level": trait_instance.level})
	return entries


func _on_secret_door_opened(kind: int, door: SecretDoorProp) -> void:
	if not is_instance_valid(door):
		return
	_opened_secret_doors[door.target_world_node] = true
	_secret_doors.erase(door.target_world_node)
	EventBus.notification.emit("%s已开 · 秘密房解锁" % SecretDoor.name_of(kind))


## 只有当前房间的道具会显示与运行；其余房间整棵树暂停，避免隔墙交互。
func _refresh_map_entity_visibility() -> void:
	for id: int in _map_entity_roots:
		var map_root: Node2D = _map_entity_roots[id]
		map_root.visible = id == _current_node
		map_root.process_mode = Node.PROCESS_MODE_INHERIT if id == _current_node else Node.PROCESS_MODE_DISABLED


func _refresh_pickup() -> void:
	if is_instance_valid(_nearby_pickup):
		_nearby_pickup.set_highlighted(false)
	_nearby_pickup = null
	if player.health <= 0 or player.inventory == null or $GameHUD/BagUi.visible or player.alchemy_station.is_menu_open() or player.alchemy_station.is_wheel_open() or get_viewport().gui_is_dragging():
		hud.show_pickup(null)
		return
	var entity_root: Node2D = _map_entity_roots.get(_current_node)
	# 新击杀掉落暂存在 spawner，切图后归入所属地图；两处都要能立即拾取。
	var pickup_roots: Array[Node2D] = [monster_spawner]
	if entity_root != null:
		pickup_roots.append(entity_root)
	var closest: float = PICKUP_RADIUS * PICKUP_RADIUS
	for pickup_root: Node2D in pickup_roots:
		for child: Node in pickup_root.get_children():
			if not child is GroundPickup or child.is_queued_for_deletion():
				continue
			var pickup := child as GroundPickup
			if not pickup.is_available_for_pickup():
				continue
			var distance: float = player.global_position.distance_squared_to(pickup.global_position)
			if distance < closest and _can_reach_pickup(pickup.global_position):
				closest = distance
				_nearby_pickup = pickup
	if is_instance_valid(_nearby_pickup):
		_nearby_pickup.set_highlighted(true)
	hud.show_pickup(_nearby_pickup)


func _can_reach_pickup(target: Vector2) -> bool:
	var steps: int = maxi(1, ceili(player.global_position.distance_to(target) / 4.0))
	for step: int in range(1, steps + 1):
		var tile: Vector2i = WorldGenerator.world_to_tile(player.global_position.lerp(target, float(step) / steps))
		if not _generator.is_walkable(tile):
			return false
	return true

## 把新炼金台 HUD 绑到主角的随身炼金台。
func _bind_alchemy_hud() -> void:
	var alchemy_hud: Node = $GameHUD/Alchemy
	if alchemy_hud != null and alchemy_hud.has_method("bind"):
		alchemy_hud.call("bind", player.alchemy_station)


# ------------------------------------------------------------ 灵感

## 把局内世界层接到灵感系统上：掉落 → 光点 → 飞入 → 计数 / 飘字，死亡 → 结算 → 回工坊。
## 世界层只负责"在哪里生成光点"，金额与留存规则全在 InspirationManager / InspirationRules。
func _setup_inspiration() -> void:
	_inspiration = get_node_or_null("/root/Inspiration") as InspirationManager
	inspiration_field.target = player
	inspiration_field.collected.connect(_on_inspiration_collected)
	inspiration_hud.bind(_inspiration)
	player.defeated.connect(_on_player_defeated)
	if not monster_spawner.monster_killed.is_connected(_on_monster_killed):
		monster_spawner.monster_killed.connect(_on_monster_killed)
	if _inspiration == null:
		return
	if not _inspiration.inspiration_dropped.is_connected(_on_inspiration_dropped):
		_inspiration.inspiration_dropped.connect(_on_inspiration_dropped)
	# 直接从编辑器运行本场景（没经过出发门）时也要有账本，否则掉落无处累计。
	if not _inspiration.in_run:
		_inspiration.start_run()


## 击杀怪物：走概率表判定掉落，掉落记账后由 inspiration_dropped 驱动光点。
func _on_monster_killed(monster: BaseMonster, inspiration_source: int) -> void:
	# 炼金侧先结算：热量加速冷却、活体分裂、灵魂游魂，与掉落是否记账无关。
	if player != null and monster != null:
		player.on_monster_killed(monster.global_position)
	if _inspiration == null or _run_failed:
		return
	_inspiration.roll_inspiration(monster.global_position, inspiration_source, _inspiration_rng)


## 需要生成光点（来自任何掉落来源）。
func _on_inspiration_dropped(position: Vector2, amount: int, source: int) -> void:
	inspiration_field.spawn(position, amount, source)


## 光点飞入：从"飞行中"转入已获得，并弹飘字。
func _on_inspiration_collected(amount: int, source: int, _is_cluster: bool) -> void:
	if _inspiration == null:
		return
	if _inspiration.collect_inspiration(amount) > 0:
		inspiration_hud.show_gain(amount, source)


## 死亡：损失局内灵感（按留存保留少量），演出后回工坊。
func _on_player_defeated() -> void:
	if _run_failed:
		return
	_run_failed = true
	inspiration_field.clear_all()
	var detail: Dictionary = {}
	if _inspiration != null:
		detail = _inspiration.fail_run()
	inspiration_hud.show_loss(int(detail.get("lost", 0)))
	inspiration_hud.show_total(int(detail.get("kept", 0)))
	EventBus.notification.emit("你倒下了 · 损失 %d 灵感，保留 %d" % [
		int(detail.get("lost", 0)), int(detail.get("kept", 0)),
	])
	AudioManager.play_sfx(&"inspiration_death")
	await get_tree().create_timer(DEATH_RETURN_DELAY).timeout
	SceneManager.change_scene(WORKSHOP_SCENE)


# ------------------------------------------------------------ 房间与门

## 当前房间的局内地图数据；旧骨架或未开局时返回 null。
func _current_room() -> RoomData:
	if _generator == null or _generator.run == null:
		return null
	return _generator.run.room_data(_current_node)


## 房间清空 = 场上没有存活怪物；非战斗房一进门就算清空。
func _update_room_clear() -> void:
	var cleared: bool = _is_room_cleared()
	if cleared == _room_cleared:
		return
	_room_cleared = cleared
	if not cleared:
		return
	var room: RoomData = _current_room()
	# Boss 房清空 = 通关：走贤者之石结算，不再开门。
	if room != null and room.kind == RoomKind.Kind.BOSS:
		_finish_run()
		return
	door_choice.show_choices(room)


## 通关：贤者之石结算材料与灵感，弹结算界面，确认后回工坊。
func _finish_run() -> void:
	if _run_failed or _run_finished:
		return
	_run_finished = true
	door_choice.hide_choices()
	inspiration_field.clear_all()
	var counts: Dictionary = _settlement_materials()
	var result: Dictionary = {}
	if _inspiration != null:
		result = _inspiration.finish_run(counts["quality"], 0, 0.0, int(counts["boss"]))
	AudioManager.play_sfx(&"sage_stone")
	settlement.show_result(result)
	EventBus.notification.emit("通关 · 贤者之石结算 %d 灵感" % int(result.get("final", 0)))


## 结算材料：统计炼金背包与物品背包里的正式材料，按品质归类，Boss 材料单列。
## 拾取会同时进两处背包；同一材料以炼金背包为准，避免重复计算，也覆盖只用炼金背包的来源。
func _settlement_materials() -> Dictionary:
	var counts: Dictionary = {"quality": {}, "boss": 0}
	if player.alchemy_station == null:
		return counts
	var bag: AlchemyBag = player.alchemy_station.bag
	var ids: Dictionary = {}
	if player.inventory != null:
		for item_id: int in player.inventory.items.keys():
			ids[item_id] = true
	if bag != null:
		for material_id: int in bag.material_ids():
			ids[material_id] = true
	for material_id: int in ids.keys():
		if not MaterialCatalog.has_material(material_id):
			continue
		var amount: int = 0
		if bag != null and bag.count(material_id) > 0:
			amount = bag.count(material_id)
		elif player.inventory != null:
			amount = player.inventory.get_count(material_id)
		if amount <= 0:
			continue
		if MaterialCatalog.is_boss_material(material_id):
			counts["boss"] = int(counts["boss"]) + amount
		else:
			var quality: int = MaterialCatalog.quality_of(material_id)
			counts["quality"][quality] = int(counts["quality"].get(quality, 0)) + amount
	return counts


## 结算确认：回工坊。
func _on_settlement_confirmed() -> void:
	SceneManager.change_scene(WORKSHOP_SCENE)


func _is_room_cleared() -> bool:
	for child: Node in monster_spawner.get_children():
		if child is BaseMonster and not child.is_queued_for_deletion():
			return false
	return true


## 选中一条门：换算成世界编号后直接进房。
func _on_door_chosen(data_node_id: int) -> void:
	if _generator == null or _generator.run == null:
		return
	var target: int = _generator.run.world_node_of(data_node_id)
	if target < 0:
		return
	door_choice.hide_choices()
	var target_spec: MapSpec = _generator.map_spec(target)
	var gate_y: int = int(target_spec.center.y)
	if not target_spec.west_gates.is_empty():
		gate_y = target_spec.west_gates[0]
	_enter_map(target, -1, gate_y)
	AudioManager.play_sfx(&"gate_transition")
	EventBus.notification.emit("进入 %s" % _generator.run.describe(target))


func _on_monster_chunk_applied(_coords: Vector2i) -> void:
	if player.active_map == null:
		return
	for child: Node in monster_spawner.get_children():
		if not child is BaseMonster:
			continue
		var monster := child as BaseMonster
		var local: Vector2i = WorldGenerator.world_to_tile(monster.global_position) - player.active_map.origin
		if not player.active_map.contains_local(local.x, local.y):
			monster_spawner.remove_child(monster)
			monster.queue_free()


func _confine_map_monsters() -> void:
	for child: Node in monster_spawner.get_children():
		if child is BaseMonster:
			var monster := child as BaseMonster
			monster.global_position = _clamp_to_map(monster.global_position, player.active_map)


func _clamp_to_map(position: Vector2, spec: MapSpec) -> Vector2:
	var half_tile := Vector2.ONE * float(WorldGenerator.TILE_SIZE) * 0.5
	var start: Vector2 = Vector2(spec.origin) * WorldGenerator.TILE_SIZE + half_tile
	var finish: Vector2 = Vector2(spec.origin + spec.extent) * WorldGenerator.TILE_SIZE - half_tile
	return position.clamp(start, finish)


## 换个种子重开世界。
func regenerate_world() -> void:
	build_world(WorldGenerator.random_seed())
	EventBus.notification.emit("已生成新世界（种子 %d）" % GameState.world_seed)
