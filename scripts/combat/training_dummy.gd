class_name TrainingDummy
extends Node2D

@export_range(0.1, 30.0, 0.1) var respawn_seconds: float = 2.0
@export_range(0.0, 1.0, 0.05) var knockback_multiplier: float = 0.35

@onready var health: HealthComponent = $Health
@onready var sprite: Sprite2D = $Sprite2D

var terrain_source: WorldGenerator
var _home: Vector2
var _velocity: Vector2 = Vector2.ZERO
var _respawn_remaining: float = 0.0
var _flash: Tween


func _ready() -> void:
	_home = global_position
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	queue_redraw()



##BuffHolder 读当前属性值
func read_stat(stat: StringName) -> float:
	match stat:
		&"defense":
			return health.defense
		&"damage_taken":
			return health.damage_taken
		&"max_health":
			return health.max_health
	return 0.0


##BuffHolder 把算好的值写回属性（其它属性训练靶不支持，直接忽略）
func apply_stat(stat: StringName, value: float) -> void:
	match stat:
		&"defense":
			health.defense = value
		&"damage_taken":
			health.damage_taken = value
		&"max_health":
			health.max_health = maxf(value, 1.0)
			health.current_health = minf(health.current_health, health.max_health)
			health.health_changed.emit(health.current_health, health.max_health)


##当前是否处于隐身状态
var invisible: bool = false


##BuffHolder 通知标记类效果
func set_buff_flag(flag: StringName, active: bool) -> void:
	if flag != Buffs.FLAG_INVISIBLE:
		return
	invisible = active
	modulate.a = Buffs.HIDDEN_ALPHA if active else 1.0


##和玩家/怪物保持同一套接口
func is_invisible() -> bool:
	return invisible


func _physics_process(delta: float) -> void:
	if not health.is_alive():
		_respawn_remaining -= delta
		if _respawn_remaining <= 0.0:
			global_position = _home
			sprite.show()
			health.reset()
		return
	var next_position: Vector2 = global_position + _velocity * delta
	if terrain_source == null or terrain_source.is_walkable(WorldGenerator.world_to_tile(next_position)):
		global_position = next_position
	_velocity = _velocity.move_toward(Vector2.ZERO, 280.0 * delta)
	if _velocity.is_zero_approx():
		global_position = global_position.move_toward(_home, 16.0 * delta)


func _on_damaged(hit: CombatHit, actual_damage: float) -> void:
	_play_sfx(&"hit_critical" if hit.critical else &"hit_wood", hit.position)
	_velocity += hit.knockback * knockback_multiplier
	if _flash != null and _flash.is_valid():
		_flash.kill()
	sprite.modulate = Color(1.0, 0.45, 0.45)
	_flash = create_tween()
	_flash.tween_property(sprite, "modulate", Color.WHITE, 0.18)
	var label: Label = Label.new()
	label.text = "%d%s" % [roundi(actual_damage), "!" if hit.critical else ""]
	label.position = Vector2(-16.0, -38.0)
	label.size = Vector2(32.0, 18.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35) if hit.critical else Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0.05, 0.05, 0.05))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 4
	add_child(label)
	var tween: Tween = label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", -60.0, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)


func _on_died(_hit: CombatHit) -> void:
	_velocity = Vector2.ZERO
	_respawn_remaining = respawn_seconds
	sprite.hide()
	queue_redraw()


func _on_health_changed(_current: float, _maximum: float) -> void:
	queue_redraw()


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载。
func _play_sfx(id: StringName, position: Vector2 = Vector2.INF) -> void:
	var manager: Node = get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.call("play_sfx", id, position)


func _draw() -> void:
	if health == null or not health.is_alive():
		return
	draw_rect(Rect2(-15.0, -25.0, 30.0, 4.0), Color(0.08, 0.1, 0.1, 0.9))
	draw_rect(Rect2(-14.0, -24.0, 28.0 * health.current_health / health.max_health, 2.0), Color(0.52, 0.84, 0.44))
