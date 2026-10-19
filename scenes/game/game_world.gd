class_name GameWorld
extends Node2D

## 箱庭出口保留双向传送关系，切换画面使用黑屏淡入淡出。

const TRAINING_DUMMY: PackedScene = preload("res://scenes/combat/training_dummy.tscn")
const FINAL_BOSS_SPAWN: MonsterSpawnData = preload("res://resources/monsters/final_boss_spawn_data.tres")

@export var spawn_training_dummy: bool = true
## 打开后每次生成世界都会打印完整地图报告（调试用）。
@export var debug_map_report: bool = false

@onready var chunk_manager: ChunkManager = $ChunkManager
@onready var monster_spawner: MonsterSpawner = $MonsterSpawner
@onready var player: PlayerCharacter = $Player
@onready var hud: Control = $GameHUD/HUD
@onready var camera: Camera2D = $Player/Camera2D

var _cottage_view: CottageView = null
var _training_dummy: TrainingDummy
var _training_dummy_map: int = -1
var _generator: WorldGenerator = null
var _current_node: int = -1
var _transitioning: bool = false
var _base_zoom: Vector2 = Vector2(2.0, 2.0)
var _hud_bound: bool = false
var _monster_map: int = -1
var _combat_entry_count: int = 0
## 怪物已释放到地上的道具按地图保存，离图暂停，回图继续。
var _map_entity_roots: Dictionary = {}
## 每张地图的地面材料只生成一次；拾取后返回地图不会补刷。
var _material_maps: Dictionary = {}
## 每张地图的地面材料占位格子，供草丛排除。
var _material_tiles: Dictionary = {}
## 每张地图的地面材料点位（纯函数结果），过场动画期间就能提前算好。
var _material_plans: Dictionary = {}
## 每张地图的草丛上下文（排除区）、按小块的视图与独立草层。
var _grass_contexts: Dictionary = {}
var _grass_views: Dictionary = {}
var _grass_roots: Dictionary = {}
## 每张地图已清除的草丛（key -> true）；本局内保留，重建世界才清空。
var _grass_cleared: Dictionary = {}
## 草丛按玩家周围懒生成：待做队列 + 每帧预算，进入地图时不必同步铺满整图。
var _grass_queue: Array[Dictionary] = []
var _grass_cursor: int = 0
var _grass_queued: Dictionary = {}
var _grass_focus_chunk: Vector2i = INVALID_CHUNK
var _nearby_pickup: GroundPickup = null
var _nearby_chest: WorldChest = null
var _population_maps: Dictionary = {}
const PICKUP_RADIUS: float = 36.0
## 草层容器本身压在地形之上：每个草块再按人物脚底决定画在前还是后（0 / 1），
## 武器与怪物血条在 2，永远在草之上。
const GRASS_LAYER_Z: int = 0
## 分割线只更新屏幕附近的草块，视野外多留一圈。
const GRASS_SPLIT_MARGIN: float = 480.0
## 需要逐簇分层的那一小块：角色精灵加草叶可能蒙到身上的范围。
## 这块之外的草即使跨过脚底也画在角色前面，因为根本不会和角色重叠。
const GRASS_FOCUS_HALF_WIDTH: float = 20.0
const GRASS_FOCUS_ABOVE: float = 44.0
const GRASS_FOCUS_BELOW: float = 12.0
## 草丛只生成玩家周围这个区块半径内的小块，走一步补一片。
## 视野在缩放 2 倍时约 1.3x0.7 个区块，1 圈足够盖住屏幕还留出余量。
const GRASS_RADIUS_CHUNKS: int = 1
## 每帧最多生成几块草丛；黑屏转场期间没有画面要画，可以多做。
const GRASS_CELLS_PER_FRAME: int = 8
const GRASS_CELLS_PER_FRAME_TRANSITION: int = 24
const INVALID_CHUNK: Vector2i = Vector2i(2147483647, 2147483647)


func _ready() -> void:
	_base_zoom = camera.zoom
	get_viewport().size_changed.connect(_on_viewport_resized)
	# 直接从编辑器单独运行本场景时，也要能开局。
	if GameState.world_seed == 0:
		GameState.start_new_world()
	build_world(GameState.world_seed)


func _process(_delta: float) -> void:
	# 草丛按预算长出来；转场黑屏期间也在推进，这样淡入时身边已经长好。
	_process_grass_queue()
	# 与角色的前后关系依赖角色位置，同样在转场期间保持更新。
	_update_grass_split()
	if _generator == null or player.active_map == null or _transitioning:
		return
	_sync_training_dummy()
	_confine_map_monsters()
	_refresh_pickup()
	if player.health <= 0:
		return
	var spec: MapSpec = player.active_map
	var local: Vector2i = WorldGenerator.world_to_tile(player.global_position) - spec.origin
	for link: Dictionary in _generator.gate_links(_current_node):
		var side: int = link["side"]
		if player.velocity.x * side <= 0.1:
			continue
		if absi(local.y - int(link["y"])) > MapSpec.GATE_HALF_HEIGHT:
			continue
		if (side < 0 and local.x <= 1) or (side > 0 and local.x >= spec.extent.x - 2):
			_transition_to_map(link)
			return


func _transition_to_map(link: Dictionary) -> void:
	if _transitioning or SceneManager.is_transitioning():
		return
	_transitioning = true
	var carried_velocity: Vector2 = player.velocity
	var was_physics_processing: bool = player.is_physics_processing()
	var was_handling_input: bool = player.is_processing_unhandled_input()
	var monster_mode: Node.ProcessMode = monster_spawner.process_mode
	# 黑屏之前就把下一张图铺好：地面材料点位与到达点周围的草丛，动画期间逐帧生成。
	_prewarm_map(
		_generator.map_spec(int(link["target"])),
		int(link["arrival_side"]),
		int(link["arrival_y"])
	)
	player.weapon_controller.cancel_attack()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	var swap: Callable = func() -> void:
		_enter_map(int(link["target"]), int(link["arrival_side"]), int(link["arrival_y"]))
	await SceneManager.transition_in_place(swap)
	if not is_inside_tree():
		return
	# 出口落点向里八格，保留前进方向也不会当帧触发回程。
	player.velocity = carried_velocity
	player.set_physics_process(was_physics_processing)
	player.set_process_unhandled_input(was_handling_input)
	monster_spawner.process_mode = monster_mode
	AudioManager.play_sfx(&"gate_transition")
	EventBus.notification.emit("进入 %s · %s" % [_generator.run.describe(_current_node), player.active_map.shape_name()])
	_transitioning = false


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pickup_item") and (player.stun_remaining > 0.0 or player.boss_captured or player.boss_grappled):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("regenerate_world"):
		regenerate_world()
	elif event.is_action_pressed("kill_all_monsters"):
		kill_all_monsters()
	elif event.is_action_pressed("pickup_item") and not event.is_echo():
		_refresh_pickup()
		if is_instance_valid(_nearby_chest):
			if _nearby_chest.open():
				EventBus.notification.emit("已打开%s，靠近掉落物按 E 拾取" % _nearby_chest.display_name())
			_refresh_pickup()
		elif is_instance_valid(_nearby_pickup):
			var material_name: String = _nearby_pickup.data.name
			var quantity: int = _nearby_pickup.amount
			if _nearby_pickup.collect(player):
				EventBus.notification.emit("获得 %s ×%d" % [material_name, quantity])
			_refresh_pickup()
		get_viewport().set_input_as_handled()


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
	_combat_entry_count = 0
	_clear_map_entities()
	_generator = MapScorer.build_best(seed_value, _map_config_for_monsters())
	GameState.world_seed = _generator.world_seed
	MapRng.set_shared_master(GameState.world_seed)
	# 房间类型决定内容池：只有战斗 / Boss 区域刷怪。
	monster_spawner.content = MapContent.build(_generator)
	chunk_manager.setup(_generator, player)
	if not chunk_manager.chunk_applied.is_connected(_on_grass_chunk_applied):
		chunk_manager.chunk_applied.connect(_on_grass_chunk_applied)
	_enter_map(_generator.run.start_node(), 0, -1, true)
	_place_training_dummy(_generator, WorldGenerator.world_to_tile(player.global_position))
	_setup_map_monsters()
	# 初图落位并加载后才绑定，避免把上一局的位置记为已探索。
	hud.bind_world(chunk_manager, player)
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
	if monster_spawner.content != null and monster_spawner.content.budget_of(map_node_id, MapContent.ENEMY) > 0:
		_combat_entry_count += 1
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
	_setup_world_population(spec)
	_setup_ground_materials(spec)
	_setup_grass(spec)
	_refresh_pickup()
	if _hud_bound:
		_sync_training_dummy()
		_setup_map_monsters()
		_sync_minimap()


func _sync_minimap() -> void:
	hud.minimap.refresh_position()
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
	hud.call("set_boss_visible", false)
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
	# 箱庭保留整图怪物；spawner 自身只运行限额生成与远处休眠，不做距离回收。
	monster_spawner.set_process(true)
	monster_spawner.setup(_generator, chunk_manager, player, player.active_map, _combat_entry_count, _transitioning, true)
	# 连接在 spawner 后面，同步过滤隐藏邻居预铺和边缘共享区块中的越界实体。
	chunk_manager.chunk_applied.connect(_on_monster_chunk_applied)
	_on_monster_chunk_applied(Vector2i.ZERO)
	if _current_node == _generator.run.final_node():
		_spawn_final_boss(player.active_map)


func _spawn_final_boss(spec: MapSpec) -> void:
	if spec == null or monster_spawner.content.budget_of(spec.node_id, MapContent.BOSS) <= 0:
		return
	var occupied: Dictionary = {}
	var population: Dictionary = _generator.population_for(spec.node_id)
	for kind: String in ["structures", "chests"]:
		for entry: Dictionary in population.get(kind, []):
			for y: int in range(-2, 3):
				for x: int in range(-2, 3):
					occupied[entry["tile"] + Vector2i(x, y)] = true
	var center := spec.origin + spec.extent / 2
	for radius: int in maxi(spec.extent.x, spec.extent.y):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var tile: Vector2i = center + Vector2i(x, y)
				if not spec.contains_local(tile.x - spec.origin.x, tile.y - spec.origin.y):
					continue
				if occupied.has(tile) or not _generator.is_walkable(tile):
					continue
				var boss: BaseMonster = monster_spawner.spawn_monster(FINAL_BOSS_SPAWN, tile)
				if boss != null:
					hud.call("set_boss_visible", true)
					boss.tree_exited.connect(_on_boss_exited, CONNECT_ONE_SHOT)
				return
	push_error("No walkable spawn tile for final boss in room %d" % spec.node_id)


func _on_boss_exited() -> void:
	if is_instance_valid(hud):
		hud.call("set_boss_visible", false)


func _map_entity_root(map_node_id: int) -> Node2D:
	if not _map_entity_roots.has(map_node_id):
		var root := Node2D.new()
		root.name = "MapEntities_%d" % map_node_id
		add_child(root)
		_move_before_player(root)
		_map_entity_roots[map_node_id] = root
	return _map_entity_roots[map_node_id]


func _clear_map_entities() -> void:
	if is_instance_valid(_nearby_chest):
		_nearby_chest.set_highlighted(false)
	_nearby_chest = null
	_population_maps.clear()
	if is_instance_valid(_nearby_pickup):
		_nearby_pickup.set_highlighted(false)
	_nearby_pickup = null
	_material_maps.clear()
	_material_tiles.clear()
	_material_plans.clear()
	_grass_contexts.clear()
	_grass_views.clear()
	_grass_cleared.clear()
	_grass_queue.clear()
	_grass_cursor = 0
	_grass_queued.clear()
	_grass_focus_chunk = INVALID_CHUNK
	for grass_root: Node2D in _grass_roots.values():
		remove_child(grass_root)
		grass_root.queue_free()
	_grass_roots.clear()
	for root: Node2D in _map_entity_roots.values():
		remove_child(root)
		root.queue_free()
	_map_entity_roots.clear()
	for child: Node in monster_spawner.get_children():
		if not child is BaseMonster:
			monster_spawner.remove_child(child)
			child.queue_free()
	_monster_map = -1


func _setup_world_population(spec: MapSpec) -> void:
	if _population_maps.has(spec.node_id):
		return
	var entity_root: Node2D = _map_entity_root(spec.node_id)
	var population: Dictionary = _generator.population_for(spec.node_id)
	for entry: Dictionary in population.get("structures", []):
		var structure := WorldStructure.new()
		structure.name = "Structure_%s_%d_%d" % [entry["kind"], entry["tile"].x, entry["tile"].y]
		structure.kind = entry["kind"]
		structure.variant = int(entry["variant"])
		structure.biome_id = spec.biome_id
		structure.position = WorldGenerator.tile_to_world(entry["tile"])
		entity_root.add_child(structure)
	for entry: Dictionary in population.get("chests", []):
		var chest := WorldChest.new()
		chest.name = "Chest_%d_%d" % [entry["tile"].x, entry["tile"].y]
		chest.bind(entry, _generator)
		chest.position = WorldGenerator.tile_to_world(entry["tile"])
		entity_root.add_child(chest)
	for entry: Dictionary in population.get("drops", []):
		var data: IngredientData = ItemListGlobal.get_template(int(entry["item_id"])) as IngredientData
		if data == null:
			continue
		var pickup := GroundPickup.new()
		pickup.name = "WorldLoot_%d_%d" % [entry["tile"].x, entry["tile"].y]
		pickup.bind(data, int(entry["amount"]), _generator)
		pickup.position = WorldGenerator.tile_to_world(entry["tile"])
		entity_root.add_child(pickup)
	_population_maps[spec.node_id] = true


func _setup_ground_materials(spec: MapSpec) -> void:
	var entity_root: Node2D = _map_entity_root(spec.node_id)
	if not _material_maps.has(spec.node_id):
		# 点位在过场动画期间就备好了，这里只建节点。
		_ensure_material_plan(spec)
		for entry: Dictionary in _material_plans.get(spec.node_id, []):
			var data: IngredientData = ItemListGlobal.get_template(int(entry["item_id"])) as IngredientData
			if data == null:
				continue
			var pickup := GroundPickup.new()
			pickup.name = "Material_%d_%d" % [entry["tile"].x, entry["tile"].y]
			pickup.bind(data, int(entry["amount"]), _generator)
			pickup.position = WorldGenerator.tile_to_world(entry["tile"])
			entity_root.add_child(pickup)
		_material_maps[spec.node_id] = true
	# 结构画在草后面：草层要排在实体层之后、角色之前。
	var grass_root: Node2D = _grass_roots.get(spec.node_id)
	if grass_root != null:
		_move_before_player(grass_root)
	_sync_layer_visibility()


## 只有当前箱庭的实体与草丛可见；其余隐藏并暂停。
func _sync_layer_visibility() -> void:
	for id: int in _map_entity_roots:
		var map_root: Node2D = _map_entity_roots[id]
		map_root.visible = id == _current_node
		map_root.process_mode = (
			Node.PROCESS_MODE_INHERIT if id == _current_node else Node.PROCESS_MODE_DISABLED
		)
	for id: int in _grass_roots:
		var grass_root: Node2D = _grass_roots[id]
		grass_root.visible = id == _current_node
		grass_root.process_mode = (
			Node.PROCESS_MODE_INHERIT if id == _current_node else Node.PROCESS_MODE_DISABLED
		)


func _setup_grass(spec: MapSpec) -> void:
	if _generator == null:
		return
	_ensure_grass_context(spec)
	# 换地图时丢掉上一张图没做完的队列，重新按新位置排。
	_grass_queue.clear()
	_grass_cursor = 0
	_grass_queued.clear()
	_grass_focus_chunk = INVALID_CHUNK
	_queue_grass_around(spec)


## 把玩家周围视野圈内已经铺好的区块排进队列，近的先做。
## 换地图或换区块时重新排；整图的草丛不再在进图时一次算完。
func _queue_grass_around(spec: MapSpec) -> void:
	if _generator == null or player.active_map == null:
		return
	var focus: Vector2i = WorldGenerator.tile_to_chunk(
		WorldGenerator.world_to_tile(player.global_position)
	)
	if focus == _grass_focus_chunk:
		return
	_grass_focus_chunk = focus
	_queue_grass_ring(spec, focus)


## 把以 focus 区块为中心的视野圈里、已经铺好的区块排进队列（近的先做）。
## 过场动画预热下一张图时也走这里，只是中心换成到达点。
func _queue_grass_ring(spec: MapSpec, focus: Vector2i) -> void:
	if _generator == null:
		return
	var per_side: int = _grass_cells_per_chunk()
	var origin: Vector2i = focus - Vector2i(GRASS_RADIUS_CHUNKS, GRASS_RADIUS_CHUNKS)
	var span: int = GRASS_RADIUS_CHUNKS * 2 + 1
	var pending: Array[Dictionary] = []
	for cy: int in span:
		for cx: int in span:
			var chunk: Vector2i = origin + Vector2i(cx, cy)
			if chunk_manager.get_cached_chunk(chunk) == null:
				continue
			for sub: int in per_side * per_side:
				var cell: Vector2i = chunk * per_side + Vector2i(sub % per_side, sub / per_side)
				var key := Vector3i(cell.x, cell.y, spec.node_id)
				if _grass_queued.has(key) or _grass_cell_is_populated(spec, cell):
					continue
				_grass_queued[key] = true
				pending.append({"spec_id": spec.node_id, "cell": cell, "chunk": chunk})
	if pending.is_empty():
		return
	var center := Vector2(focus * WorldGenerator.CHUNK_SIZE)
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _grass_cell_distance(a["cell"], center) < _grass_cell_distance(b["cell"], center)
	)
	_grass_queue.append_array(pending)


func _grass_cell_distance(cell: Vector2i, center_tile: Vector2) -> float:
	return (Vector2(cell * GrassView.CELL_TILES) - center_tile).length_squared()


func _grass_cell_is_populated(spec: MapSpec, cell: Vector2i) -> bool:
	var views: Dictionary = _grass_views.get(spec.node_id, {})
	var view: GrassView = views.get(cell)
	return view != null and view.is_populated()


## 每帧按预算把队列里的草丛长出来；转场黑屏期间可以多做。
func _process_grass_queue() -> void:
	if _generator == null or player.active_map == null:
		return
	var spec: MapSpec = player.active_map
	_queue_grass_around(spec)
	if _grass_cursor >= _grass_queue.size():
		return
	var budget: int = (
		GRASS_CELLS_PER_FRAME_TRANSITION
		if _transitioning or SceneManager.is_transitioning()
		else GRASS_CELLS_PER_FRAME
	)
	var attempts: int = 0
	while attempts < budget and _grass_cursor < _grass_queue.size():
		attempts += 1
		var entry: Dictionary = _grass_queue[_grass_cursor]
		_grass_cursor += 1
		var cell: Vector2i = entry["cell"]
		_grass_queued.erase(Vector3i(cell.x, cell.y, int(entry["spec_id"])))
		var entry_spec: MapSpec = _generator.map_spec(int(entry["spec_id"]))
		if entry_spec != null:
			_grow_grass_cell(entry_spec, cell, entry["chunk"])
	if _grass_cursor >= _grass_queue.size():
		_grass_queue.clear()
		_grass_cursor = 0


func _grow_grass_cell(spec: MapSpec, cell: Vector2i, chunk_coords: Vector2i) -> bool:
	var data: ChunkData = chunk_manager.get_cached_chunk(chunk_coords)
	if data == null:
		return false
	var view: GrassView = _grass_view_for(spec, cell)
	if view == null or view.is_populated():
		return false
	view.populate(data, chunk_coords)
	return true


## 把节点插到角色之前（角色之前的层按树序先画）。
## move_child 内部先摘下节点再插入，节点本来就在角色之前的索引需要补偿一位，
## 否则会插到角色之后。
func _move_before_player(node: Node2D) -> void:
	var target: int = player.get_index()
	if node.get_index() < target:
		target -= 1
	move_child(node, maxi(target, 0))


## 每张地图一层草丛容器：草块自己的 z 由 GrassView 按人物脚底逐块决定。
func _grass_root(map_node_id: int) -> Node2D:
	if _grass_roots.has(map_node_id):
		return _grass_roots[map_node_id]
	var root := Node2D.new()
	root.name = "GrassLayer_%d" % map_node_id
	root.z_index = GRASS_LAYER_Z
	root.visible = map_node_id == _current_node
	add_child(root)
	# 放在角色之前：z=0 的草块因此画在角色背后，z=1 的画在角色前面。
	_move_before_player(root)
	_grass_roots[map_node_id] = root
	return root


## 每帧把视野内草块的分割线更新成人物脚底：
## 脚底以上的草盖住人物，脚底以下的草被人物踩住。
## 只有可能和角色重叠的一两块才逐簇分层，其余整块归层，避免走路时不停重绘。
func _update_grass_split() -> void:
	if _generator == null or player.active_map == null:
		return
	var feet: float = player.global_position.y + _player_feet_offset()
	var focus := Rect2(
		Vector2(
			player.global_position.x - GRASS_FOCUS_HALF_WIDTH,
			feet - GRASS_FOCUS_ABOVE
		),
		Vector2(GRASS_FOCUS_HALF_WIDTH * 2.0, GRASS_FOCUS_ABOVE + GRASS_FOCUS_BELOW)
	)
	var area := Rect2(
		player.global_position - Vector2.ONE * GRASS_SPLIT_MARGIN,
		Vector2.ONE * GRASS_SPLIT_MARGIN * 2.0
	)
	for node: Node in GrassView.views_in_rect(area):
		var view := node as GrassView
		if view == null or not view.is_visible_in_tree():
			continue
		view.update_focus(feet, focus)


## 角色最低处（精灵底边）相对原点的偏移；换角色贴图时会自动跟着变。
func _player_feet_offset() -> float:
	var sprite: Sprite2D = player.sprite
	if sprite == null:
		return float(WorldGenerator.TILE_SIZE) * 0.5
	return sprite.get_rect().end.y * absf(sprite.scale.y)


## 过场动画期间优先准备到达视口的地形、材料点位与草丛。
## 黑屏结束时视口内容已经在位，切图本身只剩很轻的工作。
func _prewarm_map(spec: MapSpec, side: int, gate_y: int) -> void:
	if _generator == null or spec == null:
		return
	_ensure_grass_context(spec)
	var arrival: Vector2 = _generator.entry_position(spec.node_id, side, gate_y)
	chunk_manager.prewarm_arrival(spec.node_id, arrival)
	_queue_grass_ring(spec, WorldGenerator.tile_to_chunk(WorldGenerator.world_to_tile(arrival)))


## 地面材料点位是纯函数结果，提前算好并缓存；进图时直接按点位建节点。
func _ensure_material_plan(spec: MapSpec) -> void:
	if _material_plans.has(spec.node_id):
		return
	var plan: Array[Dictionary] = GroundMaterials.plan(_generator, spec)
	_material_plans[spec.node_id] = plan
	var tiles: Dictionary = {}
	for entry: Dictionary in plan:
		tiles[entry["tile"]] = true
	_material_tiles[spec.node_id] = tiles


func _ensure_grass_context(spec: MapSpec) -> void:
	if _grass_contexts.has(spec.node_id):
		return
	_ensure_material_plan(spec)
	_grass_contexts[spec.node_id] = GrassContext.create(
		_generator, spec, _material_tiles.get(spec.node_id, {})
	)
	if not _grass_cleared.has(spec.node_id):
		_grass_cleared[spec.node_id] = {}


## 一个区块覆盖多少个小块：区块 32 格、块 8 格，正好 4x4。
func _grass_cells_per_chunk() -> int:
	return WorldGenerator.CHUNK_SIZE / GrassView.CELL_TILES


func _grass_view_for(spec: MapSpec, cell: Vector2i) -> GrassView:
	if not _grass_contexts.has(spec.node_id) or not _grass_cleared.has(spec.node_id):
		return null
	if not _grass_views.has(spec.node_id):
		_grass_views[spec.node_id] = {}
	var views: Dictionary = _grass_views[spec.node_id]
	if views.has(cell):
		return views[cell]
	var view := GrassView.new()
	view.name = "Grass_%d_%d" % [cell.x, cell.y]
	view.bind(
		cell,
		Rect2i(spec.origin, spec.extent),
		_generator,
		_grass_contexts[spec.node_id],
		_grass_cleared[spec.node_id]
	)
	_grass_root(spec.node_id).add_child(view)
	views[cell] = view
	return view


## 区块铺好后，可能正好落在玩家视野圈里：让下一帧重新按位置排队。
func _on_grass_chunk_applied(_coords: Vector2i) -> void:
	if _generator == null or player.active_map == null:
		return
	if not _grass_contexts.has(player.active_map.node_id):
		return
	_grass_focus_chunk = INVALID_CHUNK


func _refresh_pickup() -> void:
	if is_instance_valid(_nearby_chest):
		_nearby_chest.set_highlighted(false)
	_nearby_chest = null
	if is_instance_valid(_nearby_pickup):
		_nearby_pickup.set_highlighted(false)
	_nearby_pickup = null
	if player.health <= 0 or player.inventory == null or $GameHUD/BagUi.visible or $GameHUD/Alchemy.visible or get_viewport().gui_is_dragging():
		hud.show_pickup(null)
		return
	var entity_root: Node2D = _map_entity_roots.get(_current_node)
	# 新击杀掉落暂存在 spawner，切图后归入所属地图；两处都要能立即拾取。
	var pickup_roots: Array[Node2D] = [monster_spawner]
	if entity_root != null:
		pickup_roots.append(entity_root)
	# 拾取范围受升级卡“拾荒”影响。
	var radius: float = player.pickup_radius_tiles() * float(WorldGenerator.TILE_SIZE)
	var closest: float = radius * radius
	for pickup_root: Node2D in pickup_roots:
		for child: Node in pickup_root.get_children():
			if child is WorldChest and not child.opened and not child.is_queued_for_deletion():
				var chest_distance: float = player.global_position.distance_squared_to(child.global_position)
				if chest_distance < closest and _can_reach_pickup(child.global_position):
					closest = chest_distance
					_nearby_chest = child
					_nearby_pickup = null
				continue
			if not child is GroundPickup or child.is_queued_for_deletion():
				continue
			var pickup := child as GroundPickup
			if not pickup.is_available_for_pickup():
				continue
			var distance: float = player.global_position.distance_squared_to(pickup.global_position)
			if distance < closest and _can_reach_pickup(pickup.global_position):
				closest = distance
				_nearby_pickup = pickup
				_nearby_chest = null
	if is_instance_valid(_nearby_pickup):
		_nearby_pickup.set_highlighted(true)
	hud.show_pickup(_nearby_pickup)
	if is_instance_valid(_nearby_chest):
		_nearby_chest.set_highlighted(true)
		hud.show_chest(_nearby_chest)


func _can_reach_pickup(target: Vector2) -> bool:
	var steps: int = maxi(1, ceili(player.global_position.distance_to(target) / 4.0))
	for step: int in range(1, steps + 1):
		var tile: Vector2i = WorldGenerator.world_to_tile(player.global_position.lerp(target, float(step) / steps))
		if not _generator.is_walkable(tile):
			return false
	return true


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
