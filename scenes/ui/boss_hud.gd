class_name BossHud
extends Control

const HEALTH_WIDTH: float = 560.0
const RAGE_WIDTH: float = 360.0

@onready var content: Control = $Content
@onready var name_label: Label = $Content/NameLabel
@onready var phase_label: Label = $Content/PhaseLabel
@onready var health_bar: ProgressBar = $Content/HealthBar
@onready var rage_label: Label = $Content/RageLabel
@onready var rage_bar: BossRageBar = $Content/RageBar


func _ready() -> void:
	resized.connect(_layout)
	_layout()


func bind_health(health: HealthComponent, title: String) -> void:
	name_label.text = title
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func set_phase(phase: int, total: int, color: Color) -> void:
	phase_label.text = "%d / %d" % [phase, total]
	var fill := health_bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = color
	set_rage(phase == 3, rage_bar.current_rage, false, 0.0)


func set_rage(enabled: bool, value: int, charging: bool, seconds: float) -> void:
	rage_label.visible = enabled
	rage_bar.visible = enabled
	if not enabled:
		return
	rage_bar.set_rage(value, charging)
	rage_label.text = "蓄力 %.0fs   怒气 %d / 1000" % [ceilf(seconds), value] if charging else "怒气 %d / 1000" % value


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maxf(maximum, 1.0)
	health_bar.value = current


func _layout() -> void:
	if not is_node_ready():
		return
	var width: float = minf(HEALTH_WIDTH, maxf(0.0, size.x - 24.0))
	content.position = Vector2(roundf((size.x - width) * 0.5), 8.0)
	content.size = Vector2(width, 96.0)
	var rage_width: float = minf(RAGE_WIDTH, maxf(0.0, width - 24.0))
	var left: float = roundf((width - rage_width) * 0.5)
	rage_label.position = Vector2(left, 59.0)
	rage_label.size = Vector2(rage_width, 18.0)
	rage_bar.position = Vector2(left, 78.0)
	rage_bar.size = Vector2(rage_width, 14.0)
