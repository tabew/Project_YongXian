class_name MapSpec
extends RefCounted

## 同一世界中的陆地箱庭：重叠庭室组成原野、谷地与山径，路口由世界布局对接。
const MIN_SIZE: int = 112
const MAX_SIZE: int = 224
const GATE_HALF_HEIGHT: int = 2
const CLIMATE_BIAS: float = 0.30
const ROAD_HALF_WIDTH: float = 2.4
const ROAD_WOBBLE: float = 8.0
const ROAD_WOBBLE_WAVES: float = 1.3
## 旧调用方的兼容常量；新生成器使用每个区域的 pass_half_width。
const NECK_HALF_WIDTH: float = 20.0
const SHAPE_NAMES: PackedStringArray = ["宽阔原野", "狭长山谷", "林间空地", "折返山径", "阶梯台地", "双庭丘陵"]

var node_id: int = 0
## size 保留为最大边长；实际范围必须使用 extent。
var size: int = MIN_SIZE
var extent: Vector2i = Vector2i(MIN_SIZE, MIN_SIZE)
## 模板最初抽样的大小；列贴合只会调整最终绘制宽度。
var template_extent: Vector2i = Vector2i(MIN_SIZE, MIN_SIZE)
var origin: Vector2i = Vector2i.ZERO
var center: Vector2 = Vector2.ZERO
var radius: float = 100.0
var axes: Vector2 = Vector2.ONE
var shape: int = 0
var height_scale: float = 0.6
var climate_bias: Vector2 = Vector2.ZERO
var phase_a: float = 0.0
var phase_b: float = 0.0
var road_phases: PackedFloat32Array = PackedFloat32Array()
var west_gate_y: int = -1
## 汇流区域可以同时接收来自主干和岔路的入口，返回时各走原路。
var west_gates: PackedInt32Array = PackedInt32Array()
var east_gates: PackedInt32Array = PackedInt32Array()
## 庭室均使用区域本地坐标；首个庭室是主庭，其余庭室是可探索的侧庭。
var chambers: Array[Rect2] = []
var chamber_corners: PackedFloat32Array = PackedFloat32Array()
var side_centers: PackedVector2Array = PackedVector2Array()
var pass_half_width: float = 20.0
var boundary_kind: int = Terrain.Kind.FOREST
## 整个世界使用的群系由布局构建方赋值；起始屋使用独立碰撞覆盖。
var biome_id: int = Biome.Kind.FOREST
var cottage: CottageLayout = null
## 生成这张区域时选中的模板 id。
var template_id: StringName = &""
## 池塘每四个浮点数记录本地 x、y、半轴 rx、ry。
var ponds: PackedFloat32Array = PackedFloat32Array()
var river_width: float = 0.0
var river_y: float = 0.0
var river_phase: float = 0.0
var river_amplitude: float = 0.0


static func create(world_seed: int, map_node_id: int, has_west_gate: bool, east_gate_count: int, room_kind: int = RoomType.Kind.COMBAT, variant: int = 0) -> MapSpec:
	var spec := MapSpec.new()
	spec.node_id = map_node_id
	var rng: RandomNumberGenerator = MapRng.node_rng(world_seed, map_node_id)
	spec.shape = posmod(world_seed + map_node_id, SHAPE_NAMES.size())
	# 按房间类型与门朝向挑选区域模板；挑模板用独立随机源，不影响主序列。
	var doors: int = (RegionTemplate.DOOR_WEST if has_west_gate else 0) | (RegionTemplate.DOOR_EAST if east_gate_count > 0 else 0)
	var pick_rng: RandomNumberGenerator = MapRng.new(world_seed).rng(MapRng.Stream.ROOM, 2 + map_node_id + variant * 97)
	var template: RegionTemplate = RegionTemplates.pick(room_kind, doors, spec.shape, pick_rng)
	spec.template_id = template.id
	# 所有尺寸都从模板的上下限派生，宽高分别抽样。
	var low: int = template.min_extent
	var high: int = template.max_extent
	var width: int = rng.randi_range(low, high)
	var height: int = rng.randi_range(low, high)
	if spec.shape == 0 or spec.shape == 3:
		width = rng.randi_range(int(lerpf(low, high, 0.65)), high)
		height = rng.randi_range(low, int(lerpf(low, high, 0.65)))
	elif spec.shape == 1:
		width = rng.randi_range(low, int(lerpf(low, high, 0.45)))
		height = rng.randi_range(int(lerpf(low, high, 0.65)), high)
	if width == height and high > low:
		height = height + 1 if height < high else height - 1
	spec.extent = Vector2i(width, height)
	spec.template_extent = spec.extent
	spec.size = maxi(width, height)
	spec.axes = Vector2(spec.extent) * 0.4
	spec.radius = minf(spec.axes.x, spec.axes.y)
	spec.height_scale = rng.randf_range(0.34, 0.94)
	spec.climate_bias = Vector2(rng.randf_range(-CLIMATE_BIAS, CLIMATE_BIAS), rng.randf_range(-CLIMATE_BIAS, CLIMATE_BIAS))
	spec.phase_a = rng.randf_range(0.0, TAU)
	spec.phase_b = rng.randf_range(0.0, TAU)
	spec.pass_half_width = rng.randf_range(16.0, 26.0)
	var boundary_kinds: PackedInt32Array = template.boundary_kinds if not template.boundary_kinds.is_empty() else PackedInt32Array([Terrain.Kind.FOREST, Terrain.Kind.TAIGA, Terrain.Kind.MOUNTAIN])
	spec.boundary_kind = boundary_kinds[rng.randi_range(0, boundary_kinds.size() - 1)]
	if room_kind == RoomType.Kind.START:
		spec._build_start_chambers()
		spec.cottage = CottageLayout.create(world_seed, map_node_id, variant, spec.chambers[0])
		spec.center = Vector2(spec.cottage.spawn_tile)
	else:
		spec._build_chambers(rng)
		# 主庭中心始终在轮廓内；不依赖矩形区域中点是否落在凹口。
		spec.center = spec.chambers[0].get_center()
	for index: int in range(1, spec.chambers.size()):
		spec.side_centers.append(spec.chambers[index].get_center())
	if has_west_gate:
		spec.west_gate_y = int(spec.center.y)
		spec.west_gates.append(spec.west_gate_y)
	for index: int in east_gate_count:
		var gate_y: float = spec.center.y if index == 0 else spec.side_centers[(index - 1) % spec.side_centers.size()].y
		spec.east_gates.append(clampi(int(gate_y), GATE_HALF_HEIGHT + 1, height - GATE_HALF_HEIGHT - 2))
	for index: int in 32:
		spec.road_phases.append(rng.randf())
	if spec.cottage == null:
		spec._build_water(rng)
	return spec


## 同一列等宽，屋内尺寸不缩放；其它箱庭的庭室和池塘一起平移伸展。
func fit_column_width(width: int) -> void:
	if extent.x == width:
		return
	var scale_x: float = float(width) / float(extent.x)
	for index: int in chambers.size():
		var room: Rect2 = chambers[index]
		room.position.x *= scale_x
		room.size.x *= scale_x
		chambers[index] = room
	for index: int in side_centers.size():
		var side: Vector2 = side_centers[index]
		side.x *= scale_x
		side_centers[index] = side
	center.x *= scale_x
	for base: int in range(0, ponds.size(), 4):
		ponds[base] *= scale_x
		ponds[base + 2] *= scale_x
	extent.x = width
	size = maxi(extent.x, extent.y)
	axes = Vector2(extent) * 0.4
	radius = minf(axes.x, axes.y)


func _build_start_chambers() -> void:
	# 大主庭与东侧上下两庭连续重叠，屋外支路不会跨过西侧屋墙。
	var dimensions := Vector2(extent)
	var rooms: Array[Rect2] = [Rect2(0.08, 0.12, 0.80, 0.76), Rect2(0.65, 0.07, 0.27, 0.38), Rect2(0.65, 0.55, 0.27, 0.38)]
	for room: Rect2 in rooms:
		chambers.append(Rect2(room.position * dimensions, room.size * dimensions))
		chamber_corners.append(8.0)


func _build_chambers(rng: RandomNumberGenerator) -> void:
	var rooms: Array[Rect2] = []
	# 归一化重叠矩形：每类保留不同的分支位置、凹口与庭室比例。
	match shape:
		0:
			rooms = [Rect2(0.10, 0.24, 0.80, 0.55), Rect2(0.18, 0.09, 0.36, 0.40), Rect2(0.60, 0.55, 0.30, 0.36)]
		1:
			rooms = [Rect2(0.28, 0.06, 0.48, 0.88), Rect2(0.08, 0.14, 0.39, 0.42), Rect2(0.56, 0.48, 0.36, 0.42)]
		2:
			rooms = [Rect2(0.18, 0.18, 0.65, 0.65), Rect2(0.07, 0.08, 0.38, 0.42), Rect2(0.58, 0.55, 0.34, 0.38)]
		3:
			rooms = [Rect2(0.25, 0.34, 0.67, 0.32), Rect2(0.08, 0.08, 0.72, 0.32), Rect2(0.08, 0.60, 0.70, 0.32)]
		4:
			rooms = [Rect2(0.24, 0.36, 0.60, 0.42), Rect2(0.10, 0.12, 0.56, 0.46), Rect2(0.40, 0.65, 0.50, 0.28)]
		5:
			rooms = [Rect2(0.30, 0.34, 0.40, 0.40), Rect2(0.08, 0.14, 0.49, 0.71), Rect2(0.43, 0.10, 0.49, 0.74)]
	var dimensions := Vector2(extent)
	for room: Rect2 in rooms:
		var room_center: Vector2 = room.get_center() + Vector2(rng.randf_range(-0.012, 0.012), rng.randf_range(-0.012, 0.012))
		var room_size: Vector2 = room.size * Vector2(rng.randf_range(0.97, 1.06), rng.randf_range(0.97, 1.06))
		var half: Vector2 = room_size * 0.5
		room_center = room_center.clamp(half + Vector2.ONE * 0.025, Vector2.ONE * 0.975 - half)
		chambers.append(Rect2((room_center - half) * dimensions, room_size * dimensions))
		chamber_corners.append(rng.randf_range(6.0, 12.0))
	# 给目标面积留余量，抽样校正避免随机比例把箱庭变成满屏矩形或细线。
	for attempt: int in 8:
		var coverage: float = _sample_coverage()
		if coverage >= 0.58 and coverage <= 0.76:
			break
		var scale_factor: float = clampf(sqrt(0.66 / maxf(coverage, 0.01)), 0.93, 1.08)
		for index: int in chambers.size():
			var room: Rect2 = chambers[index]
			var half: Vector2 = (room.size * scale_factor * 0.5).min(dimensions * 0.475)
			var room_center: Vector2 = room.get_center().clamp(half + dimensions * 0.025, dimensions * 0.975 - half)
			chambers[index] = Rect2(room_center - half, half * 2.0)


func _sample_coverage() -> float:
	var inside: int = 0
	const SAMPLE_SIDE: int = 32
	for y: int in SAMPLE_SIDE:
		for x: int in SAMPLE_SIDE:
			var point: Vector2 = Vector2((x + 0.5) / SAMPLE_SIDE, (y + 0.5) / SAMPLE_SIDE) * Vector2(extent)
			if clearance(point) > 0.0:
				inside += 1
	return float(inside) / float(SAMPLE_SIDE * SAMPLE_SIDE)


func _build_water(rng: RandomNumberGenerator) -> void:
	var pond_count: int = rng.randi_range(0, 2)
	for index: int in pond_count:
		var rx: float = rng.randf_range(4.0, 10.0)
		var ry: float = rng.randf_range(4.0, 10.0)
		for attempt: int in 20:
			var point := Vector2(rng.randf_range(16.0, extent.x - 16.0), rng.randf_range(16.0, extent.y - 16.0))
			if clearance(point) <= maxf(rx, ry) + 5.0 or point.distance_to(center) <= maxf(rx, ry) + 12.0:
				continue
			ponds.append_array(PackedFloat32Array([point.x, point.y, rx, ry]))
			break
	# 河流改为世界级水系（WorldGenerator._build_rivers），
	# 箱庭内不再保留独立河带，避免两套河流互相打架；池塘仍然保留。


## 沼泽主题至少有一处可游荡池塘，避免合法战斗箱庭完全没有鳄鱼栖地。
func ensure_swamp_water() -> void:
	if biome_id != Biome.Kind.SWAMP or cottage != null:
		return
	var best := Vector2.ZERO
	var best_clearance: float = -INF
	for y: int in range(16, extent.y - 16, 4):
		for x: int in range(16, extent.x - 16, 4):
			var point := Vector2(x + 0.5, y + 0.5)
			if point.distance_to(center) < 24.0:
				continue
			var depth: float = clearance(point)
			if depth > best_clearance:
				best = point
				best_clearance = depth
	if best_clearance > 14.0:
		ponds.append_array(PackedFloat32Array([best.x, best.y, 7.0, 7.0]))


func contains_local(local_x: int, local_y: int) -> bool:
	return local_x >= 0 and local_x < extent.x and local_y >= 0 and local_y < extent.y


func shape_name() -> String:
	return "起始小屋" if cottage != null else SHAPE_NAMES[shape]


## 圆角矩形的 signed clearance 联合：内部正值、边界零、外部负值。
func clearance(point: Vector2) -> float:
	var result: float = -INF
	for index: int in chambers.size():
		var room: Rect2 = chambers[index]
		var corner: float = minf(chamber_corners[index], minf(room.size.x, room.size.y) * 0.5)
		var q: Vector2 = (point - room.get_center()).abs() - room.size * 0.5 + Vector2.ONE * corner
		var signed_distance: float = q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0) - corner
		result = maxf(result, -signed_distance)
	return result


## 旧 API 的等价内外判定：offset.length() < edge_at(offset) 当且仅当 clearance > 0。
## 不再构造极坐标轮廓，新调用方直接使用 clearance。
func edge_at(offset: Vector2) -> float:
	return offset.length() + clearance(center + offset)


## 水面内正值、边缘零、外负值。生成器另以 clearance > 5 限制水面。
func water_depth(point: Vector2) -> float:
	var depth: float = -Vector2(extent).length()
	for base: int in range(0, ponds.size(), 4):
		var delta: Vector2 = point - Vector2(ponds[base], ponds[base + 1])
		var pond_axes := Vector2(ponds[base + 2], ponds[base + 3])
		var ellipse_depth: float = (1.0 - (delta / pond_axes).length()) * minf(pond_axes.x, pond_axes.y)
		depth = maxf(depth, ellipse_depth)
	if river_width > 0.0:
		var water_y: float = river_y + sin(point.x / float(extent.x) * TAU + river_phase) * river_amplitude
		depth = maxf(depth, river_width - absf(point.y - water_y))
	return depth


## 连接所有门、主庭与侧庭；侧庭互连和主庭支路组成可返回的回路。
func build_roads() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	if cottage != null:
		var porch := Vector2(cottage.porch_tile) + Vector2.ONE * 0.5
		_append(data, Vector2(cottage.spawn_tile) + Vector2.ONE * 0.5, porch, -1.0)
		for gate_y: int in west_gates:
			# START 通常无西门；兼容调用通过屋外北侧折线绕到平台。
			var detour_y: float = float(cottage.bounds.position.y - 5) + 0.5
			var west := Vector2(0.5, float(gate_y) + 0.5)
			var north_west := Vector2(west.x, detour_y)
			var north_east := Vector2(porch.x, detour_y)
			_append(data, west, north_west, -1.0)
			_append(data, north_west, north_east, -1.0)
			_append(data, north_east, porch, -1.0)
		for gate_y: int in east_gates:
			_append(data, porch, Vector2(float(extent.x) - 0.5, float(gate_y) + 0.5), -1.0)
		for side_center: Vector2 in side_centers:
			_append(data, porch, side_center, -1.0)
		for side_index: int in range(1, side_centers.size()):
			_append(data, side_centers[side_index - 1], side_centers[side_index], -1.0)
		return data
	var index: int = 0
	# 主干：西门 → 穿过主庭 → 东门，中间两处折点让主路蜿蜒而不是一条直线。
	var west_y: float = float(west_gates[0]) + 0.5 if not west_gates.is_empty() else center.y
	var east_y: float = float(east_gates[0]) + 0.5 if not east_gates.is_empty() else center.y
	var bend: float = (float(shape) - 2.5) * 3.6
	var trunk: Array[Vector2] = [
		Vector2(0.5, west_y),
		Vector2(
			float(extent.x) * 0.28,
			clampf(lerpf(west_y, center.y, 0.72) + bend, 6.0, float(extent.y) - 6.0)
		),
		center,
		Vector2(
			float(extent.x) * 0.72,
			clampf(lerpf(center.y, east_y, 0.72) - bend * 0.8, 6.0, float(extent.y) - 6.0)
		),
		Vector2(float(extent.x) - 0.5, east_y),
	]
	for point_index: int in range(1, trunk.size()):
		_append(data, trunk[point_index - 1], trunk[point_index], _road_phase(index))
		index += 1
	# 额外的门接在主干两端，形成岔口而不是从主庭放射。
	for gate_index: int in range(1, west_gates.size()):
		_append(data, Vector2(0.5, float(west_gates[gate_index]) + 0.5), trunk[1], _road_phase(index))
		index += 1
	for gate_index: int in range(1, east_gates.size()):
		_append(data, trunk[3], Vector2(float(extent.x) - 0.5, float(east_gates[gate_index]) + 0.5), _road_phase(index))
		index += 1
	# 侧庭从主干最近点引支路，侧庭之间再互相连通，形成可返回的环路。
	for side_center: Vector2 in side_centers:
		_append(data, _nearest_trunk_point(trunk, side_center), side_center, _road_phase(index))
		index += 1
	for side_index: int in range(1, side_centers.size()):
		_append(data, side_centers[side_index - 1], side_centers[side_index], _road_phase(index))
		index += 1
	return data


## 主干折线上离目标最近的点。
func _nearest_trunk_point(trunk: Array[Vector2], target: Vector2) -> Vector2:
	var best: Vector2 = trunk[0]
	var best_distance: float = INF
	for index: int in range(1, trunk.size()):
		var a: Vector2 = trunk[index - 1]
		var b: Vector2 = trunk[index]
		for step: int in 9:
			var point: Vector2 = a.lerp(b, float(step) / 8.0)
			var distance: float = point.distance_squared_to(target)
			if distance < best_distance:
				best_distance = distance
				best = point
	return best


func _road_phase(index: int) -> float:
	return road_phases[posmod(index, road_phases.size())] if not road_phases.is_empty() else 0.0


## 路段写入。短路段不套正弦摆动：8 格振幅压在十来格的短段上会让曲线过陡，
## 逐格判定与实际曲线偏离，路面出现断口。
func _append(data: PackedFloat32Array, a: Vector2, b: Vector2, phase: float) -> void:
	if a.distance_to(b) < 26.0:
		phase = -1.0
	data.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, phase]))


static func node_seed(world_seed: int, map_node_id: int) -> int:
	return MapRng.node_seed(world_seed, map_node_id)


static func road_offset(t: float, phase: float) -> float:
	if phase < 0.0:
		return 0.0
	return ROAD_WOBBLE * sin((t * ROAD_WOBBLE_WAVES + phase) * TAU) * sin(t * PI)


static func segment_distance(point: Vector2, a: Vector2, b: Vector2, phase: float = -1.0) -> float:
	var delta: Vector2 = b - a
	var length_sq: float = delta.length_squared()
	if length_sq < 0.0001:
		return point.distance_to(a)
	var projection: float = (point - a).dot(delta) / length_sq
	if projection < 0.0:
		return point.distance_to(a)
	if projection > 1.0:
		return point.distance_to(b)
	var signed_distance: float = ((point.x - a.x) * delta.y - (point.y - a.y) * delta.x) / sqrt(length_sq)
	return absf(signed_distance - (road_offset(projection, phase) if phase >= 0.0 else 0.0))
