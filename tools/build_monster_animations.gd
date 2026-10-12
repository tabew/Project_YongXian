extends SceneTree

## 生成可在编辑器中修改的占位动画资源。
func _initialize() -> void:
	var library := AnimationLibrary.new()
	var machine := AnimationNodeStateMachine.new()
	var definitions: Dictionary = {
		"Idle": [1.0, true, [0.0, 0.5, 1.0], [Vector2.ZERO, Vector2(0, -1), Vector2.ZERO]],
		"Move": [0.3, true, [0.0, 0.15, 0.3], [Vector2(-1, 0), Vector2(1, -2), Vector2(-1, 0)]],
		"Attack": [0.3, false, [0.0, 0.12, 0.3], [Vector2.ZERO, Vector2(3, -1), Vector2.ZERO]],
		"Leap": [0.42, false, [0.0, 0.21, 0.42], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]],
		"Throw": [0.25, false, [0.0, 0.10, 0.25], [Vector2.ZERO, Vector2(-3, -2), Vector2.ZERO]],
		"Hurt": [0.10, false, [0.0, 0.02, 0.04, 0.06, 0.08, 0.10], [Vector2(4, -1), Vector2(-4, 1), Vector2(3, -1), Vector2(-3, 1), Vector2(1, 0), Vector2.ZERO]],
		"Death": [0.25, false, [0.0, 0.25], [Vector2.ZERO, Vector2(0, 8)]],
	}
	var index: int = 0
	for state: String in definitions:
		var spec: Array = definitions[state]
		var animation := Animation.new()
		animation.length = spec[0]
		animation.loop_mode = Animation.LOOP_LINEAR if spec[1] else Animation.LOOP_NONE
		var pose_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(pose_track, NodePath(".:visual_pose"))
		for key: int in spec[2].size():
			animation.track_insert_key(pose_track, spec[2][key], spec[3][key])
		var height_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(height_track, NodePath(".:_visual_height"))
		animation.track_insert_key(height_track, 0.0, 0.0)
		if state == "Leap":
			animation.track_insert_key(height_track, 0.21, 24.0)
		animation.track_insert_key(height_track, animation.length, 0.0)
		var tint_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(tint_track, NodePath(".:visual_tint"))
		animation.track_insert_key(tint_track, 0.0, Color(1.0, 0.35, 0.35) if state == "Hurt" else Color.WHITE)
		animation.track_insert_key(tint_track, animation.length, Color.WHITE)
		library.add_animation(StringName(state), animation)
		var node := AnimationNodeAnimation.new()
		node.animation = StringName(state)
		machine.add_node(StringName(state), node, Vector2(200 + index % 3 * 200, 100 + index / 3 * 150))
		index += 1
	for from: String in definitions:
		for to: String in definitions:
			if from == to:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			if from in ["Attack", "Throw", "Hurt"] and to == "Idle":
				transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
				transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
			machine.add_transition(StringName(from), StringName(to), transition)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	machine.add_transition(&"Start", &"Idle", start)
	# 调整受击反馈时只替换 Hurt，保留各怪物的其他动画和状态图。
	if "--hurt-only" in OS.get_cmdline_user_args():
		var saved: bool = true
		for path: String in ["res://resources/monsters/base_animation_library.tres", "res://resources/monsters/give_animation_library.tres"]:
			var existing := load(path) as AnimationLibrary
			existing.remove_animation(&"Hurt")
			existing.add_animation(&"Hurt", library.get_animation(&"Hurt").duplicate(true))
			var save_error: Error = ResourceSaver.save(existing, path)
			saved = saved and save_error == OK
		print("HURT_ANIMATION_UPDATED=", saved)
		quit(0 if saved else 1)
		return
	# 各怪物可替换自己的动画库，共用相同状态名称与默认状态图。
	var template_error: Error = ResourceSaver.save(library, "res://resources/monsters/base_animation_library.tres")
	var library_error: Error = ResourceSaver.save(library.duplicate(true), "res://resources/monsters/give_animation_library.tres")
	var machine_error: Error = ResourceSaver.save(machine, "res://resources/monsters/monster_animation_state_machine.tres")
	print("MONSTER_ANIMATION_RESOURCES=", library_error, ",", machine_error)
	quit(0 if template_error == OK and library_error == OK and machine_error == OK else 1)
