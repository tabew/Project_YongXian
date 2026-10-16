class_name SwarmYoyoDefinition
extends YoyoWeaponDefinition

enum Effect { THUNDER, HIVE }
enum Ultimate { NONE, CONTRACT, CORE, BEACON, BOMB, MIGRATION }

@export_storage var ultimate: Ultimate = Ultimate.NONE


func apply_ultimate(mode: int) -> void:
	ultimate = mode as Ultimate
	match ultimate:
		Ultimate.CONTRACT:
			proc_chance = 1.0
			damage *= 0.4
			secondary_damage_scale /= 0.4
			hit_interval = 0.65
		Ultimate.CORE:
			secondary_damage_scale *= 2.5
			effect_range *= 1.5
		Ultimate.BOMB:
			bee_burst_count = 8
		Ultimate.MIGRATION:
			damage *= 0.6
			secondary_damage_scale /= 0.6
			bee_lifetime = 5.0
			bee_spawn_interval = 1.2

@export var effect: Effect = Effect.THUNDER
@export_range(1.0, 256.0) var effect_range: float = 40.0
@export_range(0.01, 4.0) var secondary_damage_scale: float = 1.5
@export_range(0.05, 5.0) var bee_spawn_interval: float = 0.6
@export_range(1, 12) var bee_burst_count: int = 3
@export_range(1, 24) var bee_limit: int = 9
@export_range(1.0, 1000.0) var bee_speed: float = 120.0
@export_range(0.1, 10.0) var bee_lifetime: float = 2.4
@export_range(0.05, 1.0) var bee_scatter_seconds: float = 0.3
@export var bee_texture: Texture2D


func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = super.validation_errors()
	if effect not in [Effect.THUNDER, Effect.HIVE]:
		errors.append("Unknown yoyo effect.")
	if effect_range <= 0.0 or secondary_damage_scale <= 0.0:
		errors.append("Yoyo effect range and damage scale must be positive.")
	if bee_spawn_interval <= 0.0 or bee_limit < 1 or bee_burst_count < 1 or bee_burst_count > bee_limit or bee_speed <= 0.0:
		errors.append("Bee timing, count and speed must be positive; burst cannot exceed limit.")
	if bee_scatter_seconds <= 0.0 or bee_lifetime <= bee_scatter_seconds:
		errors.append("Bee lifetime must exceed its positive scatter duration.")
	if effect == Effect.HIVE and bee_texture == null:
		errors.append("Hive requires a bee texture.")
	return errors
