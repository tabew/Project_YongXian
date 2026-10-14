extends SceneTree

## 临时调试：加载生成器并打印一层结构。

func _initialize() -> void:
	var script: GDScript = load("res://resources/run/run_map_generator.gd")
	print("script=", script)
	if script == null:
		quit(1)
		return
	print("has generate=", script.has_method("generate"))
	var config: RunMapConfig = RunMapConfig.prototype()
	var floor: FloorData = script.generate(20261014, 0, config)
	print(RunMapGenerator.describe(floor))
	quit(0)
