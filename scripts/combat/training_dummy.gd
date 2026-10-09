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


func _draw() -> void:
	if health == null or not health.is_alive():
		return
	draw_rect(Rect2(-15.0, -25.0, 30.0, 4.0), Color(0.08, 0.1, 0.1, 0.9))
	draw_rect(Rect2(-14.0, -24.0, 28.0 * health.current_health / health.max_health, 2.0), Color(0.52, 0.84, 0.44))
