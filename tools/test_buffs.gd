extends SceneTree

## buff 基类验收：施加 / 升级与降级 / 属性改写与还原 / 定时治疗 / 定时伤害(减益) /
## 非玩家宿主 / 没有容器的目标。
##
## 运行：godot --headless --path . --script res://tools/test_buffs.gd
##
## 宿主用正式游戏场景里的玩家与训练靶，所以顺带覆盖了
## "BuffHolder 需要宿主提供 read_stat/apply_stat" 这条约定在各实体上的接线。

const SWIFT_PATH: String = "res://resources/buffs/swift.tres"
const REGEN_PATH: String = "res://resources/buffs/regen.tres"
const DEFENSE_UP_PATH: String = "res://resources/buffs/defense_up.tres"
const GAME_SCENE: String = "res://scenes/game/game_world.tscn"
const DUMMY_SCENE: String = "res://scenes/combat/training_dummy.tscn"
## 一帧的时长，用来把"等几帧"换算成秒
const STEP: float = 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## 造一个只用于测试的减益：持续掉血
func _make_dot(id: StringName, duration: float, tick: float, per_tick: float) -> BuffData:
	var data: BuffData = BuffData.new()
	data.id = id
	data.display_name = "测试毒"
	data.description = "临时 DoT"
	data.is_debuff = true
	data.duration = duration
	data.tick_interval = tick
	data.damage_per_tick = per_tick
	return data


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node2D = (load(GAME_SCENE) as PackedScene).instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	var player: PlayerCharacter = game.get_node("Player") as PlayerCharacter
	player.set_physics_process(false)
	game.get_node("MonsterSpawner").process_mode = Node.PROCESS_MODE_DISABLED
	await physics_frame
	await physics_frame

	_test_speed_buff(player)
	await _test_tick_effects(player)
	await _test_other_host(game, player)
	_finish()


## 属性类 buff：施加、升级、降级、重复施加不叠乘、外部改值后认新基准
func _test_speed_buff(player: PlayerCharacter) -> void:
	var holder: BuffHolder = Buffs.holder_of(player)
	_check(holder != null, "玩家身上拿得到 BuffHolder")
	if holder == null:
		return

	var swift: BuffData = load(SWIFT_PATH) as BuffData
	var base_speed: float = player.max_speed

	_check(Buffs.apply(player, swift, 1), "施加「轻身」成功")
	var speed_level_1: float = player.max_speed
	_check(speed_level_1 > base_speed, "1 级轻身提高移速（%.1f → %.1f）" % [base_speed, speed_level_1])
	_check(holder.has(&"swift") and holder.get_level(&"swift") == 1, "容器里能查到轻身 1 级")

	#同一个 id 再次施加不能把加成叠上去
	Buffs.apply(player, swift, 1)
	_check(is_equal_approx(player.max_speed, speed_level_1), "重复施加同一等级不会叠乘（%.1f）" % player.max_speed)

	_check(Buffs.apply(player, swift, 2), "同 id 更高等级会升级并刷新时长")
	_check(holder.get_level(&"swift") == 2, "等级变成 2")
	var speed_level_2: float = player.max_speed
	_check(speed_level_2 >= speed_level_1, "2 级不低于 1 级（%.1f → %.1f）" % [speed_level_1, speed_level_2])

	_check(not Buffs.apply(player, swift, 1), "更低等级被忽略并返回 false")
	_check(holder.get_level(&"swift") == 2, "等级没有被降级")
	_check(is_equal_approx(player.max_speed, speed_level_2), "被忽略的施加不改数值")

	Buffs.apply(player, swift, 3)
	_check(player.max_speed > speed_level_2, "3 级比 2 级更快（%.1f → %.1f）" % [speed_level_2, player.max_speed])

	Buffs.remove(player, &"swift")
	_check(is_equal_approx(player.max_speed, base_speed), "移除后还原成基准 %.1f" % player.max_speed)

	#外部系统直接改了属性：下一次重算要把它认成新基准，而不是把旧基准写回去
	Buffs.apply(player, swift, 1)
	player.max_speed = 100.0
	Buffs.remove(player, &"swift")
	_check(is_equal_approx(player.max_speed, 100.0), "外部改过的值会认成新基准（%.1f）" % player.max_speed)


## 定时效果：减益掉血、增益回血
func _test_tick_effects(player: PlayerCharacter) -> void:
	var poison: BuffData = _make_dot(&"poison_tmp", 2.0, 0.1, 1.0)
	var before: float = player.health
	_check(Buffs.apply(player, poison, 1), "给玩家施加 DoT 减益")

	var shown: Array[Dictionary] = Buffs.display_list(player)
	_check(shown.size() == 1, "显示列表里有一项（HUD 用）")
	if shown.size() == 1:
		var shown_buff: BuffData = shown[0]["buff"]
		_check(shown_buff.is_debuff, "显示列表带减益标记（HUD 换红框）")

	var frames: int = 0
	while frames < 60 and player.health > before - 2.0:
		await physics_frame
		frames += 1
	_check(player.health <= before - 2.0,
			"DoT 在 %.2f 秒内扣了至少 2 点血（%.1f → %.1f）" % [float(frames) * STEP, before, player.health])

	Buffs.clear(player)
	_check(Buffs.display_list(player).is_empty(), "clear 之后容器空了")

	player.take_damage(5.0)
	var hurt: float = player.health
	Buffs.apply(player, load(REGEN_PATH) as BuffData, 1)
	var waited: float = 0.0
	while waited < 1.5 and player.health <= hurt:
		await physics_frame
		waited += STEP
	_check(player.health > hurt, "持续恢复开始回血（%.1f → %.1f）" % [hurt, player.health])


## 非玩家宿主与没有容器的目标
func _test_other_host(game: Node2D, player: PlayerCharacter) -> void:
	var dummy: TrainingDummy = (load(DUMMY_SCENE) as PackedScene).instantiate() as TrainingDummy
	game.add_child(dummy)
	await physics_frame
	await physics_frame

	var before_defense: float = dummy.health.defense
	_check(Buffs.apply(dummy, load(DEFENSE_UP_PATH) as BuffData, 1), "训练靶也能施加「护体」")
	_check(dummy.health.defense > before_defense,
			"护体把训练靶防御写回（%.1f → %.1f）" % [before_defense, dummy.health.defense])

	var plain: Node2D = Node2D.new()
	game.add_child(plain)
	_check(not Buffs.apply(plain, load(SWIFT_PATH) as BuffData, 1), "没有 BuffHolder 的目标安静返回 false")
	_check(Buffs.holder_of(plain) == null, "取不到容器的目标返回 null")

	Buffs.clear(dummy)
	_check(is_equal_approx(dummy.health.defense, before_defense), "训练靶清空后防御还原")


func _finish() -> void:
	print("BUFFS: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)