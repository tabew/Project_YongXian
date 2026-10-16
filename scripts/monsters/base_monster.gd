class_name BaseMonster
extends CharacterBody2D

## 只在真正死亡（含调试击杀）时发出；地图卸载不算击杀。
signal killed

var _death_committed: bool = false
var difficulty_entry: int = 1
var difficulty_multiplier: float = 1.0
var _difficulty_applied: bool = false
const SUPPLY_PATROL_RADIUS_TILES: float = 8.0
var has_supply_post: bool = false
var supply_post: Vector2 = Vector2.ZERO

## 所有怪物共用的模板：生命、受击、动画、感知/寻路原语，以及通用四状态 AI 的装配。
##
## AI 本体（状态机、配置、黑板、攻击接口）都在 scripts/monsters/ai/ 下，所有怪物共享同一套
## 逻辑：怪物只需要提供 EnemyAIConfig，并按需实现 EnemyAttack，不需要复制粘贴 AI 代码。
## 视线检测复用 RayCast2D（物理墙体）与程序化地形采样（当前没有物理层的阻挡格）。

@export_group("AI")
## 怪物类型的 AI 数据配置；留空时使用通用默认值。
@export var ai_config: EnemyAIConfig

@export_group("死亡掉落")
## 配置有效表后真正死亡必定掉一件；卸载/回收不调用死亡流程。
@export var death_loot: MonsterLootTable

@export_group("受击反馈")
## 基础反馈只产生约2像素位移；武器击退仍按强度加算，形成更明显的推开。
@export_range(0.0, 500.0, 1.0) var default_knockback_speed: float = 40.0
@export_range(0.01, 1.0, 0.01) var knockback_duration: float = 0.10
@export_range(0.01, 1.0, 0.01) var hit_flash_duration: float = 0.06

var _knockback_impulse: Vector2 = Vector2.ZERO
var _knockback_remaining: float = 0.0
var _knockback_applied_this_frame: bool = false
var _hit_flash_remaining: float = 0.0
## 定身减速的剩余时间与比例；0 表示未被减速。
var _slow_remaining: float = 0.0
var _slow_ratio: float = 0.0

@onready var target_raycast: RayCast2D = $TargetRayCast

var player: PlayerCharacter = null
var world_generator: WorldGenerator = null
var spawn_chunk: Vector2i = Vector2i.ZERO
var original_spawn_tile: Vector2i = Vector2i.ZERO
## 击杀基础经验，由 MonsterSpawner 按生成配置写入。
var experience_reward: int = 0

## 每个怪物独立的 AI 组件；共享的只有配置、感知服务、路径调度与事件总线。
var blackboard: EnemyBlackboard = null
var perception: EnemyPerception = null
var navigator: EnemyNavigator = null
var attack: EnemyAttack = null
var brain: EnemyBrain = null

var _pending_navigation_speed: float = -1.0
var _ai_config_owned: bool = false
var _animation_accumulator: float = 0.0
var _last_line_blocked_by_physics: bool = false
var _last_physics_collider: CollisionObject2D = null

## 移动速度统一存放在 ai_config.move_speed，保留 navigation_speed 作为兼容别名。
var navigation_speed: float:
	get:
		if ai_config != null:
			return ai_config.move_speed
		return _pending_navigation_speed if _pending_navigation_speed >= 0.0 else 72.0
	set(value):
		if ai_config != null:
			ai_config.move_speed = value
		else:
			_pending_navigation_speed = value


##BuffHolder 读当前属性值。速度借用 navigation_speed（底层是每只怪物独立的副本），
##所以 AI 自己改过导航速度后，holder 下一次重算会把这个改动认成新基准，不会踩掉它。
func read_stat(stat: StringName) -> float:
	var health_component: HealthComponent = get_node_or_null("Health") as HealthComponent

	match stat:
		&"move_speed":
			return navigation_speed
		&"defense":
			return health_component.defense if health_component != null else 0.0
		&"damage_taken":
			return health_component.damage_taken if health_component != null else 1.0
		&"damage_dealt":
			return outgoing_damage_multiplier
		&"lifesteal":
			return lifesteal
		&"max_health":
			return health_component.max_health if health_component != null else 0.0
	return 0.0


##BuffHolder 把算好的值写回属性
func apply_stat(stat: StringName, value: float) -> void:
	var health_component: HealthComponent = get_node_or_null("Health") as HealthComponent

	match stat:
		&"move_speed":
			navigation_speed = value
		&"defense":
			if health_component != null:
				health_component.defense = value
		&"damage_taken":
			if health_component != null:
				health_component.damage_taken = value
		&"damage_dealt":
			outgoing_damage_multiplier = value
		&"lifesteal":
			lifesteal = value
		&"max_health":
			if health_component != null:
				health_component.max_health = maxf(value, 1.0)
				health_component.current_health = minf(health_component.current_health, health_component.max_health)
				health_component.health_changed.emit(health_component.current_health, health_component.max_health)


##当前是否处于隐身状态
var invisible: bool = false
##buff 的攻击力倍率（1.0 = 正常），由 BuffHolder 写回
var outgoing_damage_multiplier: float = 1.0
##buff 的吸血比例（0 = 不吸血），由 BuffHolder 写回
var lifesteal: float = 0.0


##BuffHolder 通知标记类效果（隐身）
func set_buff_flag(flag: StringName, active: bool) -> void:
	if flag != Buffs.FLAG_INVISIBLE:
		return
	invisible = active
	modulate.a = Buffs.HIDDEN_ALPHA if active else 1.0


##感知用：隐身时看不见（EnemyPerception 会读这个）
func is_invisible() -> bool:
	return invisible


##出手（攻击/出手伤害）会显形
func reveal_by_action() -> void:
	var holder: BuffHolder = Buffs.holder_of(self)

	if holder != null:
		holder.reveal_by_action()


##攻击状态下持续显形：动作一停，隐身立刻恢复
func _update_invisibility_reveal() -> void:
	var holder: BuffHolder = Buffs.holder_of(self)

	if holder == null or not holder.has_flag(Buffs.FLAG_INVISIBLE):
		return
	if get_ai_state() == EnemyState.State.ATTACK:
		reveal_by_action()

## 共享占位动画轨道；子类可替换动画库和 Visual 下的外形。
var _visual_height: float = 0.0:
	set(value):
		_visual_height = value
		_update_visual_pose()
var visual_pose: Vector2 = Vector2.ZERO:
	set(value):
		visual_pose = value
		_update_visual_pose()
var visual_tint: Color = Color.WHITE:
	set(value):
		visual_tint = value
		_update_visual_pose()

## 由通用模板创建，使用各怪物自己的 HealthComponent。
var health_bar: ProgressBar = null
var animation_tree: AnimationTree = null
var animation_playback: AnimationNodeStateMachinePlayback = null


func _ready() -> void:
	add_to_group("monsters")
	target_raycast.add_exception(self)
	_setup_health_bar()
	_setup_animation()
	var health_component := get_node_or_null("Health") as HealthComponent
	if health_component != null:
		health_component.damaged.connect(_on_monster_damaged)
		health_component.died.connect(_on_monster_died)
	_ensure_ai_config()
	_build_ai()


func _physics_process(delta: float) -> void:
	advance_frame_animation(delta)
	_hit_flash_remaining = maxf(_hit_flash_remaining - delta, 0.0)
	_slow_remaining = maxf(_slow_remaining - delta, 0.0)
	_update_hit_flash()
	_update_invisibility_reveal()
	_knockback_applied_this_frame = _knockback_remaining > 0.0
	if _knockback_applied_this_frame:
		var step_time: float = minf(delta, _knockback_remaining)
		var strength: float = maxf(_knockback_remaining - step_time * 0.5, 0.0) / knockback_duration
		_move_knockback(_knockback_impulse * strength * step_time)
		_knockback_remaining = maxf(_knockback_remaining - delta, 0.0)
		# 击退期间不驱动 AI，避免覆盖位移；击退结束后重新寻路。
		if navigator != null:
			navigator.clear()
		return
	if brain != null:
		brain.tick(delta)


func _setup_animation() -> void:
	animation_tree = get_node_or_null("AnimationTree") as AnimationTree
	if animation_tree == null:
		return
	animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_tree.active = true
	animation_playback = animation_tree.get("parameters/playback")
	animation_playback.start(&"Idle")
	animation_tree.advance(0.0)


# --- AI 装配 ----------------------------------------------------------------

## 复制一份配置，避免多只怪物共享同一个 .tres 时互相污染运行时改动。
func _ensure_ai_config() -> void:
	if _ai_config_owned:
		return
	ai_config = ai_config.duplicate() as EnemyAIConfig if ai_config != null else EnemyAIConfig.new()
	if _pending_navigation_speed >= 0.0:
		ai_config.move_speed = _pending_navigation_speed
	_ai_config_owned = true


## 装配（或按最终位置重建）本怪物的 AI 组件。
func _build_ai() -> void:
	_ensure_ai_config()
	blackboard = EnemyBlackboard.new()
	blackboard.patrol_anchor = _resolve_patrol_anchor()
	perception = EnemyPerception.new()
	perception.setup(self, ai_config, blackboard)
	navigator = EnemyNavigator.new()
	navigator.setup(self, ai_config)
	attack = _create_attack()
	if attack != null:
		attack.setup(self, ai_config)
	brain = EnemyBrain.new()
	brain.setup(self, ai_config, blackboard, perception, navigator, attack, _ai_seed())


func set_supply_post(position: Vector2) -> void:
	has_supply_post = true
	supply_post = position
	ai_config.patrol_radius_tiles = SUPPLY_PATROL_RADIUS_TILES
	blackboard.patrol_anchor = position


func supply_patrol_allows(tile: Vector2i) -> bool:
	var radius: float = SUPPLY_PATROL_RADIUS_TILES * WorldGenerator.TILE_SIZE
	return not has_supply_post or WorldGenerator.tile_to_world(tile).distance_squared_to(supply_post) <= radius * radius


## 子类返回自己的攻击实现；默认没有攻击，怪物只会巡逻与追击。
func _create_attack() -> EnemyAttack:
	return null


## 初始巡逻锚点：场景中的 PatrolAnchor 节点，否则用出生点。
func _resolve_patrol_anchor() -> Vector2:
	var marker := get_node_or_null("PatrolAnchor") as Node2D
	if marker != null:
		return marker.global_position
	return global_position


## 用世界种子 + 生成位置做种，保证同一局存档/回放的巡逻与搜索点一致。
## 种子取自所在世界的生成器，避免直接引用 GameState 单例标识符。
func _ai_seed() -> int:
	var world_seed: int = world_generator.world_seed if world_generator != null else 0
	var tile: Vector2i = WorldGenerator.world_to_tile(global_position)
	return hash([
		world_seed,
		tile.x,
		tile.y,
		ai_config.ai_id,
		spawn_chunk.x,
		spawn_chunk.y,
	])


func get_ai_state() -> EnemyState.State:
	return brain.current_state() if brain != null else EnemyState.State.PATROL


func get_ai_state_name() -> String:
	return EnemyState.describe(get_ai_state())


func get_ai_config() -> EnemyAIConfig:
	return ai_config


func get_blackboard() -> EnemyBlackboard:
	return blackboard


func get_attack() -> EnemyAttack:
	return attack


func get_navigator() -> EnemyNavigator:
	return navigator


func get_attack_cooldown() -> float:
	return blackboard.attack_cooldown if blackboard != null else 0.0


func set_attack_cooldown(seconds: float) -> void:
	if blackboard != null:
		blackboard.attack_cooldown = maxf(seconds, 0.0)


func is_path_empty() -> bool:
	return navigator == null or not navigator.has_path()


## 兼容旧接口：现在的"仇恨"等价于状态机处于 Chase 或 Attack。
func has_player_aggro() -> bool:
	if blackboard == null:
		return false
	return (
		blackboard.state == EnemyState.State.CHASE
		or blackboard.state == EnemyState.State.ATTACK
	)


## 兼容旧接口：外部脚本可强制放弃目标，怪物以当前位置为锚点回到巡逻。
func clear_player_aggro() -> void:
	if brain != null:
		brain.abandon_target()


## 通过 /root 路径取共享的自动加载服务。不直接写单例标识符，
## 保证怪物脚本在 `--script` 模式下也能编译（那时自动加载标识符不可解析）。
func shared_service(service_name: StringName) -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null(NodePath("/root/%s" % service_name))


## PerceptionManager 调用的统一感知入口。
func evaluate_perception() -> void:
	if perception == null or blackboard == null:
		return
	blackboard.can_see_target = perception.can_see(player)
	blackboard.target = player if blackboard.can_see_target else null
	if not is_instance_valid(player):
		blackboard.target_distance = 0.0
		return
	blackboard.target_distance = global_position.distance_to(player.global_position)
	if blackboard.can_see_target:
		blackboard.last_known_position = player.global_position
		blackboard.has_last_known_position = true
		blackboard.lose_sight_elapsed = 0.0


## PerceptionManager 广播噪音/警报时调用。
func report_suspicious(position: Vector2) -> void:
	if perception != null:
		perception.report_suspicious(position)


func ai_hearing_radius() -> float:
	return perception.hearing_radius() if perception != null else 0.0


## 最近一次视线检测被物理墙体挡住时，把它转换成 AStar 的格阻挡。
func blocked_physics_tiles() -> Dictionary:
	if _last_line_blocked_by_physics and is_instance_valid(_last_physics_collider):
		return EnemyPathfinder.physics_collider_tiles(_last_physics_collider)
	return {}


## PathRequestScheduler 的异步回调入口。
func _on_ai_path_ready(result: Array[Vector2i], request_generation: int) -> void:
	if navigator != null:
		navigator.apply_path(request_generation, result)


## 子类调用 super._physics_process() 后应优先处理这一状态，避免 AI 覆盖击退。
func is_receiving_knockback() -> bool:
	return _knockback_remaining > 0.0 or _knockback_applied_this_frame


func is_distance_sleep_blocked() -> bool:
	return not is_zero_approx(_visual_height)


func apply_difficulty(entry: int) -> void:
	if _difficulty_applied:
		return
	_difficulty_applied = true
	difficulty_entry = maxi(entry, 1)
	difficulty_multiplier = MonsterDifficulty.multiplier_for_entry(difficulty_entry)
	var health := get_node_or_null("Health") as HealthComponent
	if health != null and not is_equal_approx(difficulty_multiplier, 1.0):
		health.max_health *= difficulty_multiplier
		health.current_health = health.max_health
		health.health_changed.emit(health.current_health, health.max_health)


func outgoing_damage(base_damage: float) -> float:
	#隐身现形
	reveal_by_action()

	return base_damage * difficulty_multiplier * outgoing_damage_multiplier



# --- 受击反馈 ---------------------------------------------------------------

func _update_hit_flash() -> void:
	var visual := get_node_or_null("Visual") as CanvasItem
	if visual != null and visual.material is ShaderMaterial:
		(visual.material as ShaderMaterial).set_shader_parameter("hit_flash", 1.0 if _hit_flash_remaining > 0.0 else 0.0)


func _resolve_knockback(hit: CombatHit) -> Vector2:
	if not hit.knockback.is_zero_approx():
		# 同方向加算：武器击退强度 + 模板基础击退强度。
		return hit.knockback + hit.knockback.normalized() * default_knockback_speed
	var direction: Vector2 = Vector2.ZERO
	if is_instance_valid(hit.source) and hit.source != self:
		direction = hit.source.global_position.direction_to(global_position)
	if direction.is_zero_approx() and not hit.position.is_equal_approx(global_position):
		direction = hit.position.direction_to(global_position)
	if direction.is_zero_approx() and is_instance_valid(player):
		direction = player.global_position.direction_to(global_position)
	if direction.is_zero_approx():
		direction = Vector2.UP
	return direction * default_knockback_speed


func _move_knockback(motion: Vector2) -> void:
	# 小步检查程序化地形，再让物理引擎扫掠身体，不能被击退穿过墙体。
	var steps: int = maxi(ceili(motion.length() / (WorldGenerator.TILE_SIZE * 0.25)), 1)
	var step: Vector2 = motion / float(steps)
	for _index: int in steps:
		var destination: Vector2 = global_position + step
		if world_generator != null and not is_navigation_tile_allowed(WorldGenerator.world_to_tile(destination)):
			_knockback_impulse = Vector2.ZERO
			break
		if move_and_collide(step) != null:
			_knockback_impulse = Vector2.ZERO
			break


func _update_visual_pose() -> void:
	var visual := get_node_or_null("Visual") as Node2D
	if visual != null:
		visual.position = visual_pose + Vector2(0.0, -_visual_height)
		visual.modulate = visual_tint
	queue_redraw()


func _on_monster_damaged(hit: CombatHit, _actual_damage: float) -> void:
	# 命中音由受击方决定，这样不同材质的怪物可以换不同音色。
	_play_sfx(&"hit_critical" if hit.critical else &"hit_flesh", hit.position)
	_play_sfx(&"monster_hurt", global_position)
	_hit_flash_remaining = hit_flash_duration
	_update_hit_flash()
	var health_component := get_node_or_null("Health") as HealthComponent
	if health_component == null or not health_component.is_alive():
		return
	stop_navigation()
	_knockback_impulse = _resolve_knockback(hit)
	_knockback_remaining = knockback_duration if not _knockback_impulse.is_zero_approx() else 0.0
	# 受击打断动作，包括跳跃；Hurt 的高度轨道会立即落地归零。
	play_monster_animation(&"Hurt", true)
	if brain != null:
		brain.interrupt_attack()
	# 被打了却看不到攻击者：记为可疑信息，让 AI 去搜索而不是直接回家。
	# 这里用感知判定而不是单纯的视线，因为"看不到"既包括视线被挡，也包括超出视野距离。
	if perception == null or not perception.can_see(player):
		report_suspicious(_hit_source_position(hit))


func _hit_source_position(hit: CombatHit) -> Vector2:
	if is_instance_valid(hit.source) and hit.source is Node2D:
		return (hit.source as Node2D).global_position
	return hit.position


func _on_monster_died(_hit: CombatHit) -> void:
	# 只有被打死才出声；调试用的全灭指令保持安静。
	_play_sfx(&"monster_die", global_position)
	kill()


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载。
func _play_sfx(id: StringName, position: Vector2 = Vector2.INF) -> void:
	var manager: Node = get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.call("play_sfx", id, position)


# --- 动画 -------------------------------------------------------------------

func play_monster_animation(state: StringName, restart: bool = false) -> void:
	if animation_playback == null:
		return
	var current: StringName = animation_playback.get_current_node()
	# Death 是终点，脚本也不能通过 start/restart 把死亡怪物切回存活动作。
	if state != &"Death" and (_death_committed or current == &"Death"):
		return
	if current == state and not restart:
		return
	var machine := animation_tree.tree_root as AnimationNodeStateMachine
	var has_direct_transition: bool = false
	if machine != null:
		for index: int in machine.get_transition_count():
			if machine.get_transition_from(index) == current and machine.get_transition_to(index) == state:
				has_direct_transition = true
				break
	# 受击/死亡立即打断；缺少直连的动作也直接切换，避免 travel 绕经 Idle。
	if restart or state in [&"Hurt", &"Death"] or not has_direct_transition:
		animation_playback.start(state)
	else:
		animation_playback.travel(state)
	animation_tree.advance(0.0)
	# travel 首次求值处理状态切换，第二次应用新状态的初始轨道。
	animation_tree.advance(0.0)


func monster_animation_state() -> StringName:
	return animation_playback.get_current_node() if animation_playback != null else &"Idle"


func advance_monster_animation(delta: float) -> void:
	if animation_tree != null:
		animation_tree.advance(delta)


## 物理帧驱动的动画推进；远处怪物按 LOD 降频，但累计时间不变。
func advance_frame_animation(delta: float) -> void:
	if animation_tree == null:
		return
	if not _should_use_animation_lod():
		_animation_accumulator = 0.0
		animation_tree.advance(delta)
		return
	_animation_accumulator += delta
	var interval: float = 1.0 / maxf(ai_config.lod_animation_hz, 1.0)
	if _animation_accumulator < interval:
		return
	animation_tree.advance(_animation_accumulator)
	_animation_accumulator = 0.0


func _should_use_animation_lod() -> bool:
	if ai_config == null or not ai_config.lod_enabled or brain == null:
		return false
	return brain.is_lod_active()


func _setup_health_bar() -> void:
	var health_component := get_node_or_null("Health") as HealthComponent
	if health_component == null:
		return

	health_bar = get_node_or_null("HealthBar") as ProgressBar
	if health_bar == null:
		health_bar = ProgressBar.new()
		health_bar.name = "HealthBar"
		add_child(health_bar)
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.size = Vector2(28.0, 4.0)
	health_bar.position = Vector2(-14.0, -22.0)
	health_bar.z_index = 1
	var name_label := get_node_or_null("NameLabel") as Label
	if name_label != null:
		health_bar.position.y = name_label.position.y + name_label.size.y + 1.0

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.10, 0.08, 0.08, 0.95)
	background.border_color = Color(0.02, 0.02, 0.02)
	background.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.78, 0.18, 0.16)
	health_bar.add_theme_stylebox_override("background", background)
	health_bar.add_theme_stylebox_override("fill", fill)
	health_component.health_changed.connect(_update_health_bar)
	_update_health_bar(health_component.current_health, health_component.max_health)


func _update_health_bar(current: float, maximum: float) -> void:
	health_bar.max_value = maxf(maximum, 1.0)
	health_bar.value = current


## 调试全灭与正常死亡共用；先释放怪物携带的道具，避免随父节点一起删除。
func kill() -> void:
	if _death_committed or is_queued_for_deletion():
		return
	_death_committed = true
	play_monster_animation(&"Death", true)
	_drop_death_loot()
	killed.emit()
	var world_parent: Node = get_parent()
	if world_parent != null:
		for child: Node in get_children():
			if child.is_in_group("ingredients") or child.is_in_group("throwable_stones"):
				child.reparent(world_parent, true)
	queue_free()


func _drop_death_loot() -> void:
	if death_loot == null or get_parent() == null:
		return
	var item: IngredientData = death_loot.choose_for_roll(MapRng.shared(MapRng.Stream.LOOT).randf())
	if item == null:
		push_warning("Monster '%s' has no valid death loot entries" % name)
		return
	var pickup := GroundPickup.new()
	pickup.name = "%sLoot" % name
	pickup.bind(item, 1 + _loot_bonus(), world_generator)
	get_parent().add_child(pickup)
	pickup.global_position = _death_loot_position()


## 升级卡“贪婪”：材料掉落数量加值。
func _loot_bonus() -> int:
	var progress: Node = shared_service(&"RunProgress")
	if progress == null:
		return 0
	return progress.loot_bonus()


## 水中击杀的材料落在最近可通行岸边，玩家不用进入不可通行水面才能收取。
func _death_loot_position() -> Vector2:
	if world_generator == null:
		return global_position
	var tile: Vector2i = WorldGenerator.world_to_tile(global_position)
	if world_generator.is_walkable(tile):
		return global_position
	var spec: MapSpec = world_generator.sample_map(tile)
	var best: Vector2i = tile
	var distance: int = 16 * 16 + 1
	for y: int in range(-16, 17):
		for x: int in range(-16, 17):
			var squared: int = x * x + y * y
			if squared >= distance:
				continue
			var candidate := tile + Vector2i(x, y)
			if world_generator.sample_map(candidate) == spec and world_generator.is_walkable(candidate):
				best = candidate
				distance = squared
	return WorldGenerator.tile_to_world(best)


# --- 配置与感知原语 ---------------------------------------------------------

## MonsterSpawner 的统一初始化接口；子类需要扩展时调用 super.configure()。
func configure(
	target_player: PlayerCharacter,
	generator: WorldGenerator,
	chunk_coords: Vector2i
) -> void:
	spawn_chunk = chunk_coords
	configure_target(target_player, generator)


func configure_target(target_player: PlayerCharacter, generator: WorldGenerator) -> void:
	player = target_player
	world_generator = generator
	_knockback_impulse = Vector2.ZERO
	_knockback_remaining = 0.0
	_knockback_applied_this_frame = false
	_hit_flash_remaining = 0.0
	_last_line_blocked_by_physics = false
	_last_physics_collider = null
	_update_hit_flash()
	# 位置已确定，用最终坐标重建 AI：随机种子与初始巡逻锚点都依赖它。
	_build_ai()


func has_clear_line_to_player() -> bool:
	if not is_instance_valid(player):
		return false
	return has_clear_line_to_position(player.global_position, player)


func has_clear_line_to_position(
	world_target: Vector2,
	allowed_collider: CollisionObject2D = null
) -> bool:
	if world_generator == null:
		return false

	_last_line_blocked_by_physics = false
	_last_physics_collider = null
	target_raycast.target_position = to_local(world_target)
	target_raycast.force_raycast_update()
	if target_raycast.is_colliding():
		var collider: Object = target_raycast.get_collider()
		if allowed_collider == null or collider != allowed_collider:
			_last_line_blocked_by_physics = true
			if collider is CollisionObject2D:
				_last_physics_collider = collider as CollisionObject2D
			return false

	return _terrain_line_is_clear(global_position, world_target)


## 两点之间是否没有程序化地形阻挡（不含物理墙体），供 AI 选点使用。
func is_terrain_line_clear(from: Vector2, to: Vector2) -> bool:
	return _terrain_line_is_clear(from, to)


## 沿线密集采样，弥补当前 TileSet 没有物理碰撞层、RayCast2D 看不到地形的问题。
func _terrain_line_is_clear(from: Vector2, to: Vector2) -> bool:
	var distance: float = from.distance_to(to)
	var step_length: float = float(WorldGenerator.TILE_SIZE) * 0.25
	var steps: int = maxi(ceili(distance / step_length), 1)
	var previous_tile: Vector2i = EnemyPathfinder.INVALID_TILE
	for step: int in range(1, steps):
		var point: Vector2 = from.lerp(to, float(step) / float(steps))
		var tile: Vector2i = WorldGenerator.world_to_tile(point)
		if tile == previous_tile:
			continue
		previous_tile = tile
		if not is_visibility_tile_allowed(tile):
			return false
	return true


## 整段直线位移的严格地形检查：枚举线段扫过的所有格子，含只擦过一角的格子。
## 跳跃等“一次性位移”用它判断会不会穿墙；视线检测仍走 _terrain_line_is_clear。
func is_terrain_segment_clear(from: Vector2, to: Vector2) -> bool:
	var direction: Vector2 = to - from
	if direction.is_zero_approx():
		return true
	var tile_size: float = float(WorldGenerator.TILE_SIZE)
	var current: Vector2i = WorldGenerator.world_to_tile(from)
	var end_tile: Vector2i = WorldGenerator.world_to_tile(to)
	if not is_navigation_tile_allowed(current) or not is_navigation_tile_allowed(end_tile):
		return false
	if current == end_tile:
		return true

	var step_x: int = signi(end_tile.x - current.x)
	var step_y: int = signi(end_tile.y - current.y)
	var t_delta_x: float = absf(tile_size / direction.x) if step_x != 0 else INF
	var t_delta_y: float = absf(tile_size / direction.y) if step_y != 0 else INF
	var t_max_x: float = INF
	var t_max_y: float = INF
	if step_x != 0:
		t_max_x = (float(current.x + maxi(step_x, 0)) * tile_size - from.x) / direction.x
	if step_y != 0:
		t_max_y = (float(current.y + maxi(step_y, 0)) * tile_size - from.y) / direction.y

	var guard: int = absi(end_tile.x - current.x) + absi(end_tile.y - current.y) + 2
	while guard > 0:
		guard -= 1
		if is_equal_approx(t_max_x, t_max_y):
			# 正好穿过格点：supercover 规则要求同时检查两个对角邻格。
			if not is_navigation_tile_allowed(Vector2i(current.x + step_x, current.y)):
				return false
			if not is_navigation_tile_allowed(Vector2i(current.x, current.y + step_y)):
				return false
			current.x += step_x
			current.y += step_y
			t_max_x += t_delta_x
			t_max_y += t_delta_y
		elif t_max_x < t_max_y:
			current.x += step_x
			t_max_x += t_delta_x
		else:
			current.y += step_y
			t_max_y += t_delta_y
		if not is_navigation_tile_allowed(current):
			return false
		if current == end_tile:
			return true
	return true


## 子类可追加自己的移动限制；默认仅检查地形可通行性。
func is_navigation_tile_allowed(tile: Vector2i) -> bool:
	return world_generator != null and world_generator.is_walkable(tile)


## 默认与移动判定相同；两栖怪物可放宽视线而限制水中巡逻。
func is_visibility_tile_allowed(tile: Vector2i) -> bool:
	return is_navigation_tile_allowed(tile)


func is_patrol_tile_allowed(tile: Vector2i) -> bool:
	return is_navigation_tile_allowed(tile)


func movement_speed() -> float:
	# 定身期间按比例降速；只影响移动，不影响攻击节奏。
	if _slow_remaining > 0.0:
		return navigation_speed * (1.0 - _slow_ratio)
	return navigation_speed


## 升级卡“定身”：命中后减速一段时间，取更强的一次。
func apply_slow(ratio: float, seconds: float) -> void:
	if ratio <= 0.0 or seconds <= 0.0 or _death_committed:
		return
	_slow_ratio = clampf(maxf(_slow_ratio, ratio), 0.0, 0.9)
	_slow_remaining = maxf(_slow_remaining, seconds)


## 升级卡“连锁”：由玩家侧对周围怪物结算一次额外伤害。
func apply_chain_damage(amount: float, source: Node2D) -> void:
	if amount <= 0.0 or _death_committed:
		return
	var component := get_node_or_null("Health") as HealthComponent
	if component == null or not component.is_alive():
		return
	var hit: CombatHit = CombatHit.new()
	hit.source = source
	hit.weapon_id = &"chain"
	hit.damage = amount
	hit.position = global_position
	component.receive_hit(hit)



func stop_navigation() -> void:
	velocity = Vector2.ZERO
	match monster_animation_state():
		&"Idle", &"Move":
			play_monster_animation(&"Idle")
