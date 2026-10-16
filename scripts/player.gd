class_name PlayerCharacter
extends CharacterBody2D

signal health_changed(current: float, maximum: float)
signal defeated
#荆棘之类的反伤监听这个信号
signal damaged(hit: CombatHit, actual_damage: float)


## 主角占位实现：WASD / 方向键控制，速度带加速度与摩擦力，摄像机跟随。
##
## 地形阻挡不依赖物理层，而是直接问 WorldGenerator 这一格是什么地形。
## 生成器是纯函数式的（只由种子和坐标决定），所以判定结果和画面上看到的永远一致，
## 不需要等区块加载完。

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
@export var max_health: int = 10

@onready var sprite: Sprite2D = $Sprite2D
@onready var weapon_controller: WeaponController = $WeaponController

@export_group("背包")
@export var inventory:Inventory

#玩家所持物品id
var handy_item:int

## 地形来源，由 GameWorld 注入。
var terrain_source: WorldGenerator = null
## 当前箱庭的矩形通行边界，出口由 GameWorld 瞬切。
var active_map: MapSpec = null
var health: float = 10.0

##受到的伤害倍率：1.0 表示正常，减伤类 buff 会把它调小
var damage_taken: float = 1.0
##防御：直接减伤，含义与怪物 HealthComponent.defense 一致
var defense: float = 0.0
##造成的伤害倍率：1.0 表示正常，攻击类 buff 会改它（武器结算时乘算）
var damage_dealt: float = 1.0
##吸血比例：造成伤害时按这个比例回血（0 = 不吸血）
var lifesteal: float = 0.0

# 上一个查过的格子。主角一帧最多查两次，缓存一下省掉重复的噪声计算
var _cached_tile: Vector2i = Vector2i(2147483647, 2147483647)
var _cached_walkable: bool = true


func _ready() -> void:
	health = float(max_health)
	health_changed.emit(health, float(max_health))

	inventory.handy_selection_changed.connect(handy_item_changed)
	inventory._init()
	handy_item_changed()

func _physics_process(delta: float) -> void:
	weapon_controller.set_aim(get_global_mouse_position() - global_position)
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
	#攻击动作期间持续显形：动作一停，隐身立刻恢复（buff 不会消失）
	if weapon_controller != null and weapon_controller.is_attacking():
		reveal_by_action()


func _unhandled_input(event: InputEvent) -> void:
	if health > 0.0:
		if event.is_action_pressed("attack"):
			#选中物品左键使用
			if is_ui_blocking():
				return

			inventory.left_use_handy_slot(self)
			weapon_controller.set_trigger_pressed(true)
			reveal_by_action()
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
		


func handy_item_changed()->void:
	handy_item = inventory.get_handy_slot_id(inventory.get_selected_handy())

	if handy_item >=200&&handy_item<300:
		weapon_controller.equip((inventory.get_item_data[handy_item] as WeaponData).weapon)
	else:
		weapon_controller.equip(null)
##ui是否挡着世界操作
func is_ui_blocking() -> bool:

	var hud:Node = get_tree().get_first_node_in_group("game_hud")

	if hud == null:
		return false

	for panel_name:String in ["BagUi", "Alchemy"]:
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
		var target_velocity: Vector2 = input_direction * max_speed
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


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
		health = float(max_health)
		health_changed.emit(health, float(max_health))


##BuffHolder 读当前属性值（认基准用）
func read_stat(stat: StringName) -> float:
	match stat:
		&"move_speed":
			return max_speed
		&"defense":
			return defense
		&"damage_taken":
			return damage_taken
		&"damage_dealt":
			return damage_dealt
		&"lifesteal":
			return lifesteal
		&"max_health":
			return float(max_health)
	return 0.0


##BuffHolder 把算好的值写回属性
func apply_stat(stat: StringName, value: float) -> void:
	match stat:
		&"move_speed":
			max_speed = value
		&"defense":
			defense = value
		&"damage_taken":
			damage_taken = value
		&"damage_dealt":
			damage_dealt = value
		&"lifesteal":
			lifesteal = value
		&"max_health":
			#临时上限：只抬高容器，不回血；上限变小时把当前生命压回上限
			max_health = maxi(int(round(value)), 1)
			health = minf(health, float(max_health))
			health_changed.emit(health, float(max_health))


##当前是否处于隐身状态
var invisible: bool = false


##BuffHolder 通知标记类效果(目前只给隐身使用)
func set_buff_flag(flag: StringName, active: bool) -> void:
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


##持续恢复之类的定时效果走这里
func heal(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = minf(health + amount, float(max_health))
	health_changed.emit(health, float(max_health))


##和怪物 CombatHurtbox 一样收到一次命中；复用传入的 CombatHit，所以反伤深度等 metadata 不会丢
func receive_hit(hit: CombatHit) -> bool:
	if hit == null or hit.damage <= 0.0 or health <= 0.0:
		return false
	var mitigated: float = maxf(hit.damage * damage_taken - defense, 0.0)


	if Buffs.is_absorbing(self):
		heal(mitigated)
		return false

	if mitigated <= 0.0:
		return false
	hit.damage = mitigated
	_apply_hit(hit)

	return true


##受伤入口：source 是攻击者，可为空（燃烧/毒之类没有来源）
func take_damage(amount: float, source: Node = null) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	#先过 buff 的减伤倍率与防御，再扣血
	var mitigated: float = maxf(amount * damage_taken - defense, 0.0)

	if Buffs.is_absorbing(self):
		heal(mitigated)
		return

	if mitigated <= 0.0:
		return
	var hit: CombatHit = CombatHit.new()

	hit.damage = mitigated
	hit.position = global_position
	if source is Node2D:
		hit.source = source as Node2D
	_apply_hit(hit)


##真正扣血：两条入口都走这里，保证只有一条结算路径
func _apply_hit(hit: CombatHit) -> void:
	var amount: float = hit.damage

	_play_sfx(&"player_hurt", global_position)
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, float(max_health))
	damaged.emit(hit, amount)
	Buffs.apply_lifesteal(hit.source, amount)
	_notify("受到 %s 点伤害，剩余生命 %s/%s" % [str(amount), str(health), str(max_health)])
	if health <= 0.0:
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


func _update_facing() -> void:
	if weapon_controller.is_attacking():
		sprite.flip_h = weapon_controller.locked_aim().x < 0.0
	elif absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0.0
