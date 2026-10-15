extends SceneTree

## 药水命中判定的验收：木桩式目标(Node2D + layer4 的 Area2D 受击盒)只要在药水弹道上，
## 哪怕瓶心偏离受击盒中心十几像素，也要在受击盒处碎掉，而不是整颗穿过去。
##
## 运行：godot --headless --path . --script res://tools/test_potion_hit.gd
##
## 背景：木桩的受击盒半径只有 10px，比它的贴图小得多；药水原来用零宽射线判定撞击，
## 要求瓶心几乎正中受击盒才算命中，稍微偏离就会穿过去，飞到可视范围外才碎
## （表现：药水穿过木桩、没伤害、木桩那里也没有爆炸）。

## 木桩受击盒半径，和 training_dummy.tscn 里的 CircleShape2D 一致
const HURTBOX_RADIUS: float = 10.0
## 木桩受击盒所在层(Layer 3 = EnemyHurtbox = 值 4)，和 training_dummy.tscn 一致
const HURTBOX_LAYER: int = 4
## 药水投掷用的碰撞掩码，和 PotionData.right_use 里设的一致
const POTION_MASK: int = 4
## 本帧推进用的时长，模拟 60 帧/秒
const STEP_SECONDS: float = 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0
var _arena: Node2D = null


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## 造一个木桩式目标：Node2D 身体 + 受击盒 Area2D（和 training_dummy 同构）
func _make_target(at: Vector2) -> Area2D:
	var body: Node2D = Node2D.new()
	body.position = at
	var hurtbox: Area2D = Area2D.new()
	hurtbox.collision_layer = HURTBOX_LAYER
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.monitorable = true
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = HURTBOX_RADIUS
	shape_node.shape = circle
	hurtbox.add_child(shape_node)
	body.add_child(hurtbox)
	_arena.add_child(body)
	return hurtbox


## 造一瓶正在飞的药水：[模型, 投射物控制器]
func _make_projectile(at: Vector2) -> Array:
	var potion: ItemModel = (load("res://scenes/items/potions/potion.tscn") as PackedScene).instantiate() as ItemModel
	_arena.add_child(potion)
	potion.global_position = at
	potion.collision_layer = 0
	potion.collision_mask = POTION_MASK
	potion.freeze = true
	potion.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	var projectile: PotionProjectile = PotionProjectile.new()
	potion.add_child(projectile)
	projectile.start(null, Vector2.RIGHT, 400.0, 32.0, 0.0, [])
	return [potion, projectile]


## 等物理服务器把新加的受击盒放进空间，否则第一次查询查不到
func _settle() -> void:
	await physics_frame
	await physics_frame
	await physics_frame


func _run() -> void:
	_arena = Node2D.new()
	root.add_child(_arena)

	# --- 偏离弹道 12px：受击盒半径 10 + 判定半径 6，这种"擦边"必须算命中 ---
	var off_center: Area2D = _make_target(Vector2(120.0, 12.0))
	await _settle()
	var pair: Array = _make_projectile(Vector2.ZERO)
	await _settle()

	var impact: float = pair[1].call("_first_block", Vector2(0.0, 0.0), Vector2(140.0, 0.0))
	_check(impact >= 0.0, "瓶心偏离受击盒中心 12px 时仍要判为命中")
	if impact >= 0.0:
		var point: Vector2 = Vector2(0.0, 0.0).lerp(Vector2(140.0, 0.0), impact)
		_check(point.x > 100.0 and point.x < 132.0, "碎点落在受击盒附近（x=%.1f）" % point.x)

	# --- 偏离 60px：超出受击盒 + 判定半径，不能误判 ---
	off_center.get_parent().global_position = Vector2(120.0, 800.0)
	await _settle()
	_make_target(Vector2(120.0, 60.0))
	await _settle()
	var miss_pair: Array = _make_projectile(Vector2.ZERO)
	await _settle()
	_check(miss_pair[1].call("_first_block", Vector2(0.0, 0.0), Vector2(140.0, 0.0)) < 0.0,
			"瓶心偏离 60px 时不算命中")

	# --- 正对目标逐帧推进：药水要碎在目标上，而不是飞过去 ---
	var direct: Area2D = _make_target(Vector2(120.0, 0.0))
	await _settle()
	var shot: Array = _make_projectile(Vector2.ZERO)
	await _settle()
	var potion: ItemModel = shot[0]
	var projectile: PotionProjectile = shot[1]
	var steps: int = 0
	while steps < 60 and not bool(projectile.get("_done")):
		projectile.call("_physics_process", STEP_SECONDS)
		steps += 1
	_check(bool(projectile.get("_done")), "推进 %d 帧后药水碎在目标上" % steps)
	_check(steps < 30, "%d 帧内撞上（正对目标 120px，约 0.3 秒）" % steps)
	_check(potion.global_position.x > 100.0 and potion.global_position.x < 132.0,
			"碎点停在受击盒附近（x=%.1f）" % potion.global_position.x)
	_check(direct != null and is_instance_valid(direct), "受击盒仍然有效")

	print("POTION_HIT: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)