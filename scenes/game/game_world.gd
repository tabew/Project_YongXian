extends Node2D

## 游戏世界：建一个无限世界生成器，交给 ChunkManager 按区块加载，把主角放到出生点。

@onready var chunk_manager: ChunkManager = $ChunkManager
@onready var player: PlayerCharacter = $Player
@onready var hud: Control = $GameHUD/HUD


func _ready() -> void:
	# 直接从编辑器单独运行本场景时，也要能开局
	if GameState.world_seed == 0:
		GameState.start_new_world()
	build_world(GameState.world_seed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate_world"):
		regenerate_world()


## 用指定种子重建整个世界。
func build_world(seed_value: int) -> void:
	var generator := WorldGenerator.new(seed_value)
	GameState.world_seed = generator.world_seed

	chunk_manager.setup(generator, player)
	hud.bind_world(chunk_manager, player)

	# 出生点从原点向外找一块开阔地，避免一开局就被水围住
	var spawn_tile: Vector2i = generator.find_spawn(Vector2i.ZERO)
	player.spawn_on(generator, WorldGenerator.tile_to_world(spawn_tile))

	EventBus.world_ready.emit(generator.world_seed)


## 换个种子重开世界。
func regenerate_world() -> void:
	build_world(WorldGenerator.random_seed())
	EventBus.notification.emit("已生成新世界（种子 %d）" % GameState.world_seed)
