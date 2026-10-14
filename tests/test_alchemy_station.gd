extends SceneTree

## 随身炼金台集成测试：世界材料桥接、背包→素材槽→炼金、热量过载、武器倍率与失效。

const LONGSWORD: WeaponDefinition = preload("res://resources/weapons/longsword.tres")

var _checks: int = 0
var _failures: int = 0
var _arena: Node2D = null
var _controller: WeaponController = null
var _stations: Array[AlchemyStation] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_test_defaults()
	_test_bridge()
	_test_absorb_and_preview()
	_test_brew_and_consume()
	_test_repeat_recipe()
	_test_overload()
	_test_interrupt()
	await _test_weapon_multiplier()
	for station: AlchemyStation in _stations:
		if is_instance_valid(station):
			station.free()
	print("ALCHEMY STATION: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _station() -> AlchemyStation:
	var station: AlchemyStation = AlchemyStation.new()
	station.setup()
	_stations.append(station)
	return station


## 最小可玩原型 / 正式玩法的默认数值。
func _test_defaults() -> void:
	var station: AlchemyStation = _station()
	_check(station.slots.slot_count() == 2, "默认素材槽 2 格")
	_check(station.bag.capacity == 12, "默认背包 12 格")
	_check(station.pool_limit == AlchemyRules.POOL_LIMIT_FULL, "正式玩法词条池上限 10")
	_check(AlchemyRules.POOL_LIMIT_FULL >= 8 and AlchemyRules.POOL_LIMIT_FULL <= 10, "词条池上限落在 8~10")
	_check(AlchemyRules.POOL_LIMIT_PROTOTYPE == 6, "最小可玩原型词条池上限 6")
	_check(is_equal_approx(AlchemyRules.BASE_DURATION, 12.0), "基础时长 12 秒")
	_check(is_equal_approx(AlchemyRules.HEAT_MAX, 100.0), "热量上限 100")
	_check(is_equal_approx(AlchemyRules.SLOW_MOTION_SCALE, 0.25), "长按轮盘 25% 慢动作")
	_check(station.active_combo() == null, "初始只有一个效果槽且为空")
	_check(station.weapon_slots.temporary_limit == 1, "初始 1 个武器临时炼金槽")


func _test_bridge() -> void:
	_check(MaterialCatalog.material_id_for_world(2) == 1002, "石头 → 硝石")
	_check(MaterialCatalog.material_id_for_world(3) == 1006, "木棍 → 火油")
	_check(MaterialCatalog.material_id_for_world(4) == 1003, "给毛 → 骨粉")
	_check(MaterialCatalog.material_id_for_world(5) == 1001, "猴皮 → 毒菇")
	_check(MaterialCatalog.material_id_for_world(999) == -1, "未登记的世界材料没有映射")


func _test_absorb_and_preview() -> void:
	var station: AlchemyStation = _station()
	_check(station.absorb_world_material(999, 3) == 0, "未知世界材料不收进背包")
	_check(station.absorb_world_material(2, 5) == 5, "石头吸附 5 个硝石")
	_check(station.bag.count(1002) == 5, "硝石进背包")
	_check(station.slots.material_ids().has(1002), "吸附后自动填入素材槽")
	var pool: TraitPoolResult = station.preview()
	_check(pool.has_trait(&"fire") and pool.has_trait(&"explode"), "预览含火与爆炸词条")
	_check(pool.effect_tags.has(&"fire"), "效果标签含火")


func _test_brew_and_consume() -> void:
	var station: AlchemyStation = _station()
	station.absorb_material(1002, 4)
	station.absorb_material(1001, 4)
	station.clear_slots()
	_check(station.set_slot(0, 1002), "放入硝石")
	_check(station.set_slot(1, 1001), "放入毒菇")
	var combo: BrewCombo = station.brew_from_slots()
	_check(combo != null, "素材槽可以炼金")
	_check(combo.effect_tags.has(&"poison_smoke"), "火+毒产出毒烟反应")
	_check(station.active_combo() != null, "组合生效")
	_check(station.bag.count(1002) == 3 and station.bag.count(1001) == 3, "炼金各消耗 1 个材料")
	_check(is_equal_approx(station.heat(), AlchemyRules.HEAT_PER_BREW), "首次炼金热量 +20")
	_check(station.duration_remaining() > 0.0, "组合开始倒计时")


func _test_repeat_recipe() -> void:
	var station: AlchemyStation = _station()
	station.absorb_material(1002, 3)
	station.absorb_material(1001, 3)
	station.clear_slots()
	station.set_slot(0, 1002)
	station.set_slot(1, 1001)
	station.brew_from_slots()
	var before: int = station.bag.count(1002)
	var repeated: BrewCombo = station.repeat_last_recipe()
	_check(repeated != null, "短按 E 复用上次配方")
	_check(station.bag.count(1002) == before - 1, "复用配方同样消耗材料")
	_check(station.session.last_recipe == [1002, 1001], "配方按槽位顺序记录")
	station.bag.remove(1002, 99)
	_check(station.repeat_last_recipe() == null, "材料不足时复用失败")


func _test_overload() -> void:
	var station: AlchemyStation = _station()
	var captured: Dictionary = {}
	station.overloaded.connect(func(report: Dictionary) -> void: captured["report"] = report)
	station.absorb_material(1002, 2)
	station.set_slot(0, 1002)
	station.brew_from_slots()
	_check(station.active_combo() != null, "过载前组合生效")
	station.session.heat.add_heat(AlchemyRules.HEAT_MAX)
	_check(captured.has("report"), "热量满触发过载")
	_check(station.active_combo() == null, "过载结束当前效果")
	_check(station.is_weapon_disabled(), "过载使武器失效")
	_check(not station.session.heat.can_brew(), "过载后短时间内不能炼金")


func _test_interrupt() -> void:
	var station: AlchemyStation = _station()
	station.in_combat = true
	station.press_brew()
	station.input_state.tick(AlchemyRules.LONG_PRESS_SECONDS + 0.01)
	_check(station.is_wheel_open(), "长按打开轮盘")
	var heat_before: float = station.heat()
	var materials_before: int = station.slots.material_ids().size()
	_check(station.interrupt(), "受击打断轮盘")
	_check(not station.is_wheel_open(), "打断后轮盘关闭")
	_check(is_equal_approx(station.heat() - heat_before, AlchemyRules.HEAT_PER_INTERRUPT), "打断 +10 热量")
	_check(station.slots.material_ids().size() == materials_before, "打断不丢材料")
	_check(not station.session.heat.is_locked(), "打断不进炼金锁定")


func _test_weapon_multiplier() -> void:
	_arena = Node2D.new()
	root.add_child(_arena)
	var actor: Node2D = Node2D.new()
	_arena.add_child(actor)
	_controller = WeaponController.new()
	actor.add_child(_controller)
	_controller.set_physics_process(false)
	var data: WeaponDefinition = LONGSWORD.duplicate(true) as WeaponDefinition
	data.critical_chance = 0.0
	_check(_controller.equip(data), "长剑可装备")
	var health: HealthComponent = _target(Vector2(35, 0))
	await physics_frame
	await physics_frame
	_controller.damage_multiplier = 2.0
	_controller.set_aim(Vector2.RIGHT)
	_check(_controller.try_attack(), "起手成功")
	var attack: WeaponAttack = _current_attack()
	_check(attack != null and is_equal_approx(attack.damage_multiplier, 2.0), "炼金倍率注入攻击实例")
	attack._physics_process(0.07)
	_check(health.current_health == 1000.0, "前摇不造成伤害")
	attack._physics_process(0.19)
	_check(is_equal_approx(health.current_health, 964.0), "炼金倍率把 18 点伤害放大到 36 点")
	_controller.cancel_attack()
	_controller.set_disabled(AlchemyRules.OVERLOAD_WEAPON_DISABLE)
	_check(_controller.is_disabled(), "过载后武器失效可查询")
	_check(not _controller.try_attack(), "失效期间无法起手")
	_controller.set_disabled(0.0)
	_check(not _controller.is_disabled(), "失效结束恢复")
	_arena.free()
	_arena = null


func _current_attack() -> WeaponAttack:
	for child: Node in _controller.get_children():
		if child is WeaponAttack and not child.is_queued_for_deletion():
			var attack := child as WeaponAttack
			attack.set_physics_process(false)
			return attack
	return null


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
	shape.radius = 3.0
	shape_node.shape = shape
	hurtbox.add_child(shape_node)
	target.add_child(hurtbox)
	_arena.add_child(target)
	return health
