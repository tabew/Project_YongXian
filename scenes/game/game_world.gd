class_name GameWorld
extends Node2D

## 传统 RPG 箱庭：触及出口立即换到目标入口，主视图只显示当前区域。

const TRAINING_DUMMY: PackedScene = preload("res://scenes/combat/training_dummy.tscn")

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
var _base_zoom: Vector2 = Vector2(2.0, 2.0)
var _hud_bound: bool = false
var _monster_map: int = -1
## 怪物已释放到地上的道具按地图保存，离图暂停，回图继续。
var _map_entity_roots: Dictionary = {}
## 每张地图的地面材料只生成一次；拾取后返回地图不会补刷。
var _material_maps: Dictionary = {}
var _nearby_pickup: GroundPickup = null
const PICKUP_RADIUS: float = 36.0


func _ready() -> void:
	_base_zoom = camera.zoom
	get_viewport().size_changed.connect(_on_viewport_resized)
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
			var carried_velocity: Vector2 = player.velocity
			_enter_map(link["target"], link["arrival_side"], link["arrival_y"])
			# 落点与出口带分离，按住同方向即可走进新箱庭，不会立即弹回。
			player.velocity = carried_velocity
			EventBus.notification.emit("进入 %s · %s" % [_generator.run.describe(_current_node), player.active_map.shape_name()])
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate_world"):
		regenerate_world()
	elif event.is_action_pressed("kill_all_monsters"):
		kill_all_monsters()
	elif event.is_action_pressed("pickup_item") and not event.is_echo():
		_refresh_pickup()
		if is_instance_valid(_nearby_pickup):
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
	_clear_map_entities()
	_generator = MapScorer.build_best(seed_value)
	GameState.world_seed = _generator.world_seed
	MapRng.set_shared_master(GameState.world_seed)
	# 房间类型决定内容池：只有战斗 / Boss 区域刷怪。
	monster_spawner.content = MapContent.build(_generator)
	chunk_manager.setup(_generator, player)
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


## 一次同步完成入口落位、相机跳转与可见地图替换，不播放淡入淡出。
func _enter_map(map_node_id: int, side: int = 0, gate_y: int = -1, reset_health: bool = false) -> void:
	var spec: MapSpec = _generator.map_spec(map_node_id)
	if spec == null:
		return
	_current_node = map_node_id
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


## 原 spawner 保留全部生成/战斗功能；切图重建实体，避免旧区域怪物继续攻击。
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
	monster_spawner.setup(_generator, chunk_manager, player)
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
	_material_maps.clear()
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
			pickup.bind(data, int(entry["amount"]))
			pickup.position = WorldGenerator.tile_to_world(entry["tile"])
			entity_root.add_child(pickup)
		_material_maps[spec.node_id] = true
	for id: int in _map_entity_roots:
		var map_root: Node2D = _map_entity_roots[id]
		map_root.visible = id == _current_node
		map_root.process_mode = Node.PROCESS_MODE_INHERIT if id == _current_node else Node.PROCESS_MODE_DISABLED


func _refresh_pickup() -> void:
	if is_instance_valid(_nearby_pickup):
		_nearby_pickup.set_highlighted(false)
	_nearby_pickup = null
	if player.health <= 0 or player.inventory == null or $GameHUD/BagUi.visible or $GameHUD/Alchemy.visible:
		hud.show_pickup(null)
		return
	var entity_root: Node2D = _map_entity_roots.get(_current_node)
	var closest: float = PICKUP_RADIUS * PICKUP_RADIUS
	if entity_root != null:
		for child: Node in entity_root.get_children():
			if not child is GroundPickup or child.is_queued_for_deletion():
				continue
			var pickup := child as GroundPickup
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
