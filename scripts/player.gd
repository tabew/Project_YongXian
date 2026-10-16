class_name PlayerCharacter
extends CharacterBody2D

signal health_changed(current: float, maximum: float)
signal defeated

## 主角占位实现：WASD / 方向键控制，速度带加速度与摩擦力，摄像机跟随。
##
## 地形阻挡不依赖物理层，而是直接问 WorldGenerator 这一格是什么地形。
## 生成器是纯函数式的（只由种子和坐标决定），所以判定结果和画面上看到的永远一致，
## 不需要等区块加载完。
##
## 生命走通用 HealthComponent，与怪物同一套刻度（100 点为基准），
## 因此局内成长卡的百分比与固定值才有统一含义。

const REGEN_COMBAT_LOCKOUT: float = 4.0
const COMBO_WINDOW: float = 2.0
const COMBO_MAX_STACKS: int = 5

@export_group("移动手感")
## 最大速度（像素/秒）。
@export var max_speed: float = 220.0
## 加速度：按住方向键时每秒增加多少速度。
@export var acceleration: float = 1400.0
## 摩擦力：松开按键后每秒衰减多少速度。
@export var friction: float = 1800.0

@export_group("地形")
## 打开后无法走进深水、浅水、山地和雪峰（路上的格子除外）。
@export var collide_with_terrain: bool = true

@export_group("生命")
## 基础生命上限；升级卡的加值由 max_health 属性叠加在上层。
@export var base_max_health: float = 100.0
## 基础固定减伤；升级卡的加值由 defense 属性叠加在上层。
@export var base_defense: float = 0.0
## 基础拾取范围（格）。
@export var base_pickup_radius: float = 1.5

@onready var sprite: Sprite2D = $Sprite2D
@onready var weapon_controller: WeaponController = $WeaponController
@onready var health_component: HealthComponent = $Health

@export_group("背包")
@export var inventory:Inventory

#玩家所持物品id
var handy_item:int

## 地形来源，由 GameWorld 注入。
var terrain_source: WorldGenerator = null
## 当前箱庭的矩形通行边界，出口由 GameWorld 瞬切。
var active_map: MapSpec = null

##受到的伤害倍率：1.0 表示正常，减伤类 buff 会把它调小。
##升级卡的减伤走 RunProgress，这里是 buff 的那一层，两者相乘。
var damage_taken: float = 1.0

# 上一个查过的格子。主角一帧最多查两次，缓存一下省掉重复的噪声计算
var _cached_tile: Vector2i = Vector2i(2147483647, 2147483647)
var _cached_walkable: bool = true

## 命中同一目标的连续次数，用于“节奏”卡。
var _combo_targets: Dictionary = {}
var _combo_timers: Dictionary = {}
## 脱战计时，用于“再生”卡。
var _combat_lockout: float = 0.0
## 药水带来的持续回复：剩余秒数与本段每秒回复量。
var _regen_remaining: float = 0.0
var _regen_per_second: float = 0.0
var _was_defeated: bool = false


func _ready() -> void:
	health_component.died.connect(_on_health_died)
	health_component.health_changed.connect(_on_health_changed)
	health_component.max_health = max_health
	health_component.current_health = max_health

	# 直接实例化 player.tscn 的场景（测试、编辑器单跑）可能没有背包，
	# 缺背包时跳过装备初始化，但成长仍然要应用。
	if inventory != null:
		inventory.handy_selection_changed.connect(handy_item_changed)
		inventory._init()
		handy_item_changed()

	apply_progress(true)


## 升级卡聚合后的生命上限。
var max_health: float:
	get:
		return maxf(base_max_health + _progress_value("max_health_add"), 1.0)
	set(value):
		base_max_health = value


## 升级卡聚合后的固定减伤。
var defense: float:
	get:
		return maxf(base_defense + _progress_value("defense_add"), 0.0)
	set(value):
		base_defense = value


## 当前生命，直接读生命组件。
var health: float:
	get:
		if is_instance_valid(health_component):
			return health_component.current_health
		return 0.0
	set(value):
		if is_instance_valid(health_component):
			health_component.set_current_health(value)


## 拾取范围（格）：基础值加升级卡。
func pickup_radius_tiles() -> float:
	return maxf(base_pickup_radius + _progress_value("pickup_radius_add"), 0.5)


## 由 GameWorld 在绑定时与选卡后调用：把升级卡重新落到玩家身上。
## fill 为真时回满生命（新一局 / 新世界）。
func apply_progress(fill: bool = false) -> void:
	var previous_max: float = health_component.max_health
	health_component.max_health = max_health
	health_component.defense = defense
	if fill:
		health_component.current_health = health_component.max_health
	else:
		# 取到生命上限卡时把新增的部分补进当前生命，否则加血卡毫无即时手感。
		var delta: float = health_component.max_health - previous_max
		health_component.set_current_health(health_component.current_health + maxf(delta, 0.0))
	health_component.health_changed.emit(health_component.current_health, health_component.max_health)
	rebuild_weapon()


## 用升级卡重造当前武器。必须在副本上叠卡，直接改会写回 .tres 并跨局残留。
func rebuild_weapon() -> void:
	var base: WeaponDefinition = _base_weapon()
	if base == null:
		weapon_controller.equip(null)
		return
	var progress: Node = _run_progress()
	var built: WeaponDefinition = progress.build_weapon(base) if progress != null else base
	if weapon_controller.equip(built):
		return
	# 叠卡后不合法：退回基础武器，避免卡看起来生效其实没换装。
	weapon_controller.equip(base)


## 当前选中格对应的基础武器定义（原始 .tres，未被升级卡污染）。
func _base_weapon() -> WeaponDefinition:
	if inventory == null or handy_item < 200 or handy_item >= 300:
		return null
	var data: ItemData = inventory.get_item_data.get(handy_item)
	if data == null or not (data is WeaponData):
		return null
	return (data as WeaponData).weapon


func _physics_process(delta: float) -> void:
	weapon_controller.set_aim(get_global_mouse_position() - global_position)
	_tick_progress(delta)
	if health <= 0.0:
		velocity = Vector2.ZERO
		weapon_controller.cancel_attack()
		return
	var input_direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	_apply_input(input_direction, delta)
	_integrate_movement(delta)
	_update_facing()


## 再生与连击计时。
func _tick_progress(delta: float) -> void:
	_combat_lockout = maxf(_combat_lockout - delta, 0.0)
	if _regen_remaining > 0.0:
		var step: float = minf(delta, _regen_remaining)
		_regen_remaining -= step
		if health_component.is_alive():
			health_component.heal(_regen_per_second * step)
	var progress: Node = _run_progress()
	if progress == null:
		return
	if _combat_lockout <= 0.0:
		var regen: float = progress.regen_per_second()
		if regen > 0.0 and health_component.is_alive():
			health_component.heal(regen * delta)
	for id: int in _combo_timers.keys():
		_combo_timers[id] = float(_combo_timers[id]) - delta
		if float(_combo_timers[id]) <= 0.0:
			_combo_timers.erase(id)
			_combo_targets.erase(id)


func _unhandled_input(event: InputEvent) -> void:
	if health > 0.0:
		if event.is_action_pressed("attack"):
			#选中物品左键使用
			if is_ui_blocking():
				return

			inventory.left_use_handy_slot(self)
			weapon_controller.set_trigger_pressed(true)
			get_viewport().set_input_as_handled()
			return
		
		elif event.is_action_pressed("throw"):
			#选中物品右键使用
			if is_ui_blocking():
				return

			inventory.right_use_handy_slot(self)
			get_viewport().set_input_as_handled()
			return
		

func handy_item_changed()->void:
	handy_item = inventory.get_handy_slot_id(inventory.get_selected_handy())

	if handy_item >=200&&handy_item<300:
		rebuild_weapon()
	else:
		weapon_controller.equip(null)


##ui是否挡着世界操作
func is_ui_blocking() -> bool:

	var hud:Node = get_tree().get_first_node_in_group("game_hud")

	if hud == null:
		return false

	for panel_name:String in ["BagUi", "Alchemy", "UpgradePanel", "CheatPanel"]:
		var panel:CanvasItem = hud.get_node_or_null(panel_name) as CanvasItem

		if panel != null and panel.visible:
			return true

	return false


func _input(event: InputEvent) -> void:
	# Release must also reach us when a UI control consumes the event.
	if event.is_action_released("attack"):
		weapon_controller.set_trigger_pressed(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(weapon_controller):
		weapon_controller.cancel_attack()


## 有输入时朝目标速度加速，松手后按摩擦力减速到 0。
func _apply_input(input_direction: Vector2, delta: float) -> void:
	if input_direction != Vector2.ZERO:
		var target_velocity: Vector2 = input_direction * _move_speed()
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


func _move_speed() -> float:
	var progress: Node = _run_progress()
	return max_speed * (progress.move_speed_mult() if progress != null else 1.0)


func _integrate_movement(delta: float) -> void:
	if active_map == null and (terrain_source == null or not collide_with_terrain):
		move_and_slide()
		return

	# 分轴推进：撞到障碍时只损失该轴的速度，贴边移动依然顺滑
	var step: Vector2 = velocity * delta

	var next_x: Vector2 = global_position + Vector2(step.x, 0.0)
	if can_stand_at(next_x):
		global_position.x = next_x.x
	else:
		velocity.x = 0.0

	var next_y: Vector2 = global_position + Vector2(0.0, step.y)
	if can_stand_at(next_y):
		global_position.y = next_y.y
	else:
		velocity.y = 0.0


## 该世界坐标所在的格子是否可以站人。
## 判定交给生成器：地形可通行，或者那里是路（路会架桥 / 开山道）。
func can_stand_at(world_position: Vector2) -> bool:
	var tile: Vector2i = WorldGenerator.world_to_tile(world_position)
	if active_map != null:
		var local: Vector2i = tile - active_map.origin
		if not active_map.contains_local(local.x, local.y):
			return false
	if terrain_source == null or not collide_with_terrain:
		return true
	if tile != _cached_tile:
		_cached_tile = tile
		_cached_walkable = terrain_source.is_walkable(tile)
	return _cached_walkable


## 由 GameWorld 调用：注入地形来源并把主角放到指定世界坐标。
func spawn_on(source: WorldGenerator, world_position: Vector2, map_spec: MapSpec = null, reset_health: bool = true) -> void:
	weapon_controller.cancel_attack()
	terrain_source = source
	active_map = map_spec
	velocity = Vector2.ZERO
	global_position = world_position
	_cached_tile = Vector2i(2147483647, 2147483647)
	if reset_health:
		apply_progress(true)


##BuffHolder 读当前属性值（认基准用）。
##
## 必须返回“不含 buff 的基础值”：BuffHolder 的算法是“读基准 → 加 buff 修正 → 写回”，
## 如果这里返回已经含 buff 或含升级卡的值，每次重算都会把加成再叠一遍、越滚越大。
## 升级卡的加成由各自的 getter 叠在最上层，不参与 buff 的基准。
func read_stat(stat: StringName) -> float:
	match stat:
		&"move_speed":
			return max_speed
		&"defense":
			return base_defense
		&"damage_taken":
			return damage_taken
	return 0.0


##BuffHolder 把算好的值写回基础属性。
func apply_stat(stat: StringName, value: float) -> void:
	match stat:
		&"move_speed":
			max_speed = value
		&"defense":
			base_defense = value
			#固定减伤最终由生命组件扣，buff 改完要同步过去。
			if is_instance_valid(health_component):
				health_component.defense = defense
		&"damage_taken":
			damage_taken = value


## 受到伤害：先过 buff 的倍率、升级卡的倍率与固定减伤，再交给生命组件。
func take_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	var scaled: float = _incoming_damage(amount)
	if scaled <= 0.0:
		return
	_play_sfx(&"player_hurt", global_position)
	_combat_lockout = REGEN_COMBAT_LOCKOUT
	_combo_targets.clear()
	_combo_timers.clear()
	var hit: CombatHit = CombatHit.new()
	hit.source = null
	hit.damage = scaled
	hit.position = global_position
	health_component.receive_hit(hit)


## 固定减伤在生命组件里扣，这里只负责倍率部分（buff 的 damage_taken / 坚韧 / 薄刃 / 濒死）。
func _incoming_damage(amount: float) -> float:
	var scaled: float = amount * maxf(damage_taken, 0.0)
	var progress: Node = _run_progress()
	if progress == null:
		return maxf(scaled, 0.0)
	scaled *= progress.damage_taken_mult()
	var low: float = progress.low_health_reduction()
	if low > 0.0 and health_component.max_health > 0.0 and health / health_component.max_health < 0.3:
		scaled *= 1.0 - low
	return maxf(scaled, 0.0)


## 治疗：药水走这里，受“药材学 / 以血换知”影响。
func heal(amount: float) -> float:
	if amount <= 0.0 or health <= 0.0:
		return 0.0
	var progress: Node = _run_progress()
	var scaled: float = amount
	if progress != null:
		scaled *= progress.alchemy_power_mult() * progress.heal_mult()
	return health_component.heal(scaled)


## 持续回复药水挂上的按秒回复。
func add_regeneration(per_second: float, seconds: float) -> void:
	if per_second <= 0.0 or seconds <= 0.0:
		return
	_regen_per_second = maxf(_regen_per_second, per_second)
	_regen_remaining = maxf(_regen_remaining, seconds)


## 药水投掷距离倍率。
func potion_range_mult() -> float:
	var progress: Node = _run_progress()
	return progress.potion_range_mult() if progress != null else 1.0


## 药水是否被“苦行”禁用。
func potions_blocked() -> bool:
	var progress: Node = _run_progress()
	return progress != null and progress.potion_blocked()


## 击杀结算：嗜血回血、连锁对周围目标造成伤害。
func on_monster_killed(monster: Node2D, base_damage: float) -> void:
	var progress: Node = _run_progress()
	if progress == null:
		return
	var lifesteal: float = progress.lifesteal_on_kill()
	if lifesteal > 0.0:
		health_component.heal(lifesteal)
	var chain: float = progress.chain_mult()
	if chain > 0.0 and base_damage > 0.0 and is_instance_valid(monster):
		_chain_damage(monster, base_damage * chain)


func _chain_damage(origin: Node2D, damage: float) -> void:
	var radius: float = float(WorldGenerator.TILE_SIZE) * 2.0
	for node: Node in get_tree().get_nodes_in_group("monsters"):
		var target := node as Node2D
		if target == null or target == origin or not is_instance_valid(target):
			continue
		if target.global_position.distance_to(origin.global_position) > radius:
			continue
		if target.has_method("apply_chain_damage"):
			target.call("apply_chain_damage", damage, self)


## 单次出手的伤害倍率：全武器加成 x “节奏”连击层数。
func outgoing_damage_multiplier(hurtbox: CombatHurtbox) -> float:
	var progress: Node = _run_progress()
	if progress == null:
		return 1.0
	var multiplier: float = progress.damage_mult()
	var per_stack: float = progress.combo_damage_per_stack()
	if per_stack > 0.0 and hurtbox != null:
		var id: int = hurtbox.receiver_id()
		var stacks: int = mini(int(_combo_targets.get(id, 0)), COMBO_MAX_STACKS)
		multiplier *= 1.0 + per_stack * float(stacks)
	return multiplier


## 记录一次命中，推进连击层数。同一目标连续命中才累计。
func register_hit(hurtbox: CombatHurtbox) -> void:
	var progress: Node = _run_progress()
	if progress == null or progress.combo_damage_per_stack() <= 0.0 or hurtbox == null:
		return
	var id: int = hurtbox.receiver_id()
	_combo_targets[id] = mini(int(_combo_targets.get(id, 0)) + 1, COMBO_MAX_STACKS)
	_combo_timers[id] = COMBO_WINDOW


func _on_health_changed(current: float, maximum: float) -> void:
	health_changed.emit(current, maximum)


func _on_health_died(_hit: CombatHit) -> void:
	if _was_defeated:
		return
	_was_defeated = true
	velocity = Vector2.ZERO
	_play_sfx(&"player_defeat")
	defeated.emit()
	_notify("生命归零")


func _notify(message: String) -> void:
	var event_bus: Node = get_node_or_null("/root/EventBus")
	if event_bus != null and event_bus.has_signal("notification"):
		event_bus.emit_signal("notification", message)


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载（与 _notify 的 EventBus 一致）。
func _play_sfx(id: StringName, position: Vector2 = Vector2.INF) -> void:
	var manager: Node = get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.call("play_sfx", id, position)


## 成长单例同样用运行期查找：--script 单元测试里没有自动加载。
func _run_progress() -> Node:
	return get_node_or_null("/root/RunProgress")


func _progress_value(key: String) -> float:
	var progress: Node = _run_progress()
	if progress == null:
		return 0.0
	var key_name: StringName = StringName(key)
	match key_name:
		UpgradePool.KEY_MAX_HEALTH_ADD:
			return progress.max_health_add()
		UpgradePool.KEY_DEFENSE_ADD:
			return progress.defense_add()
		UpgradePool.KEY_PICKUP_ADD:
			return progress.pickup_radius_add()
	return 0.0


func _update_facing() -> void:
	if weapon_controller.is_attacking():
		sprite.flip_h = weapon_controller.locked_aim().x < 0.0
	elif absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0.0
