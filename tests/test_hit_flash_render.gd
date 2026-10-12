extends Node2D

const MONSTER_SCENE: PackedScene = preload("res://scenes/monsters/give_monster.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var monster := MONSTER_SCENE.instantiate() as GiveMonster
	monster.position = Vector2(160, 160)
	monster.scale = Vector2(4, 4)
	add_child(monster)
	monster.set_physics_process(false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var normal: Image = get_viewport().get_texture().get_image()
	var hit := CombatHit.new()
	hit.damage = 1.0
	monster.combat_health.receive_hit(hit)
	# 单独验证闪红层，排除 Hurt 动画的普通颜色乘算影响。
	monster.visual_tint = Color.WHITE
	monster.visual_pose = Vector2.ZERO
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var flashed: Image = get_viewport().get_texture().get_image()
	var passed: bool = true
	# 身体、黑色眼睛与黑色腿部轮廓都应变成明亮的红色。
	for local_sample: Vector2i in [Vector2i(0, 1), Vector2i(-2, -8), Vector2i(-8, 8)]:
		var sample: Vector2i = Vector2i(160, 160) + local_sample * 4
		var after: Color = flashed.get_pixelv(sample)
		print("FLASH_RENDER_PIXEL local=", local_sample, " normal=", normal.get_pixelv(sample), " red=", after)
		passed = passed and after.r > 0.8 and after.g < 0.2 and after.b < 0.2
	# 检查名字与血条采样不会被身体的效果修改。
	for sample: Vector2i in [Vector2i(160, 16), Vector2i(160, 82)]:
		passed = passed and normal.get_pixelv(sample).is_equal_approx(flashed.get_pixelv(sample))
	var save_error: Error = flashed.save_png("res://.godot/hit_flash_render.png")
	passed = passed and save_error == OK
	print("HIT_FLASH_RENDER_RESULT=", passed)
	get_tree().quit(0 if passed else 1)
