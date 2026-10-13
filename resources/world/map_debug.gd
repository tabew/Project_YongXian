class_name MapDebug
extends RefCounted

## 调试与可视化：输出地图结构、房间图、类型/模板/连接、校验结果与评分明细。

## 调试开关；关闭时 report() 仍可直接调用。
static var verbose: bool = false


## 完整报告文本。
static func report(generator: WorldGenerator, config: MapConfig = null) -> String:
	if generator == null or generator.run == null:
		return "(空地图)"
	var lines: PackedStringArray = []
	lines.append("=========== 地图报告 ===========")
	lines.append("种子：%d  区域数：%d" % [generator.world_seed, generator.map_specs().size()])
	lines.append("")
	lines.append("--- 房间图 ---")
	lines.append(generator.run.describe_rooms())
	lines.append("")
	lines.append("--- ASCII 布局（P起点 C战斗 R奖励 $商店 H休息 E事件 B Boss）---")
	lines.append(ascii(generator))
	lines.append("")
	lines.append("--- 区域明细（类型 / 模板 / 门）---")
	for spec: MapSpec in generator.map_specs():
		lines.append("  %s  区域 %d  模板 %s  出口 %s  入口 %s" % [
			RoomType.name_of(generator.run.type_of(spec.node_id)),
			spec.node_id, spec.template_id,
			spec.east_gates, spec.west_gates,
		])
	lines.append("")
	lines.append("--- 硬约束校验 ---")
	var problems: PackedStringArray = MapValidator.validate(generator)
	if problems.is_empty():
		lines.append("  通过")
	else:
		for problem: String in problems:
			lines.append("  失败：%s" % problem)
	lines.append("")
	lines.append("--- 软评分明细 ---")
	var parts: Dictionary = MapScorer.breakdown(generator, config)
	for key: String in parts.keys():
		lines.append("  %-16s %.4f" % [key, float(parts[key])])
	lines.append("  总分             %.4f" % MapScorer.score(generator, config))
	lines.append("")
	lines.append("--- 内容填充 ---")
	lines.append(MapContent.build(generator).describe())
	return "\n".join(lines)


## 世界网格的 ASCII 概览。
static func ascii(generator: WorldGenerator, columns: int = 76) -> String:
	var specs: Array[MapSpec] = generator.map_specs()
	if specs.is_empty():
		return "(无区域)"
	var min_x: int = 2147483647
	var min_y: int = 2147483647
	var max_x: int = -2147483648
	var max_y: int = -2147483648
	for spec: MapSpec in specs:
		min_x = mini(min_x, spec.origin.x)
		min_y = mini(min_y, spec.origin.y)
		max_x = maxi(max_x, spec.origin.x + spec.extent.x)
		max_y = maxi(max_y, spec.origin.y + spec.extent.y)
	var span_x: int = maxi(max_x - min_x, 1)
	var span_y: int = maxi(max_y - min_y, 1)
	var cols: int = maxi(columns, 8)
	var rows: int = maxi(int(round(float(span_y) / float(span_x) * float(cols) * 0.5)), 4)
	var grid: Array = []
	for _row: int in rows:
		var line: Array = []
		for _col: int in cols:
			line.append(" ")
		grid.append(line)
	for spec: MapSpec in specs:
		var label: String = RoomType.short_name(generator.run.type_of(spec.node_id))
		var c0: int = clampi(int(floor(float(spec.origin.x - min_x) / float(span_x) * float(cols))), 0, cols - 1)
		var c1: int = clampi(int(ceil(float(spec.origin.x + spec.extent.x - min_x) / float(span_x) * float(cols))), c0 + 1, cols)
		var r0: int = clampi(int(floor(float(spec.origin.y - min_y) / float(span_y) * float(rows))), 0, rows - 1)
		var r1: int = clampi(int(ceil(float(spec.origin.y + spec.extent.y - min_y) / float(span_y) * float(rows))), r0 + 1, rows)
		for row: int in range(r0, r1):
			for col: int in range(c0, c1):
				grid[row][col] = label
	var lines: PackedStringArray = []
	for row: int in rows:
		lines.append("|" + "".join(grid[row]) + "|")
	return "\n".join(lines)