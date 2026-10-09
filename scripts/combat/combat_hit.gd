class_name CombatHit
extends RefCounted

## One resolved hit. Receivers must not mutate it.
var source: Node2D
var weapon_id: StringName
var damage: float = 0.0
var knockback: Vector2 = Vector2.ZERO
var position: Vector2 = Vector2.ZERO
var critical: bool = false
