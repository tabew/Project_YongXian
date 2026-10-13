extends SceneTree

## 调试入口：输入 seed 生成指定地图并输出完整报告。
## godot --headless --path . --script res://tools/map_debug.gd -- --seed 12345
## 不带 --seed 时随机取种。

func _initialize() -> void:
	var seed_value: int = 0
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in args.size():
		if args[index] == "--seed" and index + 1 < args.size():
			seed_value = int(args[index + 1])
	if seed_value == 0:
		seed_value = MapRng.random_seed()
	MapDebug.verbose = true
	var generator: WorldGenerator = MapScorer.build_best(seed_value)
	print("请求种子：%d  选中地图种子：%d" % [seed_value, generator.world_seed])
	print(MapDebug.report(generator))
	quit(0)