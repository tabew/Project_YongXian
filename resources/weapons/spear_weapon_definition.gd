class_name SpearWeaponDefinition
extends WeaponDefinition

@export_group("Thrust geometry (pixels)")
## Grip to tip. The texture and damage shape use the same length.
@export_range(4.0, 128.0, 0.5) var shaft_length: float = 36.0
@export_range(0.0, 32.0, 0.5) var hand_distance: float = 8.0
@export_range(1.0, 128.0, 0.5) var thrust_distance: float = 28.0
@export_range(0.0, 32.0, 0.5) var pullback_distance: float = 6.0
@export_range(0.0, 16.0, 0.5) var grip_inset: float = 3.0
@export_range(1.0, 16.0, 0.5) var hit_width: float = 6.0

@export_group("Thrust sequence")
@export_range(1, 4, 1) var thrust_count: int = 1

@export_group("Appearance")
## Texture points right; grip is measured from its top-left corner.
@export var texture: Texture2D
@export var texture_grip: Vector2 = Vector2(28.0, 5.0)
@export var trail_color: Color = Color(0.65, 0.92, 0.94, 0.45)


func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = super.validation_errors()
	if shaft_length <= 0.0 or hit_width <= 0.0 or thrust_distance <= 0.0 or hand_distance < 0.0:
		errors.append("Spear dimensions must be positive; hand distance must be nonnegative.")
	if pullback_distance < 0.0 or pullback_distance > hand_distance:
		errors.append("Pullback must keep the grip in front of the wielder.")
	if grip_inset < 0.0 or grip_inset >= shaft_length:
		errors.append("Grip inset must be smaller than shaft length.")
	if thrust_count < 1 or thrust_count > 4:
		errors.append("A spear sequence must contain 1..4 thrusts.")
	if texture == null:
		errors.append("A spear texture is required.")
	elif texture_grip.x < 0.0 or texture_grip.x >= texture.get_width() or texture_grip.y < 0.0 or texture_grip.y >= texture.get_height():
		errors.append("Texture grip must be inside the texture.")
	return errors
