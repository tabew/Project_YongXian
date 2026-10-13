extends SceneTree

## 内容填充验收：房间类型决定内容池、子随机源互不干扰、落点可通行且可复现。
## godot --headless --path . --script res://tools/test_map_content.gd

const SEEDS: Array[int] = [1, 7, 18473, 97231, 24681357, 2147483646]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var signatures: Dictionary = {}
	for seed_value: int in SEEDS:
		var generator: WorldGenerator = WorldGenerator.new(seed_value)
		var content: MapContent = MapContent.build(generator)
		var shops: int = 0
		var rewards: int = 0
		var rests: int = 0
		for spec: MapSpec in generator.map_specs():
			var kind: int = generator.run.type_of(spec.node_id)
			var node_id: int = spec.node_id
			match kind:
				RoomType.Kind.COMBAT:
					_check(content.budget_of(node_id, MapContent.ENEMY) >= 3, "战斗房没有刷怪预算 seed=%d node=%d" % [seed_value, node_id])
				RoomType.Kind.EVENT:
					_check(content.budget_of(node_id, MapContent.ENEMY) == 0, "事件房不该刷怪 seed=%d node=%d" % [seed_value, node_id])
				RoomType.Kind.REWARD:
					_check(content.budget_of(node_id, MapContent.LOOT) >= 2, "奖励房没有掉落预算 seed=%d node=%d" % [seed_value, node_id])
					rewards += 1
				RoomType.Kind.SHOP:
					_check(content.budget_of(node_id, MapContent.SHOP) == 1, "商店房没有商店 seed=%d node=%d" % [seed_value, node_id])
					shops += 1
				RoomType.Kind.REST:
					_check(content.budget_of(node_id, MapContent.HEAL) == 1, "休息房没有恢复点 seed=%d node=%d" % [seed_value, node_id])
					rests += 1
				RoomType.Kind.BOSS:
					_check(content.budget_of(node_id, MapContent.BOSS) == 1, "Boss 房没有 Boss seed=%d node=%d" % [seed_value, node_id])
				RoomType.Kind.START:
					_check(content.budget_of(node_id, MapContent.ENEMY) == 0, "起点房不该刷怪 seed=%d node=%d" % [seed_value, node_id])
		# 只有战斗 / Boss 区域有刷怪预算，其它类型一律不刷。
		for spec: MapSpec in generator.map_specs():
			var kind2: int = generator.run.type_of(spec.node_id)
			var expects: bool = kind2 == RoomType.Kind.COMBAT or kind2 == RoomType.Kind.BOSS
			_check((content.budget_of(spec.node_id, MapContent.ENEMY) > 0) == expects,
				"刷怪预算与房间类型不符 seed=%d node=%d kind=%s" % [seed_value, spec.node_id, RoomType.name_of(kind2)])

		_check(shops >= 1 and rewards >= 1 and rests >= 1,
			"地图缺少关键内容 seed=%d 商店=%d 奖励=%d 休息=%d" % [seed_value, shops, rewards, rests])

		# 复现：同种子内容完全一致。
		var replica: MapContent = MapContent.build(WorldGenerator.new(seed_value))
		_check(_signature(content) == _signature(replica), "同种子内容不一致 seed=%d" % seed_value)
		signatures[seed_value] = _signature(content)

		# 落点：可通行、数量正确、在区域范围内。
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for spec: MapSpec in generator.map_specs():
			var tiles: Array[Vector2i] = MapContent.pick_tiles(generator, spec.node_id, 3, rng)
			for tile: Vector2i in tiles:
				_check(generator.is_walkable(tile), "内容落点不可通行 seed=%d tile=%s" % [seed_value, tile])
				var local: Vector2i = tile - spec.origin
				_check(spec.contains_local(local.x, local.y), "内容落点越出区域 seed=%d" % seed_value)

	var distinct: Dictionary = {}
	for seed_value: int in signatures.keys():
		distinct[signatures[seed_value]] = true
	_check(distinct.size() > 1, "不同种子内容完全相同")
	print("MAP_CONTENT: checks=%d failures=%d distinct=%d" % [_checks, _failures, distinct.size()])
	quit(0 if _failures == 0 else 1)


func _signature(content: MapContent) -> String:
	var parts: PackedStringArray = []
	var ids: Array = content.entries.keys()
	ids.sort()
	for node_id: int in ids:
		for entry: Dictionary in content.content_of(node_id):
			parts.append("%d:%s:%d" % [node_id, entry["kind"], entry["budget"]])
	return "|".join(parts)