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

@export var animation_tree:AnimationTree;

var input_direction: Vector2

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
##造成的伤害倍率：1.0 表示正常，攻击类 buff 会改它（武器结算时乘算）
var damage_dealt: float = 1.0
##吸血比例：造成伤害时按这个比例回血（0 = 不吸血）
var lifesteal: float = 0.0
##暴击率加成：0 表示不加成，暴怒 buff 会提高它（武器结算时叠加）
var crit_chance: float = 0.0
##武器伤害的固定加值：锋利附魔会提高它（武器结算时加在基础伤害上）
var damage_add: float = 0.0
##受到的回复量倍率：1.0 表示正常，祝福 buff 会提高它
var healing_received: float = 1.0
##攻击速度加成：0 表示正常，敏捷 buff 会提高它（出手阶段按 1+它 加快）
var attack_speed: float = 0.0

##闪避可用次数上限
@export var dodge_max_charges: int = 2
##恢复一次可用次数要多少秒（灵巧会缩短它）
@export var dodge_recharge_seconds: float = 3.0
##闪避位移速度(像素/秒)
@export var dodge_speed: float = 560.0
##闪避位移持续多久(秒)
@export var dodge_seconds: float = 0.18
##闪避的无敌帧时长(秒)
@export var dodge_invulnerable_seconds: float = 0.5

##当前可用闪避次数
var dodge_charges: int = 0
##充能进度：攒满 dodge_recharge_seconds 回一次
var _dodge_recharge: float = 0.0
##剩余闪避位移时间
var _dodge_left: float = 0.0
##剩余无敌帧时间
var _invulnerable_left: float = 0.0
##本次闪避方向
var _dodge_direction: Vector2 = Vector2.DOWN
##闪避充能速度加成：灵巧 buff 写回，速度 = 1 + 它
var dodge_recovery: float = 0.0

##闪避时要不要留残影
@export var dodge_afterimage_enabled: bool = true
##残影生成间隔(秒)
@export var dodge_afterimage_interval: float = 0.035
##残影淡出时长(秒)
@export var dodge_afterimage_fade: float = 0.22
##残影颜色（会再乘上角色自身的透明度）
@export var dodge_afterimage_tint: Color = Color(0.60, 0.85, 1.0, 0.55)
##残影生成计时
var _afterimage_timer: float = 0.0

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

## Boss control effects are kept separate from refreshing buff durations.
var fear_remaining: float = 0.0
var stun_remaining: float = 0.0
var boss_grappled: bool = false
var boss_captured: bool = false
var _stun_spin: float = 0.0


func _ready() -> void:
	health_component.died.connect(_on_health_died)
	health_component.health_changed.connect(_on_health_changed)
	health_component.max_health = max_health
	health_component.current_health = max_health
	dodge_charges = dodge_max_charges

	# 直接实例化 player.tscn 的场景（测试、编辑器单跑）可能没有背包，
	# 缺背包时跳过装备初始化，但成长仍然要应用。
	if inventory != null:
		inventory.handy_selection_changed.connect(handy_item_changed)
		inventory._init()
		handy_item_changed()

	apply_progress(true)

## 生命上限：等级自带的成长(每级 +7%，加算)只乘基础生命，
## 升级卡的固定值(体质 +15 / 孤注 -25)在上层直接加减，不被等级放大。
var max_health: float:
	get:
		return maxf(base_max_health * _level_growth_mult() + _progress_value("max_health_add"), 1.0)
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
## rebuild 为假时只同步生命与减伤，不重造武器：升级本身不改武器定义
## （等级成长是在命中结算时读倍率的），而重造会 cancel_attack()，
## 一刀砍到一半升级就白砍了。
func apply_progress(fill: bool = false, rebuild: bool = true) -> void:
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
	if rebuild:
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


## 当前选中格对应的基础武器定义（模板或附魔实例，未被升级卡叠改）。
func _base_weapon() -> WeaponDefinition:
	if inventory == null:
		return null
	var data: ItemData = inventory.get_item_template(handy_item)
	if data == null or not (data is WeaponData):
		return null
	return (data as WeaponData).weapon


func _physics_process(delta: float) -> void:
	weapon_controller.set_aim(get_global_mouse_position() - global_position)
	#挥武器会显形（隐身 buff 不消失，动作停下就恢复）
	if weapon_controller.is_attacking():
		reveal_by_action()
	_tick_progress(delta)
	_tick_dodge(delta)
	_tick_boss_status(delta)
	if health <= 0.0:
		velocity = Vector2.ZERO
		weapon_controller.cancel_attack()
		return
	if stunned or stun_remaining > 0.0 or boss_captured or boss_grappled:
		input_direction = Vector2.ZERO
		velocity = Vector2.ZERO
		if stunned or stun_remaining > 0.0 or boss_captured:
			weapon_controller.cancel_attack()
		return
	input_direction = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	if is_dodging():
		velocity = _dodge_direction * dodge_speed
		_integrate_movement(delta)
		_update_facing()
		return
	if fear_remaining > 0.0:
		input_direction = -input_direction
	_apply_input(delta)
	_integrate_movement(delta)
	_update_facing()


func apply_fear(seconds: float) -> void:
	fear_remaining += maxf(seconds, 0.0)


func apply_boss_stun(seconds: float) -> void:
	if seconds <= 0.0 or health <= 0.0:
		return
	_interrupt_dodge_for_boss()
	stun_remaining = maxf(stun_remaining, seconds)
	weapon_controller.cancel_attack()
	input_direction = Vector2.ZERO
	velocity = Vector2.ZERO
	queue_redraw()


func set_boss_grappled(active: bool) -> void:
	boss_grappled = active
	if active:
		_interrupt_dodge_for_boss()
		input_direction = Vector2.ZERO
		velocity = Vector2.ZERO


func set_boss_captured(active: bool) -> void:
	boss_captured = active
	if active:
		_interrupt_dodge_for_boss()
		weapon_controller.cancel_attack()
		input_direction = Vector2.ZERO
		velocity = Vector2.ZERO


func _interrupt_dodge_for_boss() -> void:
	if _dodge_left <= 0.0 and _invulnerable_left <= 0.0:
		return
	_dodge_left = 0.0
	_invulnerable_left = 0.0
	if is_instance_valid(health_component):
		health_component.invulnerable = false


func move_by_boss_pull(target: Vector2, distance: float) -> bool:
	if not boss_grappled or health <= 0.0:
		return false
	var destination: Vector2 = global_position.move_toward(target, maxf(distance, 0.0))
	if not can_stand_at(destination):
		return false
	global_position = destination
	return true


func _tick_boss_status(delta: float) -> void:
	fear_remaining = maxf(fear_remaining - delta, 0.0)
	if stun_remaining > 0.0:
		stun_remaining = maxf(stun_remaining - delta, 0.0)
		_stun_spin += delta * 4.0
		queue_redraw()


func _reset_boss_status() -> void:
	_interrupt_dodge_for_boss()
	fear_remaining = 0.0
	stun_remaining = 0.0
	boss_grappled = false
	boss_captured = false
	if is_instance_valid(sprite):
		sprite.position.y = 0.0
	queue_redraw()


func _draw() -> void:
	if stun_remaining <= 0.0:
		return
	var center := Vector2(0.0, -22.0)
	draw_arc(center, 10.0, _stun_spin, _stun_spin + PI * 1.3, 28, Color(1.0, 0.8, 0.29, 0.95), 2.0)
	draw_arc(center, 14.0, _stun_spin + PI, _stun_spin + PI * 2.2, 28, Color(0.6, 0.88, 1.0, 0.9), 2.0)


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
	if stunned or stun_remaining > 0.0 or boss_captured or (boss_grappled and event.is_action_pressed("throw")):
		if event.is_action_pressed("attack") or event.is_action_pressed("throw"):
			get_viewport().set_input_as_handled()
		return
	if health > 0.0:
		if event.is_action_pressed("attack"):
			#选中物品左键使用
			if is_ui_blocking():
				return

			inventory.left_use_handy_slot(self)
			reveal_by_action()
			weapon_controller.set_trigger_pressed(true)
			get_viewport().set_input_as_handled()
			return
		
		elif event.is_action_pressed("throw"):
			#选中物品右键使用
			if is_ui_blocking():
				return

			inventory.right_use_handy_slot(self)
			reveal_by_action()
			get_viewport().set_input_as_handled()
			return
		
		elif event.is_action_pressed("dodge"):
			if is_ui_blocking():
				return

			if try_dodge(input_direction):
				get_viewport().set_input_as_handled()
			return

func handy_item_changed()->void:
	handy_item = inventory.get_handy_slot_id(inventory.get_selected_handy())

	#附魔过的武器是运行时实例(id 400+)，这里按类型判断，不再靠 id 段
	var data:ItemData = inventory.get_item_template(handy_item)

	if data is WeaponData:
		rebuild_weapon()
	else:
		weapon_controller.equip(null)


##背包变化后同步手上这把：选中格换成了别的物品（拖拽、附魔把武器换成实例、用完）
##就重新装备。只在格子里的 id 真的变了才动作，避免捡个材料也把正在挥的攻击打断。
func _sync_handy_item() ->void:
	if inventory.get_handy_slot_id(inventory.get_selected_handy()) != handy_item:
		handy_item_changed()

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

#动画树更新
func _update_blend_position(directionVector:Vector2):
	animation_tree.set("parameters/StateMachine/Stand/blend_position",directionVector);
	animation_tree.set("parameters/StateMachine/Walk/blend_position",directionVector);
	animation_tree.set("parameters/StateMachine/Die/blend_position",directionVector);


## 有输入时朝目标速度加速，松手后按摩擦力减速到 0。
func _apply_input(delta: float) -> void:
	if input_direction != Vector2.ZERO:
		var target_velocity: Vector2 = input_direction * _move_speed()
		velocity = velocity.move_toward(target_velocity, acceleration * delta)

		_update_blend_position(input_direction)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


##是否在闪避位移中
func is_dodging() -> bool:
	return _dodge_left > 0.0


##是否处于无敌帧
func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


##还有没有可用闪避次数
func can_dodge() -> bool:
	return health > 0.0 and dodge_charges > 0 and not stunned and stun_remaining <= 0.0 and not boss_grappled and not boss_captured


##可用次数比例（0~1），给以后做 HUD 用
func dodge_charges_ratio() -> float:
	return float(dodge_charges) / float(maxi(dodge_max_charges, 1))


##当前充能进度（0~1）：满次数时为 1，给闪避次数 UI 画恢复弧用
func dodge_recharge_ratio() -> float:
	if dodge_charges >= dodge_max_charges:
		return 1.0
	return clampf(_dodge_recharge / maxf(dodge_recharge_seconds, 0.01), 0.0, 1.0)


##闪避充能速度加成：灵巧 buff 写回 dodge_recovery
func dodge_recovery_speed() -> float:
	return 1.0 + maxf(dodge_recovery, 0.0)


##尝试闪避：有次数就朝 direction（没输入时用当前输入/上次朝向）位移，并进入无敌帧
func try_dodge(direction: Vector2 = Vector2.ZERO) -> bool:
	if not can_dodge():
		return false

	var dir: Vector2 = direction

	if dir.is_zero_approx():
		dir = input_direction
	if dir.is_zero_approx():
		dir = _dodge_direction
	if dir.is_zero_approx():
		dir = Vector2.DOWN

	_dodge_direction = dir.normalized()
	_dodge_left = maxf(dodge_seconds, 0.01)
	_invulnerable_left = maxf(dodge_invulnerable_seconds, _dodge_left)
	dodge_charges = maxi(dodge_charges - 1, 0)
	if is_instance_valid(health_component):
		health_component.invulnerable = true
	velocity = _dodge_direction * dodge_speed

	return true


##闪避计时：无敌帧、位移时间、以及可用次数的充能
func _tick_dodge(delta: float) -> void:
	if _invulnerable_left > 0.0:
		_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
		if _invulnerable_left <= 0.0 and is_instance_valid(health_component):
			health_component.invulnerable = false
	if _dodge_left > 0.0:
		_dodge_left = maxf(_dodge_left - delta, 0.0)
		if dodge_afterimage_enabled:
			_afterimage_timer -= delta
			if _afterimage_timer <= 0.0:
				_afterimage_timer = maxf(dodge_afterimage_interval, 0.01)
				_spawn_afterimage()
	if dodge_charges < dodge_max_charges:
		_dodge_recharge += delta * dodge_recovery_speed()
		while _dodge_recharge >= dodge_recharge_seconds and dodge_charges < dodge_max_charges:
			_dodge_recharge -= maxf(dodge_recharge_seconds, 0.01)
			dodge_charges += 1
		if dodge_charges >= dodge_max_charges:
			_dodge_recharge = 0.0


##闪避残影：复制角色当前帧留一张影子，稍后淡出
func _spawn_afterimage() -> void:
	if sprite == null or not is_instance_valid(sprite) or get_parent() == null:
		return

	var ghost: DodgeAfterimage = DodgeAfterimage.new()

	ghost.texture = sprite.texture
	ghost.hframes = sprite.hframes
	ghost.vframes = sprite.vframes
	ghost.frame = sprite.frame
	ghost.flip_h = sprite.flip_h
	ghost.offset = sprite.offset
	ghost.scale = sprite.scale
	#和角色同层：设成 -1 会被画到地面 tile 底下，完全看不见
	ghost.z_index = sprite.z_index
	ghost.modulate = Color(dodge_afterimage_tint.r, dodge_afterimage_tint.g,
			dodge_afterimage_tint.b, dodge_afterimage_tint.a * clampf(modulate.a, 0.0, 1.0))
	get_parent().add_child(ghost)
	ghost.global_position = sprite.global_position
	ghost.fade(dodge_afterimage_fade)

#武器动画修改
func _update_facing() -> void:
	if weapon_controller.is_attacking():
		var direction_vector = get_global_mouse_position() - global_position
		_update_blend_position(direction_vector)

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
	_reset_boss_status()
	terrain_source = source
	active_map = map_spec
	velocity = Vector2.ZERO
	global_position = world_position
	_cached_tile = Vector2i(2147483647, 2147483647)
	if reset_health:
		_was_defeated = false
		health_component.invulnerable = false
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
		&"damage_dealt":
			return damage_dealt
		&"lifesteal":
			return lifesteal
		&"crit_chance":
			return crit_chance
		&"damage_add":
			return damage_add
		&"healing_received":
			return healing_received
		&"attack_speed":
			return attack_speed
		&"dodge_recovery":
			return dodge_recovery
		&"dodge_max_charges":
			return float(dodge_max_charges)
		&"max_health":
			return base_max_health
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
		&"damage_dealt":
			damage_dealt = value
		&"lifesteal":
			lifesteal = value
		&"crit_chance":
			crit_chance = value
		&"damage_add":
			damage_add = value
		&"healing_received":
			healing_received = value
		&"attack_speed":
			attack_speed = value
		&"dodge_recovery":
			dodge_recovery = value
		&"dodge_max_charges":
			#闪避次数上限：上限提高时立刻补上多出来的次数，上限回落时把当前次数压回上限
			var new_max: int = maxi(int(round(value)), 1)
			if new_max > dodge_max_charges:
				dodge_charges += new_max - dodge_max_charges
			dodge_max_charges = new_max
			dodge_charges = clampi(dodge_charges, 0, dodge_max_charges)
		&"max_health":
			#临时上限：只抬高容器，不回血；上限变小时把当前生命压回上限
			base_max_health = maxf(value, 1.0)
			if is_instance_valid(health_component):
				health_component.max_health = max_health
				if health > max_health:
					health = max_health


##当前是否处于隐身状态
var invisible: bool = false
##是否被硬控（冰冻/眩晕）
var stunned: bool = false


##BuffHolder 通知标记类效果（隐身、硬控）
func set_buff_flag(flag: StringName, active: bool) -> void:
	if flag == Buffs.FLAG_STUNNED:
		stunned = active
		return
	if flag != Buffs.FLAG_INVISIBLE:
		return
	invisible = active
	modulate.a = Buffs.INVISIBLE_ALPHA if active else 1.0


func is_invisible() -> bool:
	return invisible


##出手（用道具/挥武器）会显形：隐身 buff 不消失，动作结束就恢复
func reveal_by_action() -> void:
	var holder: BuffHolder = Buffs.holder_of(self)

	if holder != null:
		holder.reveal_by_action()


## 受到伤害：先过 buff 的倍率、升级卡的倍率与固定减伤，再交给生命组件。
## source 是攻击者（可为空），供吸血、荆棘这类需要追溯来源的结算使用。
func take_damage(amount: float, source: Node = null) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	if is_invulnerable():
		return
	var scaled: float = _incoming_damage(amount)
	if scaled <= 0.0:
		return
	_play_sfx(&"player_hurt", global_position)
	_combat_lockout = REGEN_COMBAT_LOCKOUT
	_combo_targets.clear()
	_combo_timers.clear()
	var hit: CombatHit = CombatHit.new()
	if source is Node2D:
		hit.source = source as Node2D
	else:
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


## 药水效果强度倍率（等级成长 + 药材学）。
## 药水结算时把它设进 Buffs.set_next_power_scale()，具体覆盖范围见 docs/run_progression.md。
## 治疗量不用它重复乘：PlayerCharacter.heal() 里已经乘过一次。
func potion_power_mult() -> float:
	var progress: Node = _run_progress()
	return progress.alchemy_power_mult() if progress != null else 1.0


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
	_reset_boss_status()
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


## 等级自带的生命上限倍率（1级 = 1.0，之后每级 +7%，加算不叠乘）。
## 取不到成长单例时按 1.0，保证单跑玩家场景时生命上限还是 100。
func _level_growth_mult() -> float:
	var progress: Node = _run_progress()
	if progress == null:
		return 1.0
	return float(progress.max_health_mult())
