extends Node

## 单局游戏的运行时状态：世界种子，跨场景保留。
## 注册为自动加载单例：GameState.start_new_world()

var in_game: bool = false
var world_seed: int = 0


## 开一局新游戏：本局种子在这里定下来。传 0 表示随机取种。
func start_new_world(seed_value: int = 0) -> void:
	world_seed = seed_value if seed_value != 0 else WorldGenerator.random_seed()
	in_game = true


func reset() -> void:
	in_game = false
	world_seed = 0
