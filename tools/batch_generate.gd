extends SceneTree

## 批量生成并统计，用于验证稳定性。
## godot --headless --path . --script res://tools/batch_generate.gd -- --count 100

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var count: int = 100
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in args.size():
		if args[index] == "--count" and index + 1 < args.size():
			count = maxi(int(args[index + 1]), 1)
	var passed: int = 0
	var template_counts: Dictionary = {}
	var type_counts: Dictionary = {}
	var path_lengths: Dictionary = {}
	var score_total: float = 0.0
	var score_best: float = -INF
	var score_worst: float = INF
	var layouts: Dictionary = {}
	var rhythms: Dictionary = {}
	var template_picks: Dictionary = {}
	for index: int in count:
		var seed_value: int = 7000 + index
		var generator: WorldGenerator = WorldGenerator.new(seed_value)
		var problems: PackedStringArray = MapValidator.validate(generator)
		if problems.is_empty():
			passed += 1
		else:
			_failures += 1
			push_error("地图未通过硬校验 seed=%d %s" % [seed_value, ", ".join(problems)])
		var signature: PackedStringArray = []
		for spec: MapSpec in generator.map_specs():
			template_counts[spec.template_id] = int(template_counts.get(spec.template_id, 0)) + 1
			var kind: int = generator.run.type_of(spec.node_id)
			type_counts[RoomType.name_of(kind)] = int(type_counts.get(RoomType.name_of(kind), 0)) + 1
			signature.append("%d:%s" % [spec.origin.x, RoomType.short_name(kind)])
		layouts["|".join(signature)] = true
		rhythms[" ".join(generator.run.rhythm())] = true
		var picks: PackedStringArray = []
		for spec: MapSpec in generator.map_specs():
			picks.append(str(spec.template_id))
		template_picks["|".join(picks)] = true
		path_lengths[generator.run.main_path.size()] = int(path_lengths.get(generator.run.main_path.size(), 0)) + 1
		var value: float = MapScorer.score(generator)
		score_total += value
		score_best = maxf(score_best, value)
		score_worst = minf(score_worst, value)
	print("BATCH: count=%d passed=%d unique_layouts=%d unique_rhythms=%d unique_template_picks=%d" % [count, passed, layouts.size(), rhythms.size(), template_picks.size()])
	print("BATCH_TEMPLATES: %s" % template_counts)
	print("BATCH_TYPES: %s" % type_counts)
	print("BATCH_PATHS: %s" % path_lengths)
	print("BATCH_SCORE: avg=%.3f min=%.3f max=%.3f" % [score_total / float(count), score_worst, score_best])
	quit(0 if _failures == 0 else 1)