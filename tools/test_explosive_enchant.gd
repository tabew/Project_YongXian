extends SceneTree

## 爆炸附魔不自伤验收：
## 武器上的爆炸附魔照常炸敌人，但不再扣玩家血、也不推玩家；
## 药水那条路的自伤保持原样（只有附魔这一路取消）。
##
## 运行：godot --headless --path . --script res://tools/test_explosive_enchant.gd

const PLAYER_SCENE: PackedScene = preload("res://scenes/game/player.tscn")
const LONGSWORD_ITEM: WeaponData = preload("res://resources/items/weapons/longsword.tres")

## 属性 id（见 AlchemicalAttributeList.ATTRIBUTE）
const EXPLOSIVE_ID: int = 6
## 爆炸等级：伤害 = 18 × sqrt(2)，半径 = 30 × sqrt(2) ≈ 42
const EXPLOSIVE_LEVEL: int = 1

var _checks: int = 0
var _failures: int = 0
var _attributes: Node = null
var _arena: Node2D = null
var _player: PlayerCharacter = null
var _enemy: HealthComponent = null
var _hurtbox: CombatHurtbox = null


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
	else:
		print("ok: " + message)


func _sync_physics() -> void:
	await physics_frame
	await physics_frame


## 造一个能挨打的敌人（阵营 2 / Layer 3 = 值 4）
func _make_enemy(at: Vector2) -> void:
	var target: Node2D = Node2D.new()
	target.position = at
	_enemy = HealthComponent.new()
	_enemy.name = "Health"
	_enemy.max_health = 1000.0
	target.add_child(_enemy)
	_hurtbox = CombatHurtbox.new()
	_hurtbox.health = _enemy
	_hurtbox.team = 2
	_hurtbox.collision_layer = 4
	_hurtbox.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 4.0
	shape_node.shape = shape
	_hurtbox.add_child(shape_node)
	target.add_child(_hurtbox)
	_arena.add_child(target)


## 造一次"带爆炸附魔的武器命中"
func _weapon_hit_with_explosive(explosive: Explosive) -> void:
	var weapon: WeaponDefinition = LONGSWORD_ITEM.weapon.duplicate(true) as WeaponDefinition
	weapon.enchant_attributes = [explosive]
	var attack: WeaponAttack = WeaponAttack.new()
	_arena.add_child(attack)
	attack.definition = weapon
	attack.wielder = _player
	attack._apply_enchant_effects(_hurtbox, CombatHit.new())
	attack.queue_free()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_attributes = root.get_node("AlchemicalAttributeList")
	_arena = Node2D.new()
	root.add_child(_arena)

	_player = PLAYER_SCENE.instantiate() as PlayerCharacter
	_player.add_to_group("player")
	_arena.add_child(_player)
	_player.set_physics_process(false)
	_player.weapon_controller.set_physics_process(false)
	# 敌人就站在玩家面前 10 像素：爆炸圈（半径 42）必然罩住玩家，正是原本会自伤的场景
	_make_enemy(Vector2(10.0, 0.0))
	await process_frame
	await _sync_physics()

	var explosive: Explosive = _attributes.create(EXPLOSIVE_ID, EXPLOSIVE_LEVEL) as Explosive
	_check(explosive != null, "爆炸属性可以创建")
	if explosive == null:
		_finish()
		return
	_check(explosive.need_target == false, "爆炸是不需要目标的属性（附魔走命中点那条分支）")
	_check(explosive.blast_radius() > 10.0, "爆炸半径确实罩得住玩家(%s)" % str(explosive.blast_radius()))

	#////////////////////////// 附魔：炸敌人，不伤自己
	_player.health = _player.max_health
	var enemy_before: float = _enemy.current_health
	var player_before: float = _player.health
	_player.velocity = Vector2.ZERO
	_weapon_hit_with_explosive(explosive)
	await _sync_physics()

	var enemy_damage: float = enemy_before - _enemy.current_health
	var self_damage: float = player_before - _player.health
	_check(is_equal_approx(enemy_damage, explosive.enemy_damage()),
		"爆炸附魔照常炸敌人(%s)" % str(enemy_damage))
	_check(is_equal_approx(self_damage, 0.0), "爆炸附魔不再扣玩家血(自伤 %s)" % str(self_damage))
	_check(_player.velocity.length() < 0.01, "爆炸附魔也不再推玩家(速度 %s)" % str(_player.velocity))

	#////////////////////////// 药水：自伤保持原样
	_player.health = _player.max_health
	_player.velocity = Vector2.ZERO
	var center: Node2D = Node2D.new()
	_arena.add_child(center)
	center.global_position = Vector2(10.0, 0.0)
	var potion_player_before: float = _player.health
	explosive.use_effect(center)
	await _sync_physics()
	var potion_self: float = potion_player_before - _player.health
	_check(is_equal_approx(potion_self, explosive.player_damage_total()),
		"药水爆炸仍然会伤到自己(%s)" % str(potion_self))

	#////////////////////////// 说明文本不再声称附魔有自伤
	var sword_item: WeaponData = LONGSWORD_ITEM.duplicate(true) as WeaponData
	var weapon: WeaponDefinition = LONGSWORD_ITEM.weapon.duplicate(true) as WeaponDefinition
	weapon.enchant_attributes = [explosive]
	sword_item.weapon = weapon
	var tooltip: String = ItemTooltip.build(sword_item)
	print("--- 附魔说明：\n", tooltip)
	_check(not tooltip.contains("玩家伤害"), "附魔说明里不再写玩家伤害")
	_check(tooltip.contains("不会伤到自己"), "附魔说明写明了不自伤")

	_finish()


func _finish() -> void:
	print("爆炸附魔自伤验收：%d 项检查，%d 项失败" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
