class_name RunMapGenerator
extends RefCounted

## 局内地图生成：层 → 区域 → 房间。
## 结构为"链式主干 + 跳边"，跳边同时提供 2~3 个出口与少量环路。
## 纯逻辑，不依赖场景树，可用种子复现，可单元测试。

## 每个区域占用的 node_id 空间，保证全层唯一。
const NODE_STRIDE: int = 100
## Boss 房 / 秘密房在区域空间里的偏移。
const BOSS_OFFSET: int = 90
const SECRET_OFFSET: int = 50

## 房间类型 → 热量预算（最小值 / 最大值）。
const HEAT_BUDGETS: Dictionary = {
	RoomKind.Kind.COMBAT: Vector2(20.0, 40.0),
	RoomKind.Kind.ELITE: Vector2(45.0, 70.0),
	RoomKind.Kind.BOSS: Vector2(80.0, 100.0),
	RoomKind.Kind.CHALLENGE: Vector2(50.0, 80.0),
	RoomKind.Kind.EVENT: Vector2(0.0, 10.0),
	RoomKind.Kind.SHOP: Vector2(0.0, 10.0),
	RoomKind.Kind.TREASURE: Vector2(0.0, 10.0),
	RoomKind.Kind.ALCHEMY: Vector2(0.0, 0.0),
	RoomKind.Kind.REST: Vector2(0.0, 0.0),
	RoomKind.Kind.SECRET: Vector2(0.0, 10.0),
}

## 房间类型 → 敌人数量范围（x 为最小，y 为最大）。
const ENEMY_COUNTS: Dictionary = {
	RoomKind.Kind.COMBAT: Vector2i(3, 6),
	RoomKind.Kind.ELITE: Vector2i(1, 2),
	RoomKind.Kind.BOSS: Vector2i(1, 1),
	RoomKind.Kind.CHALLENGE: Vector2i(4, 8),
}


## 生成一层楼。同一 (seed, floor_index, config) 永远得到同一结果。
static func generate(seed_value: int, floor_index: int = 0, config: RunMapConfig = null) -> FloorData:
	var cfg: RunMapConfig = config if config != null else RunMapConfig.prototype()
	var floor := FloorData.new()
	floor.floor_index = floor_index

	var layout_rng := _rng(seed_value, floor_index, 11)
	var kind_rng := _rng(seed_value, floor_index, 23)
	var content_rng := _rng(seed_value, floor_index, 37)
	var secret_rng := _rng(seed_value, floor_index, 53)

	var region_count: int = layout_rng.randi_range(cfg.min_regions, cfg.max_regions)
	var themes: Array[StringName] = _resolve_themes(cfg, region_count, layout_rng)

	_build_regions(floor, themes, cfg, layout_rng)
	_build_boss(floor)
	_assign_kinds(floor, kind_rng, cfg)
	_build_secret_room(floor, cfg, secret_rng)
	_compute_depths(floor)
	_fill_content(floor, cfg, content_rng)
	_build_doors(floor)
	return floor


## 调试用：一层的紧凑文字描述。
static func describe(floor: FloorData) -> String:
	var lines := PackedStringArray()
	lines.append("第 %d 层：%d 区域 / %d 房间" % [floor.floor_index + 1, floor.regions.size(), floor.room_count()])
	for region: RegionData in floor.regions:
		var names := PackedStringArray()
		for room: RoomData in region.rooms:
			names.append("%d:%s" % [room.node_id, room.kind_name()])
		lines.append("  区域 %d %s（%d 房，%d 环）：%s" % [
			region.index, region.theme_name(), region.room_count(), region.loop_count(), " ".join(names),
		])
	if floor.boss_room != null:
		lines.append("  Boss：%s（%s）" % [floor.boss_room.theme_name(), floor.boss_room.kind_name()])
	return "\n".join(lines)


# ------------------------------------------------------------ 区域与房间

static func _build_regions(floor: FloorData, themes: Array[StringName], cfg: RunMapConfig, rng: RandomNumberGenerator) -> void:
	for region_index: int in themes.size():
		var region := RegionData.new()
		region.index = region_index
		region.theme_id = themes[region_index]
		region.material_pool = RegionThemeCatalog.material_ids_of(region.theme_id)

		var room_total: int = rng.randi_range(cfg.min_rooms, cfg.max_rooms)
		for local_index: int in room_total:
			var room := RoomData.new()
			room.node_id = region_index * NODE_STRIDE + local_index
			room.region_index = region_index
			room.theme_id = region.theme_id
			room.shape = _pick_shape(rng)
			region.rooms.append(room)
			floor.rooms.append(room)

		# 主干链：相邻房间互通。
		for local_index: int in room_total - 1:
			region.link_rooms(region.rooms[local_index].node_id, region.rooms[local_index + 1].node_id)
		# 跳边：跳过一间房，形成环路与第二个出口。
		for local_index: int in room_total - 2:
			if rng.randf() < cfg.loop_chance:
				region.link_rooms(region.rooms[local_index].node_id, region.rooms[local_index + 2].node_id)
		# 偶尔跳两间，制造第三个出口。
		for local_index: int in room_total - 3:
			if rng.randf() < cfg.loop_chance * 0.35:
				region.link_rooms(region.rooms[local_index].node_id, region.rooms[local_index + 3].node_id)

		for from_node: int in region.links:
			for to_node: int in region.links[from_node]:
				floor.link_rooms(from_node, to_node)
		floor.regions.append(region)

	# 跨区域：上一区域的末端接到下一区域起点。
	for region_index: int in floor.regions.size() - 1:
		var current: RegionData = floor.regions[region_index]
		var next: RegionData = floor.regions[region_index + 1]
		for terminal: RoomData in _terminal_rooms(current):
			floor.link_rooms(terminal.node_id, next.rooms[0].node_id)


static func _terminal_rooms(region: RegionData) -> Array[RoomData]:
	var result: Array[RoomData] = []
	for room: RoomData in region.rooms:
		var has_forward: bool = false
		for neighbour: int in region.neighbours(room.node_id):
			if neighbour > room.node_id:
				has_forward = true
				break
		if not has_forward:
			result.append(room)
	return result


static func _build_boss(floor: FloorData) -> void:
	var last_region: RegionData = floor.regions[floor.regions.size() - 1]
	var boss := RoomData.new()
	boss.node_id = floor.regions.size() * NODE_STRIDE + BOSS_OFFSET
	boss.region_index = last_region.index
	boss.theme_id = last_region.theme_id
	boss.kind = RoomKind.Kind.BOSS
	boss.shape = RoomShape.Shape.OPEN
	floor.boss_room = boss
	floor.rooms.append(boss)
	for terminal: RoomData in _terminal_rooms(last_region):
		floor.link_rooms(terminal.node_id, boss.node_id)


# ------------------------------------------------------------ 房间类型

static func _assign_kinds(floor: FloorData, rng: RandomNumberGenerator, cfg: RunMapConfig) -> void:
	var progression: Array[RoomData] = []
	for region: RegionData in floor.regions:
		for room: RoomData in region.rooms:
			progression.append(room)
	if progression.is_empty():
		return

	for room: RoomData in progression:
		room.kind = RoomKind.Kind.COMBAT
	progression[0].kind = RoomKind.Kind.COMBAT

	for index: int in range(1, progression.size()):
		var roll: float = rng.randf()
		if roll < 0.40:
			progression[index].kind = _random_lure_or_cooldown(rng)
		elif roll < 0.62:
			progression[index].kind = RoomKind.Kind.ELITE

	_ensure_region_combat(floor)
	var reserved: Dictionary = _apply_guarantees(progression, rng)
	# 保底会重新引入战斗房，所以热量曲线放在最后校正。
	_enforce_heat_curve(progression, cfg, reserved)


## 每个区域至少保留 2 个战斗房，避免整区全是取材/冷却房。
static func _ensure_region_combat(floor: FloorData) -> void:
	for region: RegionData in floor.regions:
		var combat_count: int = 0
		for room: RoomData in region.rooms:
			if RoomKind.is_combat(room.kind):
				combat_count += 1
		var index: int = 1
		while combat_count < 2 and index < region.rooms.size():
			var room: RoomData = region.rooms[index]
			if not RoomKind.is_combat(room.kind):
				room.kind = RoomKind.Kind.COMBAT
				combat_count += 1
			index += 1


## 热量曲线：连续战斗房超过上限时，把段内第一个非保底战斗房改成冷却房。
## 保底房（reserved）优先保留，只有在段内全是保底房时才退而改当前房。
static func _enforce_heat_curve(progression: Array[RoomData], cfg: RunMapConfig, reserved: Dictionary) -> void:
	var guard: int = 0
	while guard < 256:
		guard += 1
		var run_start: int = _first_long_run(progression, cfg)
		if run_start < 0:
			return
		var converted: bool = false
		for scan: int in range(run_start, progression.size()):
			if not RoomKind.is_combat(progression[scan].kind):
				break
			if reserved.has(scan):
				continue
			progression[scan].kind = _cooldown_kind(progression[scan].node_id)
			converted = true
			break
		if not converted:
			return


## 找第一段超长战斗房，返回段起点；没有则返回 -1。
static func _first_long_run(progression: Array[RoomData], cfg: RunMapConfig) -> int:
	var index: int = 0
	while index < progression.size():
		if not RoomKind.is_combat(progression[index].kind):
			index += 1
			continue
		var run_start: int = index
		var run_end: int = index
		while run_end + 1 < progression.size() and RoomKind.is_combat(progression[run_end + 1].kind):
			run_end += 1
		if run_end - run_start + 1 > cfg.combat_run_limit:
			return run_start
		index = run_end + 1
	return -1


## 每层保底：续组合 / 换组合 / 取材 / 冷却 各一个，分散在全层。
## 返回被保底占用的下标集合，供热量曲线避让。
static func _apply_guarantees(progression: Array[RoomData], rng: RandomNumberGenerator) -> Dictionary:
	var decisions: Array[int] = [
		RoomKind.Decision.SUSTAIN,
		RoomKind.Decision.SWITCH,
		RoomKind.Decision.LURE,
		RoomKind.Decision.COOL,
	]
	var used: Dictionary = {}
	for index: int in decisions.size():
		var slot: int = int(round(float(index + 1) * float(progression.size()) / float(decisions.size() + 1)))
		slot = clampi(slot, 1, progression.size() - 1)
		while used.has(slot):
			slot += 1
			if slot >= progression.size():
				slot = 1
		used[slot] = true
		progression[slot].kind = _kind_for_decision(decisions[index], rng)
	return used


static func _kind_for_decision(decision: int, rng: RandomNumberGenerator) -> int:
	match decision:
		RoomKind.Decision.SUSTAIN:
			return RoomKind.Kind.COMBAT
		RoomKind.Decision.SWITCH:
			return RoomKind.Kind.ELITE
		RoomKind.Decision.LURE:
			return [RoomKind.Kind.EVENT, RoomKind.Kind.SHOP, RoomKind.Kind.TREASURE][rng.randi_range(0, 2)]
		RoomKind.Decision.COOL:
			return [RoomKind.Kind.REST, RoomKind.Kind.ALCHEMY][rng.randi_range(0, 1)]
	return RoomKind.Kind.COMBAT


static func _random_lure_or_cooldown(rng: RandomNumberGenerator) -> int:
	var pool: Array[int] = [
		RoomKind.Kind.EVENT, RoomKind.Kind.SHOP, RoomKind.Kind.TREASURE,
		RoomKind.Kind.REST, RoomKind.Kind.ALCHEMY, RoomKind.Kind.CHALLENGE,
	]
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _cooldown_kind(node_id: int) -> int:
	return RoomKind.Kind.REST if node_id % 2 == 0 else RoomKind.Kind.ALCHEMY


# ------------------------------------------------------------ 秘密房

static func _build_secret_room(floor: FloorData, cfg: RunMapConfig, rng: RandomNumberGenerator) -> void:
	if cfg.secret_rooms <= 0:
		return
	var candidates: Array[RoomData] = []
	for region: RegionData in floor.regions:
		for room: RoomData in region.rooms:
			if room.kind != RoomKind.Kind.BOSS:
				candidates.append(room)
	if candidates.is_empty():
		return

	var secret_count: int = mini(cfg.secret_rooms, candidates.size())
	var used_hosts: Dictionary = {}
	for index: int in secret_count:
		var host: RoomData = null
		var attempts: int = 0
		while attempts < 32:
			attempts += 1
			var candidate: RoomData = candidates[rng.randi_range(0, candidates.size() - 1)]
			if not used_hosts.has(candidate.node_id) and candidate.kind != RoomKind.Kind.SECRET:
				host = candidate
				break
		if host == null:
			return
		used_hosts[host.node_id] = true

		var secret := RoomData.new()
		secret.node_id = host.region_index * NODE_STRIDE + SECRET_OFFSET + index
		secret.region_index = host.region_index
		secret.theme_id = host.theme_id
		secret.kind = RoomKind.Kind.SECRET
		secret.shape = RoomShape.Shape.NARROW
		floor.rooms.append(secret)
		floor.link_rooms(host.node_id, secret.node_id)

		var door_kind: int = rng.randi_range(0, SecretDoor.COUNT - 1)
		host.secret_door = {
			"target": secret.node_id,
			"kind": door_kind,
			"name": SecretDoor.name_of(door_kind),
			"trait": String(SecretDoor.trait_of(door_kind)),
			"level": SecretDoor.level_of(door_kind),
		}


# ------------------------------------------------------------ 深度与内容

static func _compute_depths(floor: FloorData) -> void:
	var start: RoomData = floor.start_room()
	if start == null:
		return
	for room: RoomData in floor.rooms:
		room.depth = -1
	start.depth = 0
	var queue: Array[int] = [start.node_id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		var current_room: RoomData = floor.room_of(current)
		for next_node: int in floor.neighbours(current):
			var next_room: RoomData = floor.room_of(next_node)
			if next_room != null and next_room.depth < 0:
				next_room.depth = current_room.depth + 1
				queue.append(next_node)
	for room: RoomData in floor.rooms:
		if room.depth < 0:
			room.depth = 0


static func _fill_content(floor: FloorData, cfg: RunMapConfig, rng: RandomNumberGenerator) -> void:
	for region: RegionData in floor.regions:
		var theme: RegionTheme = RegionThemeCatalog.create(region.theme_id)
		for room: RoomData in region.rooms:
			_fill_room(room, theme, region, cfg, rng)
	if floor.boss_room != null:
		var boss_theme: RegionTheme = RegionThemeCatalog.create(floor.boss_room.theme_id)
		_fill_room(floor.boss_room, boss_theme, floor.regions[floor.regions.size() - 1], cfg, rng)
	# 秘密房内容单独给：主题材料 + 图鉴相关奖励。
	for room: RoomData in floor.rooms:
		if room.kind == RoomKind.Kind.SECRET and room.enemy_spawns.is_empty():
			room.scene_elements = [&"mirror", &"rift"]
			room.material_drops = [{"material_id": 1026, "amount": 1}]


static func _fill_room(room: RoomData, theme: RegionTheme, region: RegionData, cfg: RunMapConfig, rng: RandomNumberGenerator) -> void:
	room.heat_budget = HEAT_BUDGETS.get(room.kind, Vector2.ZERO)

	var element_pool: Array[StringName] = theme.scene_elements.duplicate()
	for favored: StringName in RoomShape.favored_traits(room.shape):
		if element_pool.size() >= 4:
			break
		element_pool.append(favored)
	var element_count: int = 0 if not RoomKind.is_combat(room.kind) else rng.randi_range(2, mini(4, element_pool.size()))
	for index: int in element_count:
		room.scene_elements.append(element_pool[index])

	var breakable_pool: Array = BreakableCatalog.candidates_for(region.theme_id)
	var breakable_count: int = rng.randi_range(1, mini(3, breakable_pool.size())) if RoomKind.is_combat(room.kind) else rng.randi_range(0, mini(2, breakable_pool.size()))
	for index: int in breakable_count:
		room.breakables.append(StringName(breakable_pool[index]))

	if region.material_pool.is_empty():
		return
	var drop_count: int = rng.randi_range(1, mini(2, region.material_pool.size()))
	for index: int in drop_count:
		var material_id: int = region.material_pool[rng.randi_range(0, region.material_pool.size() - 1)]
		room.material_drops.append({"material_id": material_id, "amount": rng.randi_range(1, 2)})

	if not RoomKind.is_combat(room.kind):
		return
	var counts: Vector2i = ENEMY_COUNTS.get(room.kind, Vector2i(3, 6))
	var spawn_count: int = rng.randi_range(counts.x, counts.y)
	for index: int in spawn_count:
		room.enemy_spawns.append({
			"theme": String(room.theme_id),
			"tier": _tier_of(room.kind),
			"seed": rng.randi(),
		})


static func _tier_of(kind: int) -> String:
	match kind:
		RoomKind.Kind.ELITE:
			return "elite"
		RoomKind.Kind.BOSS:
			return "boss"
		RoomKind.Kind.CHALLENGE:
			return "challenge"
	return "normal"


# ------------------------------------------------------------ 门

## 世界层沿区域顺序单向推进：一个房间只要缺一条向前的门，后半层就会从起点断开。
## 同深度时按 node_id 判定，保证顺序唯一且可复现。
static func _is_forward(from_room: RoomData, to_room: RoomData) -> bool:
	if to_room.depth != from_room.depth:
		return to_room.depth > from_room.depth
	return to_room.node_id > from_room.node_id


static func _build_doors(floor: FloorData) -> void:
	for room: RoomData in floor.rooms:
		room.doors.clear()
	var hidden: Dictionary = {}
	for room: RoomData in floor.rooms:
		if room.has_secret_door():
			hidden[int(room.secret_door["target"])] = true
	for room: RoomData in floor.rooms:
		if room.kind == RoomKind.Kind.SECRET or room.kind == RoomKind.Kind.BOSS:
			continue
		var candidates: Array[RoomData] = []
		for target: int in floor.neighbours(room.node_id):
			if hidden.has(target):
				continue
			var target_room: RoomData = floor.room_of(target)
			if target_room != null:
				candidates.append(target_room)
		# 向前的门排在前面，回程门只在还有名额时才补，避免截断前进路线。
		var ordered: Array[RoomData] = []
		for target_room: RoomData in candidates:
			if _is_forward(room, target_room):
				ordered.append(target_room)
		for target_room: RoomData in candidates:
			if not _is_forward(room, target_room):
				ordered.append(target_room)
		# 带隐藏门的宿主留一格给秘密房：世界层的出口上限仍是 3。
		var limit: int = 2 if room.has_secret_door() else 3
		for index: int in mini(limit, ordered.size()):
			_add_door(room, ordered[index])


static func _add_door(room: RoomData, target_room: RoomData) -> void:
	var theme: RegionTheme = RegionThemeCatalog.create(target_room.theme_id)
	room.add_door(DoorInfo.create(
		room.node_id,
		target_room.node_id,
		target_room.kind,
		target_room.theme_id,
		theme.material_preview(2),
		theme.resistance.duplicate(),
		theme.weakness.duplicate(),
	))


# ------------------------------------------------------------ 工具

static func _resolve_themes(cfg: RunMapConfig, region_count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var result: Array[StringName] = []
	for theme_id: StringName in cfg.theme_ids:
		if result.size() >= region_count:
			break
		if not result.has(theme_id):
			result.append(theme_id)
	var pool: Array[StringName] = RegionThemeCatalog.ids()
	var start_index: int = rng.randi_range(0, maxi(pool.size() - 1, 0))
	var cursor: int = 0
	while result.size() < region_count and cursor < pool.size():
		var candidate: StringName = pool[(start_index + cursor) % pool.size()]
		cursor += 1
		if not result.has(candidate):
			result.append(candidate)
	return result


static func _pick_shape(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, RoomShape.COUNT - 1)


static func _rng(seed_value: int, floor_index: int, salt: int) -> RandomNumberGenerator:
	return MapRng.new(seed_value).rng(MapRng.Stream.ROOM, floor_index * 131 + salt)
