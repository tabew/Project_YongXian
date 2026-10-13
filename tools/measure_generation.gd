extends SceneTree

## 生成耗时：确保地图生成只在加载时发生且开销可接受。
## godot --headless --path . --script res://tools/measure_generation.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var started: int = Time.get_ticks_usec()
	for index: int in 20:
		WorldGenerator.new(5000 + index)
	var raw_ms: float = float(Time.get_ticks_usec() - started) / 1000.0 / 20.0
	started = Time.get_ticks_usec()
	for index: int in 20:
		MapScorer.build_best(6000 + index)
	var best_ms: float = float(Time.get_ticks_usec() - started) / 1000.0 / 20.0
	print("MEASURE: raw_build_ms=%.2f best_of_n_build_ms=%.2f" % [raw_ms, best_ms])
	quit(0)