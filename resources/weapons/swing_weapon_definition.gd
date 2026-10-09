class_name SwingWeaponDefinition
extends WeaponDefinition

@export_group("Swing geometry (pixels / degrees)")
## Distance from the character center to the hand.
@export_range(0.0, 64.0, 0.5) var hand_distance: float = 9.0
## Distance from the texture's grip pivot to the tip. Also scales the sprite.
@export_range(4.0, 256.0, 0.5) var blade_length: float = 38.0
@export_range(1.0, 64.0, 0.5) var blade_width: float = 7.0
## Non-damaging section between the grip and blade.
@export_range(0.0, 64.0, 0.5) var blade_inset: float = 6.0
@export_range(1.0, 360.0, 1.0) var arc_degrees: float = 150.0
@export_range(-180.0, 180.0, 1.0) var aim_offset_degrees: float = 0.0

@export_group("Appearance")
## Texture points RIGHT (+X); pivot is measured from its top-left corner.
@export var texture: Texture2D
@export var texture_grip: Vector2 = Vector2(6.0, 7.0)
@export var trail_color: Color = Color(0.72, 0.92, 1.0, 0.45)
@export_range(0.0, 90.0, 1.0) var trail_degrees: float = 42.0


func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = super.validation_errors()
	if blade_length <= 0.0 or blade_width <= 0.0 or hand_distance < 0.0:
		errors.append("Blade dimensions must be positive; hand distance must be nonnegative.")
	if blade_inset < 0.0 or blade_inset >= blade_length:
		errors.append("Blade inset must be smaller than blade length.")
	if arc_degrees <= 0.0 or arc_degrees > 360.0:
		errors.append("Swing arc must be in (0, 360].")
	if texture == null:
		errors.append("A swing texture is required.")
	elif texture_grip.x < 0.0 or texture_grip.x >= texture.get_width() or texture_grip.y < 0.0 or texture_grip.y >= texture.get_height():
		errors.append("Texture grip must be inside the texture.")
	return errors
