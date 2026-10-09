class_name WeaponController
extends Node2D

signal weapon_changed(weapon: WeaponDefinition)
signal attack_started(weapon: WeaponDefinition)
signal attack_finished
signal hit_landed(hit: CombatHit, hurtbox: CombatHurtbox)

@export var starting_weapon: WeaponDefinition
@export var team: int = 1

var equipped_weapon: WeaponDefinition
var aim_direction: Vector2 = Vector2.RIGHT

var _attack: WeaponAttack
var _held: bool = false
var _pending_press: bool = false
var _cooldown: float = 0.0


func _ready() -> void:
	if starting_weapon != null:
		equip(starting_weapon)


## A null definition unequips. Invalid replacements leave the current weapon intact.
func equip(data: WeaponDefinition) -> bool:
	if data != null:
		var errors: PackedStringArray = data.validation_errors()
		if not errors.is_empty():
			push_warning("Invalid weapon: %s" % "; ".join(errors))
			return false
		var candidate: Node = data.attack_scene.instantiate()
		var valid: bool = candidate is WeaponAttack and (candidate as WeaponAttack).accepts_definition(data)
		candidate.free()
		if not valid:
			push_warning("Attack scene must extend WeaponAttack and accept the weapon definition.")
			return false
	cancel_attack()
	equipped_weapon = data
	weapon_changed.emit(equipped_weapon)
	return true


func set_aim(direction: Vector2) -> void:
	if not direction.is_zero_approx():
		aim_direction = direction.normalized()


## Input-agnostic so AI can use the same controller. Only a new press queues a tap.
func set_trigger_pressed(pressed: bool) -> void:
	if pressed and not _held:
		_pending_press = true
	_held = pressed


func is_attacking() -> bool:
	return is_instance_valid(_attack)


func locked_aim() -> Vector2:
	return _attack.aim_direction if is_attacking() else aim_direction


func cancel_attack() -> void:
	if is_instance_valid(_attack):
		_attack.cancel()
	_attack = null
	_held = false
	_pending_press = false
	_cooldown = 0.0


func _physics_process(delta: float) -> void:
	var tapped: bool = _pending_press
	_pending_press = false
	if is_attacking():
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if equipped_weapon != null and (tapped or (_held and equipped_weapon.auto_repeat)):
		try_attack()


func try_attack() -> bool:
	if equipped_weapon == null or is_attacking() or _cooldown > 0.0:
		return false
	var actor: Node2D = get_parent() as Node2D
	if actor == null:
		return false
	_attack = equipped_weapon.attack_scene.instantiate() as WeaponAttack
	_attack.finished.connect(_on_attack_finished)
	_attack.hit_landed.connect(_on_hit_landed)
	add_child(_attack)
	_attack.start(equipped_weapon, actor, team, aim_direction)
	attack_started.emit(equipped_weapon)
	return true


func _on_attack_finished() -> void:
	_cooldown = _attack.definition.reuse_delay
	_attack = null
	attack_finished.emit()


func _on_hit_landed(hit: CombatHit, hurtbox: CombatHurtbox) -> void:
	hit_landed.emit(hit, hurtbox)
