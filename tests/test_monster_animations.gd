extends Node

const MONSTER_SCENE: PackedScene = preload("res://scenes/monsters/give_monster.tscn")
const BASE_SCENE: PackedScene = preload("res://scenes/monsters/base_monster.tscn")


func _ready() -> void:
	call_deferred("_run")


func _test_template() -> bool:
	var first := BASE_SCENE.instantiate() as BaseMonster
	var second := BASE_SCENE.instantiate() as BaseMonster
	var health := first.get_node("Health") as HealthComponent
	health.max_health = 50.0
	add_child(first)
	add_child(second)
	var passed: bool = first.health_bar.max_value == 50.0 and first.health_bar.value == 50.0
	passed = passed and first.get_node("HealthBar") == first.health_bar
	passed = passed and first.animation_playback != second.animation_playback
	first.play_monster_animation(&"Attack", true)
	passed = passed and first.monster_animation_state() == &"Attack"
	passed = passed and second.monster_animation_state() == &"Idle"
	# 基类自身的物理更新会播放并完成动作，子类无需再添加动画节点。
	await get_tree().create_timer(0.4).timeout
	passed = passed and first.monster_animation_state() == &"Idle"
	var hit := CombatHit.new()
	hit.damage = 1.0
	health.receive_hit(hit)
	passed = passed and first.monster_animation_state() == &"Hurt"
	passed = passed and first.health_bar.value == 49.0
	passed = passed and (first.get_node("Visual") as Node2D).modulate.g < 1.0
	passed = passed and second.health_bar.value == 100.0
	health.max_health = 30.0
	health.reset()
	passed = passed and first.health_bar.max_value == 30.0 and first.health_bar.value == 30.0
	hit.damage = 30.0
	health.receive_hit(hit)
	passed = passed and first.monster_animation_state() == &"Death"
	await get_tree().process_frame
	passed = passed and not is_instance_valid(first)
	second.queue_free()
	print("BASE_MONSTER_TEMPLATE_RESULT=", passed)
	return passed


func _run() -> void:
	var template_passed: bool = await _test_template()
	var monster := MONSTER_SCENE.instantiate() as GiveMonster
	add_child(monster)
	monster.set_physics_process(false)
	var passed: bool = template_passed and monster.monster_animation_state() == &"Idle"
	monster.advance_monster_animation(0.5)
	passed = passed and monster.visual_pose.y < 0.0

	print("ANIMATION_IDLE=", passed, " pose=", monster.visual_pose)
	monster.play_monster_animation(&"Move")
	monster.advance_monster_animation(0.1)
	passed = passed and monster.monster_animation_state() == &"Move"
	monster.stop_navigation()
	passed = passed and monster.monster_animation_state() == &"Idle"

	print("ANIMATION_MOVE=", passed, " state=", monster.monster_animation_state())
	monster.play_monster_animation(&"Leap", true)
	monster.advance_monster_animation(0.21)
	print("ANIMATION_LEAP_HEIGHT=", monster._visual_height)
	passed = passed and is_equal_approx(monster._visual_height, GiveMonster.LEAP_HEIGHT)
	monster.play_monster_animation(&"Idle")
	print("ANIMATION_LEAP_RESET=", monster._visual_height, " state=", monster.monster_animation_state())
	passed = passed and is_zero_approx(monster._visual_height)

	monster.play_monster_animation(&"Throw", true)
	passed = passed and monster.monster_animation_state() == &"Throw"
	monster.advance_monster_animation(0.26)
	monster.advance_monster_animation(0.01)
	passed = passed and monster.monster_animation_state() == &"Idle"

	print("ANIMATION_THROW=", passed, " state=", monster.monster_animation_state())
	monster.take_damage(1)
	print("ANIMATION_HURT_TINT=", monster.visual_tint, " state=", monster.monster_animation_state())
	passed = passed and monster.monster_animation_state() == &"Hurt"
	passed = passed and monster.visual_tint.g < 1.0 and monster.health_bar.value == 99.0
	monster.advance_monster_animation(0.19)
	monster.advance_monster_animation(0.01)
	passed = passed and monster.monster_animation_state() == &"Idle"
	passed = passed and monster.visual_tint.is_equal_approx(Color.WHITE)

	# 受击会打断跳跃并归零高度，避免旧跳跃位移覆盖新的击退。
	monster.play_monster_animation(&"Leap", true)
	monster.advance_monster_animation(0.21)
	monster.take_damage(1)
	passed = passed and monster.monster_animation_state() == &"Hurt"
	passed = passed and is_zero_approx(monster._visual_height)
	monster.kill()
	passed = passed and monster.monster_animation_state() == &"Death"
	await get_tree().process_frame
	passed = passed and not is_instance_valid(monster)
	print("MONSTER_ANIMATION_TEST_RESULT=", passed)
	if not passed:
		push_error("Animation state, track playback, completion transition or death cleanup failed")
	get_tree().quit(0 if passed else 1)
