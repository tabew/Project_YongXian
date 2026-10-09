class_name WeaponDefinition
extends Resource

## Shared item data. Runtime attacks take a snapshot; never store combat state here.
@export_group("Identity")
@export var id: StringName = &"weapon"
@export var display_name: String = "Weapon"
@export var icon: Texture2D
@export var attack_scene: PackedScene

@export_group("Damage")
@export_range(0.0, 10000.0, 0.5) var damage: float = 18.0
@export_range(0.0, 1.0, 0.01) var critical_chance: float = 0.04
@export_range(1.0, 10.0, 0.1) var critical_multiplier: float = 2.0
## Velocity impulse, in pixels per second. The target applies its own resistance.
@export_range(0.0, 2000.0, 1.0) var knockback: float = 110.0
@export_flags_2d_physics var hit_mask: int = 4

@export_group("Timing (seconds)")
@export_range(0.0, 5.0, 0.01) var windup_seconds: float = 0.08
@export_range(0.01, 5.0, 0.01) var active_seconds: float = 0.18
@export_range(0.0, 5.0, 0.01) var recovery_seconds: float = 0.20
## Extra delay AFTER the attack has finished.
@export_range(0.0, 5.0, 0.01) var reuse_delay: float = 0.04
@export var auto_repeat: bool = true


func attack_duration() -> float:
	return windup_seconds + active_seconds + recovery_seconds


func attacks_per_second() -> float:
	return 1.0 / maxf(attack_duration() + reuse_delay, 0.01)


func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if id.is_empty():
		errors.append("Weapon id cannot be empty.")
	if attack_scene == null:
		errors.append("An attack scene is required.")
	if damage < 0.0 or knockback < 0.0:
		errors.append("Damage and knockback must be nonnegative.")
	if critical_chance < 0.0 or critical_chance > 1.0 or critical_multiplier < 1.0:
		errors.append("Critical chance must be 0..1 and multiplier must be >= 1.")
	if windup_seconds < 0.0 or active_seconds <= 0.0 or recovery_seconds < 0.0 or reuse_delay < 0.0:
		errors.append("Active time must be positive; other timings must be nonnegative.")
	if hit_mask == 0:
		errors.append("Select at least one hurtbox collision layer.")
	return errors
