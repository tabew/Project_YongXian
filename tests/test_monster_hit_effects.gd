extends Node2D

class TestTerrain extends WorldGenerator:
	var blocked_from_x: int = 100000
	func is_walkable(tile: Vector2i) -> bool:
		return tile.x < blocked_from_x

const BASE: PackedScene = preload("res://scenes/monsters/base_monster.tscn")
const GIVE: PackedScene = preload("res://scenes/monsters/give_monster.tscn")
var passed: bool = true


func _ready() -> void:
	call_deferred("_run")


func _monster(scene: PackedScene, at: Vector2, terrain: WorldGenerator) -> BaseMonster:
	var monster := scene.instantiate() as BaseMonster
	monster.position = at
	add_child(monster)
	monster.set_physics_process(false)
	monster.configure(null, terrain, Vector2i.ZERO)
	return monster


func _hit(monster: BaseMonster, impulse: Vector2, source: Node2D = null, damage: float = 1.0) -> bool:
	var hit := CombatHit.new()
	hit.damage = damage
	hit.knockback = impulse
	hit.source = source
	hit.position = monster.global_position
	return (monster.get_node("Health") as HealthComponent).receive_hit(hit)


func _flash(monster: BaseMonster) -> float:
	return float(((monster.get_node("Visual") as CanvasItem).material as ShaderMaterial).get_shader_parameter("hit_flash"))


func _check(condition: bool, description: String) -> void:
	print("HIT_EFFECT_CHECK ", description, "=", condition)
	if not condition:
		passed = false
		push_error(description)


func _run() -> void:
	var terrain := TestTerrain.new(1)
	var first := _monster(BASE, Vector2.ZERO, terrain)
	var second := _monster(BASE, Vector2(100, 100), terrain)
	await get_tree().physics_frame
	_hit(first, Vector2(200, 0))
	_check(_flash(first) == 1.0 and _flash(second) == 0.0, "flash_is_independent")
	var first_shake: Vector2 = first.visual_pose
	first._physics_process(0.02)
	_check(first_shake.x > 3.5 and first.visual_pose.x < -3.5, "body_shakes_strongly_in_twenty_milliseconds")
	first._physics_process(0.03)
	_check(is_equal_approx(first.global_position.x, 9.0) and is_zero_approx(first.global_position.y), "weapon_200_plus_template_40_moves_as_240")

	var diagonal := _monster(BASE, Vector2(0, 300), terrain)
	var diagonal_start: Vector2 = diagonal.global_position
	_hit(diagonal, Vector2(-108, 144)) # 武器强度180，基础40，合计220。
	diagonal._physics_process(0.10)
	_check(is_equal_approx(diagonal.global_position.distance_to(diagonal_start), 11.0), "diagonal_strengths_add_without_changing_direction")
	_check(diagonal.global_position.x < 0.0 and diagonal.global_position.y > 300.0, "diagonal_weapon_direction_preserved")

	var attacker := Node2D.new()
	attacker.position = Vector2(50, 100)
	add_child(attacker)
	_hit(second, Vector2.ZERO, attacker)
	second._physics_process(0.10)
	_check(is_equal_approx(second.global_position.x - 100.0, 2.0), "basic_hit_is_only_two_pixels")
	_check(diagonal.global_position.distance_to(diagonal_start) > (second.global_position.x - 100.0) * 5.0, "weapon_push_dominates_basic_hit")

	first._physics_process(0.06)
	_check(_flash(first) == 0.0 and first.monster_animation_state() == &"Idle", "flash_and_hurt_recover_quickly")
	var before_repeat: float = first.global_position.x
	_hit(first, Vector2(-200, 0))
	first._physics_process(0.04)
	_check(first.global_position.x < before_repeat and _flash(first) == 1.0, "repeat_hit_restarts_and_reverses")
	first._physics_process(0.07)
	first._physics_process(0.01)
	_check(_flash(first) == 0.0 and not first.is_receiving_knockback(), "feedback_finishes")
	_check(not _hit(first, Vector2(200, 0), null, 0.0) and _flash(first) == 0.0, "zero_damage_has_no_feedback")

	var blocked := TestTerrain.new(2)
	blocked.blocked_from_x = 1
	var terrain_monster := _monster(BASE, Vector2(8, 64), blocked)
	_hit(terrain_monster, Vector2(1200, 0))
	terrain_monster._physics_process(0.18)
	_check(terrain_monster.global_position.x < 16.0, "cannot_cross_terrain_wall")

	var wall := StaticBody2D.new()
	wall.position = Vector2(40, 128)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(4, 64)
	shape.shape = rectangle
	wall.add_child(shape)
	add_child(wall)
	var physical_monster := _monster(BASE, Vector2(8, 128), terrain)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_hit(physical_monster, Vector2(1200, 0))
	physical_monster._physics_process(0.18)
	_check(physical_monster.global_position.x > 8.0 and physical_monster.global_position.x < 31.0, "cannot_cross_physical_wall")

	var give := _monster(GIVE, Vector2(200, 200), terrain) as GiveMonster
	var give_attack := give.get_attack() as GiveMonsterAttack
	give_attack.start_leap(give, Vector2(1000, 200))
	give.advance_monster_animation(0.21)
	_hit(give, Vector2(-200, 0))
	_check(give.monster_animation_state() == &"Hurt" and is_zero_approx(give._visual_height) and _flash(give) == 1.0, "airborne_hit_interrupts_and_flashes")
	give._physics_process(0.05)
	give._physics_process(0.25)
	_check(give.global_position.x < 200.0 and is_zero_approx(give_attack.leap_elapsed()), "old_leap_cannot_overwrite_knockback")

	print("MONSTER_HIT_EFFECTS_RESULT=", passed)
	get_tree().quit(0 if passed else 1)
