class_name BreakableProp
extends Node2D

## 可破坏物：被武器打碎后掉对应材料，是消耗型的材料来源。
##
## 与场景元素的分工：
## - 场景元素可反复吸附、但每次只给 1 个；
## - 可破坏物一次给一串，但打碎后不再刷新，逼玩家推进房间。
##
## 血条与受击反馈走既有的 HealthComponent + CombatHurtbox，与怪物同一套命中流程。

## 打碎：携带掉落的材料与数量，由 GameWorld 决定怎么落到地上。
signal broken(prop_id: StringName, material_id: int, amount: int)

## 玩家武器是 1 队，可破坏物站 2 队，和怪物一致。
const ENEMY_TEAM: int = 2
const HURTBOX_LAYER: int = 4
## 受击盒半径（像素）：略小于视觉体积，避免隔着墙被劈到。
const HURTBOX_RADIUS: float = 11.0
## 默认耐久；普通武器 2~3 下打碎。
const DEFAULT_HEALTH: float = 14.0

var prop_id: StringName = &""
var display_name: String = ""
var material_id: int = -1
var amount: int = 1

var health: HealthComponent = null
var hurtbox: CombatHurtbox = null

var _broken: bool = false
var _flash: Tween = null
var _shake: float = 0.0


func _ready() -> void:
	add_to_group("breakables")
	z_index = 2
	_build_health()
	queue_redraw()


## 由规划器给出的一条点位数据。
func bind(entry: Dictionary) -> void:
	prop_id = StringName(entry.get("id", &""))
	display_name = BreakableCatalog.definition_of(prop_id).get("name", "可破坏物")
	material_id = int(entry.get("material_id", -1))
	amount = maxi(int(entry.get("amount", 1)), 1)
	_broken = false
	_shake = 0.0
	if health != null:
		health.reset()
	queue_redraw()


func is_broken() -> bool:
	return _broken


## 血量归零时由 GameWorld 收走掉落；这里只做表现。
func _build_health() -> void:
	if health != null:
		return
	health = HealthComponent.new()
	health.name = "Health"
	health.max_health = DEFAULT_HEALTH
	add_child(health)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	# 受击盒必须带着 health 进场：CombatHurtbox._ready 会校验它。
	hurtbox = CombatHurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = HURTBOX_LAYER
	hurtbox.collision_mask = 0
	hurtbox.team = ENEMY_TEAM
	hurtbox.health = health
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HURTBOX_RADIUS
	shape.shape = circle
	hurtbox.add_child(shape)
	add_child(hurtbox)


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载。
func _play_sfx(id: StringName, position: Vector2 = Vector2.INF) -> void:
	var manager: Node = get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.call("play_sfx", id, position)


func _on_damaged(_hit: CombatHit, _actual_damage: float) -> void:
	if _broken:
		return
	_shake = 1.0
	if _flash != null and _flash.is_valid():
		_flash.kill()
	modulate = Color(1.0, 0.72, 0.62)
	_flash = create_tween()
	_flash.tween_property(self, "modulate", Color.WHITE, 0.16)
	queue_redraw()


func _on_died(_hit: CombatHit) -> void:
	if _broken:
		return
	_broken = true
	if hurtbox != null:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	_play_sfx(&"break_wood", global_position)
	broken.emit(prop_id, material_id, amount)
	# 碎裂表现：先缩一下再消失，避免道具瞬间凭空不见。
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.4, 0.4), 0.18)
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	if _shake <= 0.0:
		return
	_shake = maxf(_shake - delta * 6.0, 0.0)
	queue_redraw()


## 视觉：木箱 / 矿脉等统一用带裂纹的方块表示，血量越低裂纹越多。
func _draw() -> void:
	if _broken:
		return
	var offset: Vector2 = Vector2(sin(_shake * 40.0) * 1.6, 0.0) if _shake > 0.0 else Vector2.ZERO
	draw_rect(Rect2(Vector2(-11.0, 1.0) + offset, Vector2(22.0, 3.0)), Color(0.06, 0.07, 0.05, 0.30))
	var body := Rect2(Vector2(-10.0, -14.0) + offset, Vector2(20.0, 16.0))
	draw_rect(body, Color(0.46, 0.36, 0.24))
	draw_rect(body, Color(0.24, 0.19, 0.13), false, 1.0)
	draw_rect(Rect2(body.position + Vector2(1.0, 1.0), Vector2(body.size.x - 2.0, 3.0)), Color(0.58, 0.46, 0.30))
	var damage_ratio: float = 0.0
	if health != null and health.max_health > 0.0:
		damage_ratio = 1.0 - health.current_health / health.max_health
	var cracks: int = clampi(int(damage_ratio * 3.0 + 0.999), 0, 3)
	for index: int in cracks:
		var start := Vector2(-6.0 + float(index) * 6.0, -12.0) + offset
		draw_line(start, start + Vector2(3.0, 5.0), Color(0.20, 0.15, 0.10, 0.9), 1.0)
		draw_line(start + Vector2(3.0, 5.0), start + Vector2(1.0, 10.0), Color(0.20, 0.15, 0.10, 0.9), 1.0)
