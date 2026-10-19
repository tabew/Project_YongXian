extends SceneTree

class CountedSwamp extends WorldGenerator:
	var walk_queries: int = 0
	func is_walkable(_tile: Vector2i) -> bool:
		walk_queries += 1
		return true
	func sample_biome(_tile: Vector2i) -> int:
		return Biome.Kind.SWAMP

var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _run() -> void:
	var source := CountedSwamp.new(18473)
	var definition := ShiSpawnData.new()
	definition.allowed_biomes = [Biome.Kind.SWAMP]
	var rng: RandomNumberGenerator = MapRng.enemy_chunk_rng(18473, Vector2i.ZERO, &"shi:test")
	var initial_queries: int = source.walk_queries
	for attempt: int in 100:
		definition.select_spawn_tile(source, Vector2i.ZERO, rng, 0)
	check(source.walk_queries == initial_queries + 1, "anchor_search_once_for_all_slots_and_attempts")
	var original_queries: int = source.walk_queries
	var non_swamp := MapSpec.new()
	non_swamp.biome_id = Biome.Kind.FOREST
	check(definition.select_spawn_tile(source, Vector2i.ZERO, rng, 0, non_swamp) == EnemyPathfinder.INVALID_TILE, "wrong_biome_fast_rejection")
	check(source.walk_queries == original_queries, "wrong_biome_does_not_run_terrain_search")
	var holder := Node2D.new()
	root.add_child(holder)
	var owner := Node2D.new()
	holder.add_child(owner)
	for point: Vector2 in [Vector2(4, 0), Vector2(1000, 1000)]:
		var node := Node2D.new()
		holder.add_child(node)
		node.global_position = point
		node.add_to_group("swamp_perf_targets")
	ShiProximityCache.invalidate()
	var before: int = ShiProximityCache.rebuilds
	for call_index: int in 100:
		check(ShiProximityCache.nearby(owner, &"swamp_perf_targets", 10).size() == 1, "proximity_index_excludes_distant_items")
	check(ShiProximityCache.rebuilds - before == 1, "whole_scene_scan_once_per_frame")
	# 地图/群系快速索引查询应与完整地形判定完全一致，包括边界外。
	var actual := WorldGenerator.new(18473)
	for spec: MapSpec in actual.map_specs():
		for tile: Vector2i in [spec.origin, spec.origin + spec.extent / 2, spec.origin + spec.extent - Vector2i.ONE]:
			actual._classify(tile.x, tile.y)
			var biome: int = actual._last_biome
			var terrain: int = actual._last_terrain
			var route: int = actual._last_route
			var map_ref: MapSpec = actual._last_map
			check(actual.sample_biome(tile) == biome and actual.sample_map(tile) == map_ref, "fast_identity_matches_full_classification")
			check(actual.sample_terrain(tile) == terrain and actual.sample_route(tile) == route, "cached_terrain_route_match_full_classification")
			check(actual.is_walkable(tile) == (Terrain.is_walkable(terrain) or route != Route.Kind.NONE), "cached_walkability_matches_full_classification")
	var outside := Vector2i(-100000, -100000)
	check(actual.sample_biome(outside) == Biome.Kind.MOUNTAIN and actual.sample_map(outside) == null, "outside_identity_preserved")
	# 切图销毁的排队目标不能在强类型转换时抛错。
	var stale := BaseMonster.new()
	stale.free()
	root.get_node("PathRequestScheduler")._deliver({"host": stale, "callback": Callable()})
	check(true, "freed_path_job_ignored_before_cast")
	holder.queue_free()
	await process_frame
	print("SWAMP_PERF_TEST: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
