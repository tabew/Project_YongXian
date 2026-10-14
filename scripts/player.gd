class_name PlayerCharacter
extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal defeated

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

@export_group("武器")
## 按顺序循环装备；添加资源即可扩充，无需按武器类型分支。
@export var weapon_loadout: Array[WeaponDefinition] = []

@export_group("生命")
@export var max_health: int = 10

@onready var sprite: Sprite2D = $Sprite2D
@onready var weapon_controller: WeaponController = $WeaponController
@onready var alchemy_station: AlchemyStation = $AlchemyStation

@export_group("背包")
@export var inventory:Inventory
## 地形来源，由 GameWorld 注入。
var terrain_source: WorldGenerator = null
## 当前箱庭的矩形通行边界，出口由 GameWorld 瞬切。
var active_map: MapSpec = null
var health: int = 10
## 炼金无敌剩余时间（秒）：升级「炼金无敌」在炼金瞬间给一段免疫。
var invulnerable_remaining: float = 0.0

# 上一个查过的格子。主角一帧最多查两次，缓存一下省掉重复的噪声计算
var _cached_tile: Vector2i = Vector2i(2147483647, 2147483647)
var _cached_walkable: bool = true
## 过载时武器冒的黑烟。
var _weapon_smoke: CPUParticles2D = null
## 替换爆发 / 词条反应 / 过载爆炸的表现层。
var _alchemy_vfx: AlchemyVfx = null


func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)
	install_weapon_catalog()
	alchemy_station.overloaded.connect(_on_alchemy_overloaded)
	alchemy_station.self_damage.connect(_on_alchemy_self_damage)
	alchemy_station.combo_replaced.connect(_on_combo_replaced)
	alchemy_station.combo_activated.connect(_on_alchemy_combo_activated)
	alchemy_station.combo_stacked.connect(_on_alchemy_combo_stacked)
	alchemy_station.split_ready.connect(_on_split_ready)
	_build_weapon_smoke()
	_build_alchemy_vfx()


## 击杀回调：由 GameWorld 在怪物死亡时调用。
## 一次击杀同时驱动三件事：热量加速冷却、活体 V 分裂、灵魂词条生成游魂。
func on_monster_killed(position: Vector2) -> void:
	alchemy_station.register_kill()
	_spawn_summons(alchemy_station.kill_summons(), position)


## 活体 V 分裂：分裂出与武器伤害成比例、寿命有限的分身。
func _on_split_ready(count: int) -> void:
	if count <= 0:
		return
	var specs: Array[Dictionary] = [{
		"count": count,
		"chance": 1.0,
		"duration": alchemy_station.living_split_duration(),
		"explode": false,
		"flavor": &"split",
		"damage_ratio": alchemy_station.living_split_damage_ratio(),
	}]
	_spawn_summons(specs, global_position)


## 按来源表生成召唤物：命中触发（召唤 / 骨 V）与击杀触发（灵魂 / 活体分身）共用。
func _spawn_summons(specs: Array[Dictionary], origin: Vector2) -> void:
	if specs.is_empty():
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var rng: RandomNumberGenerator = MapRng.shared(MapRng.Stream.COMBAT)
	var equipped: WeaponDefinition = weapon_controller.equipped_weapon
	var base_damage: float = equipped.damage if equipped != null else 0.0
	for spec: Dictionary in specs:
		if rng.randf() >= float(spec.get("chance", 0.0)):
			continue
		var count: int = maxi(int(spec.get("count", 1)), 1)
		var ratio: float = float(spec.get("damage_ratio", AlchemyRules.SUMMON_DAMAGE_RATIO))
		for index: int in range(count):
			var summon: AlchemySummon = AlchemySummon.new()
			summon.damage = base_damage * alchemy_station.combo_power() * ratio
			summon.lifetime = float(spec.get("duration", 5.0))
			summon.explodes = bool(spec.get("explode", false))
			summon.tint = AlchemyHitEffects.flavor_color(StringName(spec.get("flavor", &"summon")))
			summon.owner_actor = self
			parent.add_child(summon)
			var offset: float = float(index) * 14.0 - float(count - 1) * 7.0
			summon.global_position = origin + Vector2(offset, -8.0)


## 把配置表里的扩展武器并入武器轮换列表；重复调用不会重复添加。
func install_weapon_catalog() -> int:
	var added: int = 0
	for definition: WeaponDefinition in WeaponCatalog.all_definitions():
		var exists: bool = false
		for equipped: WeaponDefinition in weapon_loadout:
			if equipped != null and equipped.id == definition.id:
				exists = true
				break
		if not exists:
			weapon_loadout.append(definition)
			added += 1
	return added


func _physics_process(delta: float) -> void:
	weapon_controller.set_aim(get_global_mouse_position() - global_position)
	alchemy_station.in_combat = _has_living_monsters()
	weapon_controller.damage_multiplier = alchemy_station.combo_power()
	weapon_controller.critical_chance_bonus = alchemy_station.crit_bonus()
	weapon_controller.hit_effects = alchemy_station.hit_effects()
	invulnerable_remaining = maxf(invulnerable_remaining - delta, 0.0)
	if _weapon_smoke != null:
		_weapon_smoke.emitting = weapon_controller.is_disabled()
	if health <= 0:
		velocity = Vector2.ZERO
		weapon_controller.cancel_attack()
		return
	var input_direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	_apply_input(input_direction, delta)
	_integrate_movement(delta)
	_update_facing()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		weapon_controller.set_trigger_pressed(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_weapon"):
		equip_next_weapon()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("alchemy_brew") and not event.is_echo():
		alchemy_station.press_brew()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("alchemy_cancel") and not event.is_echo():
		if alchemy_station.cancel():
			get_viewport().set_input_as_handled()


func equip_next_weapon() -> bool:
	var current_index: int = weapon_loadout.find(weapon_controller.equipped_weapon)
	for offset: int in range(1, weapon_loadout.size() + 1):
		var candidate: WeaponDefinition = weapon_loadout[(current_index + offset) % weapon_loadout.size()]
		if candidate != null and candidate != weapon_controller.equipped_weapon:
			if weapon_controller.equip(candidate):
				return true
	return false


func _input(event: InputEvent) -> void:
	# Release must also reach us when a UI control consumes the event.
	if event.is_action_released("attack"):
		weapon_controller.set_trigger_pressed(false)
	if event.is_action_released("alchemy_brew"):
		alchemy_station.release_brew()
	if event.is_action_pressed("alchemy_cancel") and not event.is_echo():
		if alchemy_station.cancel():
			get_viewport().set_input_as_handled()


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
		health = max_health
		health_changed.emit(health, max_health)


func take_damage(amount: int) -> void:
	if amount <= 0 or health <= 0 or invulnerable_remaining > 0.0:
		return
	if is_instance_valid(alchemy_station):
		alchemy_station.interrupt()
	_play_sfx(&"player_hurt", global_position)
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	_notify("受到 %d 点伤害，剩余生命 %d/%d" % [amount, health, max_health])
	if health == 0:
		velocity = Vector2.ZERO
		_play_sfx(&"player_defeat")
		defeated.emit()
		_notify("生命归零")


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载（与 _notify 的 EventBus 一致）。
func _play_sfx(id: StringName, position: Vector2 = Vector2.INF) -> void:
	var manager: Node = get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.call("play_sfx", id, position)


func _notify(message: String) -> void:
	var event_bus: Node = get_node_or_null("/root/EventBus")
	if event_bus != null and event_bus.has_signal("notification"):
		event_bus.emit_signal("notification", message)

## 地图里还有活着的怪物时视为战斗状态；战斗中 E 走短按 / 长按，非战斗打开完整炼金台。
func _has_living_monsters() -> bool:
	for monster: Node in get_tree().get_nodes_in_group("monsters"):
		if monster.is_queued_for_deletion():
			continue
		return true
	return false

## 过载：武器失效 8 秒、自伤 15，爆炸范围伤害由世界层用 report 表现。
func _on_alchemy_overloaded(report: Dictionary) -> void:
	weapon_controller.set_disabled(float(report.get("weapon_disable", AlchemyRules.OVERLOAD_WEAPON_DISABLE)))
	var self_damage_amount: int = int(report.get("self_damage", AlchemyRules.OVERLOAD_SELF_DAMAGE))
	if self_damage_amount > 0:
		take_damage(self_damage_amount)
	_apply_overload_blast(report)
	_notify("炼金过载！武器失效，材料损失一半")


## 过载爆炸：半径内的敌人吃固定伤害（半径按格换算成像素）。
func _apply_overload_blast(report: Dictionary) -> void:
	var radius: float = float(report.get("blast_radius", AlchemyRules.OVERLOAD_BLAST_RADIUS)) * float(WorldGenerator.TILE_SIZE)
	if _alchemy_vfx != null:
		_alchemy_vfx.overload_blast(radius)
	var damage: int = int(report.get("blast_damage", AlchemyRules.OVERLOAD_BLAST_DAMAGE))
	if damage <= 0:
		return
	for node: Node in get_tree().get_nodes_in_group("monsters"):
		var monster: Node2D = node as Node2D
		if monster == null or monster.is_queued_for_deletion():
			continue
		if global_position.distance_to(monster.global_position) > radius:
			continue
		if monster.has_method("take_damage"):
			monster.call("take_damage", damage)


## 替换爆发：换新组合时旧效果以 50% 强度爆发一次，并触发词条反应。
func _on_combo_replaced(previous: BrewCombo, burst_power: float, reactions: Array) -> void:
	if _alchemy_vfx != null:
		_alchemy_vfx.burst(previous, burst_power, reactions)
	_apply_replacement_burst(burst_power)


func _on_alchemy_combo_activated(_combo: BrewCombo) -> void:
	_grant_alchemy_invulnerability()


func _on_alchemy_combo_stacked(_combo: BrewCombo, _stacks: int) -> void:
	_grant_alchemy_invulnerability()


## 炼金无敌：升级「炼金无敌」给炼金瞬间一段免疫；已有更长免疫时不缩短。
func _grant_alchemy_invulnerability() -> void:
	if not is_instance_valid(alchemy_station):
		return
	invulnerable_remaining = maxf(invulnerable_remaining, alchemy_station.invuln_seconds())


## 替换爆发伤害：半径内敌人按爆发强度吃一次伤害（不返还材料、不返还旧时间）。
func _apply_replacement_burst(burst_power: float) -> void:
	var damage: int = roundi(burst_power * AlchemyRules.REPLACEMENT_BURST_BASE_DAMAGE)
	if damage <= 0:
		return
	var radius: float = AlchemyRules.REPLACEMENT_BURST_RADIUS_TILES * float(WorldGenerator.TILE_SIZE)
	for node: Node in get_tree().get_nodes_in_group("monsters"):
		var monster: Node2D = node as Node2D
		if monster == null or monster.is_queued_for_deletion():
			continue
		if global_position.distance_to(monster.global_position) > radius:
			continue
		if monster.has_method("take_damage"):
			monster.call("take_damage", damage)


func _build_alchemy_vfx() -> void:
	_alchemy_vfx = AlchemyVfx.new()
	_alchemy_vfx.name = "AlchemyVfx"
	add_child(_alchemy_vfx)


## 武器失效期间的「黑烟」：代码生成的柔边贴图，避免依赖美术资源。
func _build_weapon_smoke() -> void:
	_weapon_smoke = CPUParticles2D.new()
	_weapon_smoke.name = "WeaponSmoke"
	_weapon_smoke.emitting = false
	_weapon_smoke.amount = 18
	_weapon_smoke.lifetime = 0.9
	_weapon_smoke.texture = _make_smoke_texture()
	_weapon_smoke.position = Vector2(0, -6)
	_weapon_smoke.direction = Vector2(0, -1)
	_weapon_smoke.spread = 35.0
	_weapon_smoke.gravity = Vector2(0, -18)
	_weapon_smoke.initial_velocity_min = 10.0
	_weapon_smoke.initial_velocity_max = 24.0
	_weapon_smoke.scale_amount_min = 0.6
	_weapon_smoke.scale_amount_max = 1.4
	_weapon_smoke.color = Color(0.12, 0.12, 0.14, 0.85)
	add_child(_weapon_smoke)


static func _make_smoke_texture() -> ImageTexture:
	var size: int = 8
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center: float = float(size - 1) * 0.5
	for y: int in range(size):
		for x: int in range(size):
			var distance: float = Vector2(float(x), float(y)).distance_to(Vector2(center, center))
			var alpha: float = clampf(1.0 - distance / (center + 0.5), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * alpha))
	return ImageTexture.create_from_image(image)

func _on_alchemy_self_damage(amount: float) -> void:
	if amount > 0.0:
		take_damage(ceili(amount))

func _update_facing() -> void:
	if weapon_controller.is_attacking():
		sprite.flip_h = weapon_controller.locked_aim().x < 0.0
	elif absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0.0
