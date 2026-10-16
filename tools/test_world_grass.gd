extends SceneTree

## 草丛：一簇就是一丛草、比角色高、各群系自然地面都长、同种子可复现、
## 武器可切且不补刷、切割只查邻近小块（性能回归）。

const TEST_SEED: int = 20261016
## 会长草的地面（WorldGrass.DENSITY > 0），用来核对覆盖范围。
const GROWING_TERRAINS: Array[int] = [
	Terrain.Kind.SAND, Terrain.Kind.GRASS, Terrain.Kind.SWAMP, Terrain.Kind.SAVANNA,
	Terrain.Kind.DESERT, Terrain.Kind.TUNDRA, Terrain.Kind.STONE, Terrain.Kind.SNOW,
]
const WEAPON_SCENES: Array[String] = [
	"res://scenes/weapons/swing_attack.tscn",
	"res://scenes/weapons/yoyo_attack.tscn",
	"res://scenes/weapons/depth_strike_attack.tscn",
]
## 切割一次允许的耗时上限（微秒）：只查邻近小块，不应随全图草量增长。
const CUT_BUDGET_USEC: int = 400
## 进入一张地图允许的耗时上限（微秒）：草丛与材料都已预热，整图草量不进这一笔。
const ENTRY_BUDGET_USEC: int = 60000

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_data_layer()
	var generator := WorldGenerator.new(TEST_SEED)
	_test_every_region_grows_grass(generator)
	_test_region_population(generator, generator.map_specs()[0])
	_test_determinism()
	_test_cut_queries_stay_local()
	await _test_weapon_cut()
	await _test_live_world()
	print("WORLD_GRASS: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 纯函数：同输入同输出、每格至多两簇、根部落在格内、key 不撞、配色跟随地面。
func _test_data_layer() -> void:
	var tile := Vector2i(7, -3)
	var first: Array = WorldGrass.tufts_at(TEST_SEED, 0, Terrain.Kind.GRASS, tile)
	var again: Array = WorldGrass.tufts_at(TEST_SEED, 0, Terrain.Kind.GRASS, tile)
	_check(first == again, "same_seed_and_tile_give_identical_clumps")
	_check(first.size() <= WorldGrass.MAX_PER_TILE, "clump_count_never_exceeds_max")
	var keys: Dictionary = {}
	var grown: int = 0
	for probe: int in 600:
		var at := Vector2i(probe * 31 - 200, probe * 17 - 100)
		var clumps: Array = WorldGrass.tufts_at(TEST_SEED, 0, Terrain.Kind.SAVANNA, at)
		grown += clumps.size()
		for clump: Dictionary in clumps:
			var position: Vector2 = clump["position"]
			var local := position / float(WorldGenerator.TILE_SIZE) - Vector2(at)
			_check(
				local.x >= WorldGrass.MARGIN_X - 0.0001
				and local.x <= 1.0 - WorldGrass.MARGIN_X + 0.0001
				and local.y >= WorldGrass.BASE_TOP - 0.0001
				and local.y <= WorldGrass.BASE_BOTTOM + 0.0001,
				"clump_root_stays_inside_its_tile"
			)
			_check(not keys.has(clump["key"]), "clump_keys_are_unique_across_tiles")
			keys[clump["key"]] = true
			_check(
				clump["palette"] == int(WorldGrass.PALETTE[Terrain.Kind.SAVANNA]),
				"clump_palette_follows_the_ground_it_grows_on"
			)
			_check(
				WorldGrass.blade_count(clump["shape"]) >= 5
				and WorldGrass.blade_count(clump["shape"]) <= 8,
				"a_clump_is_a_bunch_of_blades_not_a_single_spear"
			)
	_check(grown > 20, "sampled_area_grows_a_reasonable_amount_of_grass")
	# 水面与阻挡地形一簇都不长。
	for terrain: int in Terrain.COUNT:
		var on_water: int = 0
		for probe: int in 200:
			on_water += WorldGrass.tufts_at(
				TEST_SEED, 0, terrain, Vector2i(probe * 13, probe * 7)
			).size()
		var should_grow: bool = GROWING_TERRAINS.has(terrain)
		_check(on_water > 0 if should_grow else on_water == 0, "terrain_%d_coverage" % terrain)


## 关键回归：不能只有初图有草 —— 每张箱庭都要长得出草。
func _test_every_region_grows_grass(generator: WorldGenerator) -> void:
	var specs: Array[MapSpec] = generator.map_specs()
	_check(specs.size() >= 12, "world_has_all_regions")
	var grass_regions: int = 0
	var blank_regions: Array[int] = []
	for spec: MapSpec in specs:
		if _count_clumps(generator, spec) > 0:
			grass_regions += 1
		else:
			blank_regions.append(spec.node_id)
	_check(
		blank_regions.is_empty(),
		"every_region_grows_grass (got %d/%d, blank=%s)" % [
			grass_regions, specs.size(), str(blank_regions)
		]
	)
	print("  regions with grass: %d/%d" % [grass_regions, specs.size()])


## 样点统计一张箱庭里能长出多少簇草。
func _count_clumps(generator: WorldGenerator, spec: MapSpec) -> int:
	var clumps: int = 0
	var margin: int = 3
	for y: int in range(spec.origin.y + margin, spec.origin.y + spec.extent.y - margin, 6):
		for x: int in range(spec.origin.x + margin, spec.origin.x + spec.extent.x - margin, 6):
			var tile := Vector2i(x, y)
			clumps += WorldGrass.tufts_at(
				generator.world_seed, generator.variant, generator.sample_terrain(tile), tile
			).size()
	return clumps


## 两个同种子生成器对同一小块必须给出完全一致的草丛。
func _test_determinism() -> void:
	var a := WorldGenerator.new(TEST_SEED)
	var b := WorldGenerator.new(TEST_SEED)
	var spec: MapSpec = a.map_specs()[0]
	var context: GrassContext = GrassContext.create(a, spec, {})
	var found: Dictionary = _grassy_cell(a, spec, context, {}, 4)
	_check(not found.is_empty(), "sample_cell_grows_grass")
	if found.is_empty():
		return
	var cell: Vector2i = found["cell"]
	var chunk: Vector2i = found["chunk"]
	var first: Array = found["clumps"]
	_free_view(found["view"])
	var other := _make_view(b, spec, context, cell, {})
	other.populate(b.generate_chunk(chunk, 0), chunk)
	var second: Array = _clumps_of(other)
	_free_view(other)
	_check(
		first.size() == second.size() and first == second,
		"regenerated_world_reproduces_identical_grass"
	)


## 除草只应碰到邻近的小块：查询规模必须与全图草量无关。
func _test_cut_queries_stay_local() -> void:
	var generator := WorldGenerator.new(TEST_SEED)
	var spec: MapSpec = generator.map_specs()[0]
	var context: GrassContext = GrassContext.create(generator, spec, {})
	var found: Dictionary = _grassy_cell(generator, spec, context, {}, 1)
	_check(not found.is_empty(), "test_cell_has_grass")
	if found.is_empty():
		return
	var view: GrassView = found["view"]
	# 一格 128 像素见方，一次挥击的形状只覆盖 1-4 块。
	var around := Rect2(Vector2(view.position) + Vector2(64, 64), Vector2(60, 60))
	_check(
		GrassView.views_in_rect(around).size() <= 4,
		"weapon_shape_only_touches_neighbouring_cells"
	)
	var far := Rect2(Vector2(view.position) + Vector2(4096, 4096), Vector2(60, 60))
	_check(GrassView.views_in_rect(far).is_empty(), "distant_queries_find_nothing")
	_free_view(view)


## 纯函数 + 视图逻辑：只长可长草的地面、避开排除区、切过不再补刷。
func _test_region_population(generator: WorldGenerator, spec: MapSpec) -> void:
	var occupied: Dictionary = {}
	for entry: Dictionary in GroundMaterials.plan(generator, spec):
		occupied[entry["tile"]] = true
	var context: GrassContext = GrassContext.create(generator, spec, occupied)
	var first_chunk: Vector2i = WorldGenerator.tile_to_chunk(spec.origin)
	var last_chunk: Vector2i = WorldGenerator.tile_to_chunk(spec.origin + spec.extent - Vector2i.ONE)
	var total: int = 0
	for cy: int in range(first_chunk.y, last_chunk.y + 1):
		for cx: int in range(first_chunk.x, last_chunk.x + 1):
			var coords := Vector2i(cx, cy)
			var data: ChunkData = generator.generate_chunk(coords, 0)
			var per_side: int = WorldGenerator.CHUNK_SIZE / GrassView.CELL_TILES
			for sub_y: int in per_side:
				for sub_x: int in per_side:
					var view := _make_view(
						generator, spec, context, coords * per_side + Vector2i(sub_x, sub_y), {}
					)
					view.populate(data, coords)
					total += _audit_view(generator, spec, view, occupied, context)
					_free_view(view)
	_check(total > 0, "region_grows_grass")


func _audit_view(
	generator: WorldGenerator,
	spec: MapSpec,
	view: GrassView,
	occupied: Dictionary,
	context: GrassContext
) -> int:
	var count: int = 0
	for clump: Dictionary in _clumps_of(view):
		count += 1
		var tile: Vector2i = WorldGenerator.world_to_tile(clump["position"])
		var terrain: int = generator.sample_terrain(tile)
		_check(GROWING_TERRAINS.has(terrain), "clump_only_grows_on_natural_ground")
		_check(generator.sample_route(tile) == Route.Kind.NONE, "clump_never_grows_on_roads")
		_check(not occupied.has(tile), "clump_avoids_ground_material_tiles")
		_check(context.allows(tile), "clump_avoids_structures_chests_cottage_and_gates")
		if spec.cottage != null:
			_check(
				not spec.cottage.bounds.has_point(tile - spec.origin),
				"clump_avoids_cottage_floor"
			)
	return count


## 三把武器的攻击场景都能清草；同一形状重复扫不会重复结算；换视图不补刷。
func _test_weapon_cut() -> void:
	var generator := WorldGenerator.new(TEST_SEED)
	var spec: MapSpec = generator.map_specs()[0]
	var context: GrassContext = GrassContext.create(generator, spec, {})
	var cleared: Dictionary = {}
	var found: Dictionary = _grassy_cell(generator, spec, context, cleared, WEAPON_SCENES.size() + 3)
	_check(not found.is_empty(), "somewhere_grows_enough_grass_for_the_weapon_test")
	if found.is_empty():
		return
	var view: GrassView = found["view"]
	var clumps: Array = found["clumps"]
	var chunk: Vector2i = found["chunk"]
	var polygon := _square(clumps[0]["position"])
	_check(view.cut_area(polygon) >= 1, "cut_area_clears_clump_under_polygon")
	_check(view.cut_area(polygon) == 0, "second_cut_of_same_area_clears_nothing")
	_check(cleared.has(clumps[0]["key"]), "cleared_key_recorded_for_persistence")
	# 新视图共享清除记录：切过的草不会因为重新 populate 长回来。
	var fresh := _make_view(generator, spec, context, view._cell, cleared)
	fresh.populate(generator.generate_chunk(chunk, 0), chunk)
	_check(fresh.live_clumps() < fresh._positions.size(), "reentry_view_keeps_cleared_clumps_hidden")
	for index: int in WEAPON_SCENES.size():
		var attack: Node2D = load(WEAPON_SCENES[index]).instantiate() as Node2D
		root.add_child(attack)
		var spot: Vector2 = Vector2.ZERO
		for clump: Dictionary in clumps:
			if not cleared.has(clump["key"]):
				spot = clump["position"]
				break
		attack.global_position = spot
		var local := _square(Vector2.ZERO)
		var cut: Variant = attack.call("_clear_grass", local)
		_check(int(cut) >= 1, "%s_clears_grass_with_its_attack_shape" % WEAPON_SCENES[index])
		_check(
			int(attack.call("_clear_grass", local)) == 0,
			"%s_does_not_recut_the_same_grass" % WEAPON_SCENES[index]
		)
		root.remove_child(attack)
		attack.queue_free()
	_free_view(fresh)
	_free_view(view)


## 找一块长出足够多草的小块视图，连同它的小块坐标与所在区块坐标。
## 视图留在场景树里由调用方释放，避免重复生成同一区块的数据。
func _grassy_cell(
	generator: WorldGenerator,
	spec: MapSpec,
	context: GrassContext,
	cleared: Dictionary,
	wanted: int
) -> Dictionary:
	var first_chunk: Vector2i = WorldGenerator.tile_to_chunk(spec.origin)
	var last_chunk: Vector2i = WorldGenerator.tile_to_chunk(spec.origin + spec.extent - Vector2i.ONE)
	var per_side: int = WorldGenerator.CHUNK_SIZE / GrassView.CELL_TILES
	for cy: int in range(first_chunk.y, last_chunk.y + 1):
		for cx: int in range(first_chunk.x, last_chunk.x + 1):
			var chunk := Vector2i(cx, cy)
			var data: ChunkData = generator.generate_chunk(chunk, 0)
			for sub_y: int in per_side:
				for sub_x: int in per_side:
					var cell: Vector2i = chunk * per_side + Vector2i(sub_x, sub_y)
					var view := _make_view(generator, spec, context, cell, cleared)
					view.populate(data, chunk)
					var clumps: Array = _clumps_of(view)
					if clumps.size() >= wanted:
						return {"view": view, "clumps": clumps, "cell": cell, "chunk": chunk}
					_free_view(view)
	return {}


func _clumps_of(view: GrassView) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(view._positions.size()):
		result.append({
			"position": view._positions[index],
			"key": Vector2i(view._key_x[index], view._key_y[index]),
		})
	return result


func _make_view(
	generator: WorldGenerator,
	spec: MapSpec,
	context: GrassContext,
	cell: Vector2i,
	cleared: Dictionary
) -> GrassView:
	var view := GrassView.new()
	view.bind(cell, Rect2i(spec.origin, spec.extent), generator, context, cleared)
	root.add_child(view)
	return view


func _free_view(view: GrassView) -> void:
	root.remove_child(view)
	view.queue_free()


func _square(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(-14.0, -14.0),
		center + Vector2(14.0, -14.0),
		center + Vector2(14.0, 14.0),
		center + Vector2(-14.0, 14.0),
	])


## 端到端：启动真正的游戏世界。草丛按玩家视野圈懒生成，进图不再同步铺满整图。
func _test_live_world() -> void:
	root.size = Vector2i(1280, 720)
	var world := (load("res://scenes/game/game_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	world.player.set_physics_process(false)
	world.monster_spawner.process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("GameHUD/BagUi").hide()
	world.get_node("GameHUD/Alchemy").hide()
	var manager: ChunkManager = world.chunk_manager
	for _frame: int in 900:
		if manager.map_ready():
			break
		await process_frame
	_check(manager.map_ready(), "live_world_finishes_painting_chunks")
	var spec: MapSpec = world.player.active_map
	await _wait_for_live_grass(world, spec)
	var cells: int = _live_grass_cells(world, spec)
	_check(cells > 0, "live_world_grows_grass_views_around_the_player")
	# 关键性能回归：进图只排队，不再同步把整图的草算完。
	_check(cells < _map_cell_count(spec), "grass_is_not_generated_for_the_whole_map_on_entry")
	# 草层必须高于角色，才能在画面上盖住人和怪。
	var views: Array = GrassView.views_in_rect(
		Rect2(Vector2(spec.origin) * 16.0, Vector2(spec.extent) * 16.0)
	)
	var covered: bool = not views.is_empty()
	for node: Node in views:
		if ((node as GrassView).get_parent() as Node2D).z_index <= world.player.z_index:
			covered = false
	_check(covered, "grass_layer_renders_above_the_player")
	# 玩家出生在小屋内（不长草），挪到最近的一簇草上再测挥砍。
	var spot: Vector2 = Vector2.INF
	var best: float = INF
	for node: Node in views:
		var view := node as GrassView
		for index: int in view._positions.size():
			if view._cleared.has(Vector2i(view._key_x[index], view._key_y[index])):
				continue
			var at: Vector2 = view._positions[index]
			var distance: float = at.distance_squared_to(world.player.global_position)
			if distance < best:
				best = distance
				spot = at
	_check(spot != Vector2.INF, "live_world_has_a_clump_inside_the_arena")
	# 用挥砍形状连扫 400 次：只查邻近小块，总耗时必须很小。
	var attack: Node2D = load(WEAPON_SCENES[0]).instantiate() as Node2D
	root.add_child(attack)
	attack.global_position = spot
	var local := _square(Vector2.ZERO)
	var started: int = Time.get_ticks_usec()
	var cuts: int = 0
	for _sweep: int in 400:
		cuts += int(attack.call("_clear_grass", local))
	var per_sweep: int = (Time.get_ticks_usec() - started) / 400
	print("  live sweep: cuts=%d avg=%dus" % [cuts, per_sweep])
	_check(cuts >= 1, "live_world_grass_can_be_cut")
	_check(per_sweep < CUT_BUDGET_USEC, "a_single_grass_sweep_costs_almost_nothing")
	root.remove_child(attack)
	attack.queue_free()
	# 换一张箱庭：走门进真实的邻图（邻图已预铺，和玩家实际切图一致）。
	var other: MapSpec = null
	var gate: Dictionary = {}
	for link: Dictionary in world._generator.gate_links(spec.node_id):
		var candidate: MapSpec = world._generator.map_spec(int(link["target"]))
		if candidate != null and candidate.node_id != spec.node_id:
			other = candidate
			gate = link
			break
	_check(other != null, "start_region_has_a_neighbour_to_walk_into")
	if other != null:
		var side: int = int(gate["arrival_side"])
		var gate_y: int = int(gate["arrival_y"])
		# 过场动画一开始就预热：材料点位与到达点周围的草丛。
		world._prewarm_map(other, side, gate_y)
		for _frame: int in 30:
			await process_frame
		var arrival: Vector2 = world._generator.entry_position(other.node_id, side, gate_y)
		_check(
			_grass_cell_at(world, other, arrival) > 0,
			"prewarm_grows_grass_at_the_arrival_point_before_the_swap"
		)
		# 预热过的进图不该再随整图草量增长。
		var entry_start: int = Time.get_ticks_usec()
		world._enter_map(other.node_id)
		var entry_usec: int = Time.get_ticks_usec() - entry_start
		print("  live map entry: %.1fms" % (entry_usec / 1000.0))
		_check(entry_usec < ENTRY_BUDGET_USEC, "entering_a_prewarmed_map_stays_cheap")
		await _wait_for_live_grass(world, other)
		_check(_live_grass_cells(world, other) > 0, "the_new_map_streams_grass_around_the_player")
	world.queue_free()
	for _frame: int in 30:
		await process_frame


func _wait_for_live_grass(world: Node, spec: MapSpec) -> void:
	for _frame: int in 150:
		if _live_grass_cells(world, spec) > 8:
			return
		await process_frame


func _live_grass_cells(world: Node, spec: MapSpec) -> int:
	var views: Dictionary = world._grass_views.get(spec.node_id, {})
	var count: int = 0
	for cell: Vector2i in views.keys():
		if (views[cell] as GrassView).is_populated():
			count += 1
	return count


func _map_cell_count(spec: MapSpec) -> int:
	return (
		ceili(float(spec.extent.x) / float(GrassView.CELL_TILES))
		* ceili(float(spec.extent.y) / float(GrassView.CELL_TILES))
	)


## 这个位置所在小块里已经长好的草簇数量。
func _grass_cell_at(world: Node, spec: MapSpec, world_position: Vector2) -> int:
	var tile: Vector2i = WorldGenerator.world_to_tile(world_position)
	var cell := Vector2i(
		floori(float(tile.x) / float(GrassView.CELL_TILES)),
		floori(float(tile.y) / float(GrassView.CELL_TILES))
	)
	var view: GrassView = world._grass_views.get(spec.node_id, {}).get(cell)
	return view._positions.size() if view != null else 0
