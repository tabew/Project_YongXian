class_name DepthStrikeWeaponDefinition
extends WeaponDefinition

@export_group("Staff geometry (pixels)")
## Grip to forward tip, before depth foreshortening.
@export_range(4.0, 128.0, 0.5) var shaft_length: float = 24.0
@export_range(0.0, 32.0, 0.5) var hand_distance: float = 8.0
@export_range(0.0, 16.0, 0.5) var forward_travel: float = 4.0
@export_range(0.0, 16.0, 0.5) var grip_inset: float = 3.0
@export_range(1.0, 16.0, 0.5) var hit_width: float = 4.0

@export_group("Depth swing")
## Small screen-plane fan, centered on the locked aim direction.
@export_range(0.0, 90.0, 1.0) var arc_degrees: float = 40.0
## Positive pitch points toward the viewer; negative pitch points into the screen.
@export_range(-80.0, 80.0, 1.0) var near_pitch_degrees: float = 15.0
@export_range(-80.0, 80.0, 1.0) var far_pitch_degrees: float = -35.0
## Default moves from far to near; reverse changes depth but keeps the same fan.
@export var reverse_strike: bool = false
@export_range(0.0, 0.35, 0.01) var perspective_strength: float = 0.28

@export_group("Appearance")
## Texture points right; grip is measured from its top-left corner.
@export var texture: Texture2D
@export var texture_grip: Vector2 = Vector2(8.0, 2.5)
@export var trail_color: Color = Color(0.88, 0.95, 0.7, 0.3)


func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = super.validation_errors()
	if shaft_length <= 0.0 or hit_width <= 0.0 or hand_distance < 0.0 or forward_travel < 0.0:
		errors.append("Staff dimensions must be positive; distances must be nonnegative.")
	if grip_inset < 0.0 or grip_inset >= shaft_length:
		errors.append("Grip inset must be smaller than shaft length.")
	if arc_degrees < 0.0 or arc_degrees > 90.0:
		errors.append("Staff swing arc must be in 0..90 degrees.")
	if absf(near_pitch_degrees) > 80.0 or absf(far_pitch_degrees) > 80.0 or is_equal_approx(near_pitch_degrees, far_pitch_degrees):
		errors.append("Depth pitches must be different and within -80..80 degrees.")
	if perspective_strength < 0.0 or perspective_strength > 0.35:
		errors.append("Perspective strength must be in 0..0.35.")
	if texture == null:
		errors.append("A staff texture is required.")
	elif texture_grip.x < 0.0 or texture_grip.x >= texture.get_width() or texture_grip.y < 0.0 or texture_grip.y >= texture.get_height():
		errors.append("Texture grip must be inside the texture.")
	return errors
