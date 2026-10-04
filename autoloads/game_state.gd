extends Node

## 单局游戏的运行时状态：地图种子与尺寸，跨场景保留。
## 注册为自动加载单例：GameState.start_new_game()

const MAP_WIDTH: int = 64
const MAP_HEIGHT: int = 64

var in_game: bool = false
var map_seed: int = 0
var map_width: int = MAP_WIDTH
var map_height: int = MAP_HEIGHT


## 开一局新游戏：本局种子在这里定下来。传 0 表示随机取种。
func start_new_game(seed_value: int = 0) -> void:
	map_seed = seed_value if seed_value != 0 else random_seed()
	map_width = MAP_WIDTH
	map_height = MAP_HEIGHT
	in_game = true


## 重掷种子，供游戏内“重新生成地图”使用。
func reroll_seed() -> int:
	map_seed = random_seed()
	return map_seed


func reset() -> void:
	in_game = false
	map_seed = 0
	map_width = MAP_WIDTH
	map_height = MAP_HEIGHT


func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 2147483646)
