extends WeaponAttack

## A different behavior verifies the controller has no sword-specific branches.
func _on_started() -> void:
	set_meta("alternate_started", true)


func _advance(_previous: float, current: float) -> void:
	position = aim_direction * current * 10.0
