extends SceneTree

## 药水效果强度（等级成长 + 药材学）的覆盖范围验收：
## 哪些数量的效果会跟着变强、哪些有意不变，以及武器附魔/普通 buff 不会被带偏。
##
## 运行：godot --headless --path . --script res://tools/test_potion_power.gd

const PLAYER_SCENE: PackedScene = preload("res://scenes/game/player.tscn")
const POISON_BUFF: BuffData = preload("res://resources/buffs/poison.tres")
const SLOW_BUFF: BuffData = preload("res://resources/buffs/slow.tres")
const THORNS_BUFF: BuffData = preload("res://resources/buffs/thorns.tres")

## 属性 id（见 AlchemicalAttributeList.ATTRIBUTE）
const EXPLOSIVE_ID: int = 6
const FIRE_ID: int = 7
const POISON_ID: int = 10
const SLOW_ID: int = 11
const THORNS_ID: int = 16
const THUNDER_ID: int = 23
const ICE_ID: int = 36

## 手动设进上下文用的药水强度（和等级无关，纯粹验证读取点）
const POWER: float = 1.5
## 端到端那一段用的等级：期望值从 RunProgress.level_growth() 现算，
## 这样改等级成长步长不用跟着改测试
const LEVEL_FOR_POWER: int = 8

var _checks: int = 0
var _failures: int = 0
var _attributes: Node = null
var _progress: Node = null
var _arena: Node2D = null
var _player: PlayerCharacter = null


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
	else:
		print("ok: " + message)


func _sync_physics() -> void:
	await physics_frame
	await physics_frame


## 造一个能挨打的敌对目标（阵营 2 / Layer 3 = 值 4）
func _target(at: Vector2) -> HealthComponent:
	var target: Node2D = Node2D.new()
	target.position = at
	var health: HealthComponent = HealthComponent.new()
	health.max_health = 1000.0
	target.add_child(health)
	var hurtbox: CombatHurtbox = CombatHurtbox.new()
	hurtbox.health = health
	hurtbox.team = 2
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 4.0
	shape_node.shape = shape
	hurtbox.add_child(shape_node)
	target.add_child(hurtbox)
	_arena.add_child(target)
	return health


## 在 at 处结算一次药水效果（药水破碎时传进来的就是落点上的 Node2D）
func _apply_at(attribute: AlchemicalData, at: Vector2, power: float) -> void:
	var center: Node2D = Node2D.new()
	_arena.add_child(center)
	center.global_position = at
	Buffs.set_next_power_scale(power)
	attribute.use_effect(center)
	Buffs.reset_power_scale()


## 直接让目标身上的某个 buff 跳一次（绕过物理帧，结果可预期）
func _tick_buff(holder: BuffHolder, seconds: float) -> void:
	holder.set_physics_process(false)
	holder.call("_physics_process", seconds)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_attributes = root.get_node("AlchemicalAttributeList")
	_progress = root.get_node("RunProgress")
	_arena = Node2D.new()
	root.add_child(_arena)
	_progress.reset()

	_player = PLAYER_SCENE.instantiate() as PlayerCharacter
	_player.add_to_group("player")
	_arena.add_child(_player)
	_player.set_physics_process(false)
	_player.weapon_controller.set_physics_process(false)
	await process_frame

	#////////////////////////// 默认：非药水路径原样
	_check(is_equal_approx(Buffs.power_scale(), 1.0), "默认威力倍率是 1.0（武器附魔/怪物攻击读到的是原样）")
	_check(not _progress.cards_taken.has(&"alchemy_power") and _progress.level == 1, "开局没有药材学、1级零成长")
	_check(is_equal_approx(_player.potion_power_mult(), 1.0), "1级玩家的药水强度是 1.0")

	#////////////////////////// 直接数值伤害：爆炸
	var explosive: Explosive = _attributes.create(EXPLOSIVE_ID, 1) as Explosive
	var base_enemy: float = explosive.enemy_damage()
	var base_self: float = explosive.player_damage_total()
	var base_radius: float = explosive.blast_radius()
	Buffs.set_next_power_scale(POWER)
	_check(is_equal_approx(explosive.enemy_damage(), base_enemy * POWER), "爆炸对敌人的伤害吃药水强度")
	_check(is_equal_approx(explosive.player_damage_total(), base_self), "爆炸对自己的自伤不吃药水强度（不会把自己炸得更惨）")
	_check(is_equal_approx(explosive.blast_radius(), base_radius), "爆炸半径不吃药水强度")
	Buffs.reset_power_scale()
	_check(is_equal_approx(explosive.enemy_damage(), base_enemy), "复位后爆炸伤害回到原值")

	#////////////////////////// 直接数值伤害：雷 / 火 / 冰
	var thunder: Thunder = _attributes.create(THUNDER_ID, 1) as Thunder
	var fire: Fire = _attributes.create(FIRE_ID, 1) as Fire
	var ice: Ice = _attributes.create(ICE_ID, 1) as Ice
	var thunder_base: float = thunder.damage_total()
	var fire_base: float = fire.damage_total()
	var freeze_base: float = ice.freeze_value()
	var shatter_base: float = ice.shatter_damage_total()
	Buffs.set_next_power_scale(POWER)
	_check(is_equal_approx(thunder.damage_total(), thunder_base * POWER), "落雷伤害吃药水强度")
	_check(is_equal_approx(fire.damage_total(), fire_base * POWER), "火焰伤害吃药水强度")
	_check(is_equal_approx(ice.freeze_value(), freeze_base * POWER), "冰冻值累积吃药水强度（冻得更快）")
	_check(is_equal_approx(ice.shatter_damage_total(), shatter_base * POWER), "冰冻碎裂伤害吃药水强度")
	Buffs.reset_power_scale()

	#////////////////////////// buff 的定时伤害（毒）
	_player.health = _player.max_health
	var before: float = _player.health
	_player.health_component.invulnerable = false
	Buffs.apply(_player, POISON_BUFF, 1)
	var holder: BuffHolder = Buffs.holder_of(_player)
	_tick_buff(holder, 1.1)
	var plain_tick: float = before - _player.health
	_check(plain_tick > 0.0, "中毒每跳都会掉血")

	Buffs.clear(_player)
	_player.health = _player.max_health
	before = _player.health
	Buffs.set_next_power_scale(POWER)
	Buffs.apply(_player, POISON_BUFF, 1)
	Buffs.reset_power_scale()
	holder = Buffs.holder_of(_player)
	_tick_buff(holder, 1.1)
	var strong_tick: float = before - _player.health
	_check(is_equal_approx(strong_tick, plain_tick * POWER), "中毒每跳伤害按药水强度放大")
	Buffs.clear(_player)

	#////////////////////////// buff 的属性修改（迟缓）
	_player.health = _player.max_health
	var base_move: float = _player._move_speed()
	_check(is_equal_approx(base_move, _player.max_speed), "没有 buff 时移速就是基准值")

	#百分比从资源里读，别在测试里写死——平衡一调测试就得跟着改
	var slow_amount: float = SLOW_BUFF.modifiers[0].amount(1)
	_check(slow_amount < 0.0, "迟缓是负的移速修改(%s)" % str(slow_amount))

	Buffs.apply(_player, SLOW_BUFF, 1)
	var plain_move: float = _player._move_speed()
	_check(is_equal_approx(plain_move, base_move * (1.0 + slow_amount)), "1级迟缓按自身数值减移速")
	Buffs.clear(_player)
	await process_frame

	Buffs.set_next_power_scale(POWER)
	Buffs.apply(_player, SLOW_BUFF, 1)
	Buffs.reset_power_scale()
	var strong_move: float = _player._move_speed()
	_check(is_equal_approx(strong_move, base_move * (1.0 + slow_amount * POWER)),
		"迟缓的百分比乘上了药水强度(%s → %s)" % [str(plain_move), str(strong_move)])
	_check(strong_move < plain_move, "药水越强减速越狠")
	Buffs.clear(_player)
	await process_frame

	#////////////////////////// 减速叠到爆也不会变成负速度
	Buffs.set_next_power_scale(9.0)
	Buffs.apply(_player, SLOW_BUFF, 3)
	Buffs.reset_power_scale()
	_check(_player._move_speed() > 0.0, "极端强度下移速被兜底，不会变成负速度（人往后走）")
	Buffs.clear(_player)
	await process_frame

	#////////////////////////// 标记类：荆棘反伤
	_player.health = _player.max_health
	var attacker: Node2D = Node2D.new()
	_arena.add_child(attacker)
	var attacker_health: HealthComponent = HealthComponent.new()
	attacker_health.name = "Health"
	attacker_health.max_health = 500.0
	attacker.add_child(attacker_health)
	await _sync_physics()
	attacker_health.reset()

	Buffs.apply(_player, THORNS_BUFF, 1)
	_player.take_damage(10.0, attacker)
	var plain_back: float = attacker_health.max_health - attacker_health.current_health
	_check(plain_back > 0.0, "荆棘会把伤害弹回攻击者(%s)" % str(plain_back))
	Buffs.clear(_player)

	_player.health = _player.max_health
	attacker_health.reset()
	Buffs.set_next_power_scale(POWER)
	Buffs.apply(_player, THORNS_BUFF, 1)
	Buffs.reset_power_scale()
	_player.take_damage(10.0, attacker)
	var strong_back: float = attacker_health.max_health - attacker_health.current_health
	_check(is_equal_approx(strong_back, plain_back * POWER), "荆棘反伤按药水强度放大")
	Buffs.clear(_player)

	#////////////////////////// 端到端：等级 6 喝一瓶爆炸药水
	_progress.level = LEVEL_FOR_POWER
	var level_power: float = 1.0 + _progress.level_growth()
	_check(level_power > 1.0, "等级成长确实带来了药水强度(%s)" % str(level_power))
	_check(is_equal_approx(_player.potion_power_mult(), level_power),
		"%d级玩家的药水强度是 %s" % [LEVEL_FOR_POWER, str(level_power)])

	_player.global_position = Vector2.ZERO
	_player.health = _player.max_health
	var victim: HealthComponent = _target(Vector2(18.0, 0.0))
	await _sync_physics()

	var potion: PotionData = (load("res://resources/items/potions/potion_model.tres") as PotionData).duplicate() as PotionData
	potion.alchemical_attribute = [explosive]
	var health_before: float = _player.health
	_check(potion.left_use(_player) == 1, "药水可以喝下")
	var victim_damage: float = victim.max_health - victim.current_health
	var self_damage: float = health_before - _player.health
	_check(is_equal_approx(victim_damage, base_enemy * level_power),
		"喝下 %d 级药水，爆炸伤害 = 基础 × %s(%s)" % [LEVEL_FOR_POWER, str(level_power), str(victim_damage)])
	_check(is_equal_approx(self_damage, base_self), "自己的自伤还是原值(%s)" % str(self_damage))
	_check(is_equal_approx(Buffs.power_scale(), 1.0), "结算完威力倍率复位，不会漏到后面的攻击上")

	#////////////////////////// 投掷路径：碎点范围圈也带上强度
	Buffs.clear(_player)
	_player.apply_progress(true)
	var slow: Slow = _attributes.create(SLOW_ID, 1) as Slow
	var burst: PotionBurst = (load("res://scenes/items/potions/potion_burst.tscn") as PackedScene).instantiate() as PotionBurst
	_arena.add_child(burst)
	await _sync_physics()
	burst.setup(Vector2.ZERO, 32.0, 0.0, [slow], null, 1.0, POWER)
	burst.set_physics_process(false)
	_check(is_equal_approx(burst.power_scale, POWER), "范围圈记下了出手时的药水强度")
	Buffs.clear(_player)
	burst._apply_attributes(_player, false)
	_check(is_equal_approx(_player._move_speed(), base_move * (1.0 + slow_amount * POWER)),
		"投掷落点的范围圈按药水强度结算")
	Buffs.clear(_player)
	burst.queue_free()
	await process_frame

	#////////////////////////// 投掷路径：强度在出手那一刻定格
	var thrown: PotionData = (load("res://resources/items/potions/potion_model.tres") as PotionData).duplicate() as PotionData
	thrown.alchemical_attribute = [explosive]
	_check(thrown.right_use(_player) == 1, "药水可以投出去")
	var flight: PotionProjectile = null
	for child: Node in _arena.get_children():
		if child is ItemModel:
			for sub: Node in child.get_children():
				if sub is PotionProjectile:
					flight = sub as PotionProjectile
	_check(flight != null, "投掷生成了弹道")
	if flight != null:
		_check(is_equal_approx(float(flight.get("_power")), level_power), "投掷时把药水强度定在出手那一刻")
		flight.get_parent().queue_free()
	await process_frame

	_progress.reset()
	print("药水强度覆盖验收：%d 项检查，%d 项失败" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
