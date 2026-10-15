class_name SecretDoorProp
extends Node2D

## 秘密房的词条门：堵在宿主房通往秘密房的出口上，只有带对应词条的炼金组合才能打开。
##
## 与普通门的区别：普通门走 `gate_links` 直接瞬切；词条门是一堵实体墙，
## 世界层在未开门时跳过该出口的瞬切，开门后才放行。
##
## 开门条件由 `SecretDoor.matches()` 判定；本节点只负责表现与「被敲 / 被按 E」的入口，
## 词条等级表由世界层通过 `trait_levels_provider` 注入，节点不读炼金内部结构。

## 开门成功：世界层据此放行出口并记录本局已开。
signal opened(kind: int)

## 玩家武器是 1 队，词条门站 2 队，和可破坏物一致。
const ENEMY_TEAM: int = 2
const HURTBOX_LAYER: int = 4
const HURTBOX_RADIUS: float = 16.0
## 血量只用来承接命中回调，实际不会被打碎，所以给一个足够大的值。
const GATE_HEALTH: float = 999999.0
## 开门提示的显示时长。
const HINT_DURATION: float = 1.6

var kind: int = SecretDoor.Kind.EXPLODE
## 该门通向的秘密房世界 node_id；-1 表示未绑定。
var target_world_node: int = -1
## 世界层注入：返回当前生效组合的词条等级表 {trait_id: level}。
var trait_levels_provider: Callable = Callable()

var health: HealthComponent = null
var hurtbox: CombatHurtbox = null

var _open: bool = false
var _hint_remaining: float = 0.0
var _shake: float = 0.0
var _flash: Tween = null


func _ready() -> void:
	add_to_group("secret_doors")
	z_index = 3
	_build_hurtbox()
	queue_redraw()


## 绑定门的类型与目标；由世界层在生成时调用。
func bind(door_kind: int, target_node: int) -> void:
	kind = door_kind
	target_world_node = target_node
	_open = false
	_hint_remaining = 0.0
	_shake = 0.0
	queue_redraw()


func is_open() -> bool:
	return _open


## 玩家是否满足开门条件；不满足时给出提示。
func can_open() -> bool:
	if _open:
		return false
	return SecretDoor.matches(kind, _current_trait_levels())


## 尝试开门：满足条件则开门并广播，否则只抖一下并提示缺什么。
func attempt_open() -> bool:
	if _open:
		return false
	if not can_open():
		_show_hint()
		return false
	_open = true
	if hurtbox != null:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	_play_sfx(&"gate_transition", global_position)
	opened.emit(kind)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_property(self, "scale", Vector2(1.0, 0.15), 0.25)
	tween.chain().tween_callback(queue_free)
	return true


## 当前生效组合的词条等级表；没有注入时返回空表（等价于打不开）。
func _current_trait_levels() -> Dictionary:
	if not trait_levels_provider.is_valid():
		return {}
	var entries: Variant = trait_levels_provider.call()
	if entries is Array:
		return SecretDoor.levels_from(entries as Array)
	if entries is Dictionary:
		return entries as Dictionary
	return {}


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载（与 player.gd 一致）。
func _play_sfx(id: StringName, position: Vector2 = Vector2.INF) -> void:
	var manager: Node = get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.call("play_sfx", id, position)


func _build_hurtbox() -> void:
	if health != null:
		return
	health = HealthComponent.new()
	health.name = "Health"
	health.max_health = GATE_HEALTH
	add_child(health)
	health.damaged.connect(_on_damaged)
	# 受击盒必须带着 health 进场：CombatHurtbox._ready 会校验它。
	hurtbox = CombatHurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = HURTBOX_LAYER
	hurtbox.collision_mask = 0
	hurtbox.team = ENEMY_TEAM
	hurtbox.health = health
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(HURTBOX_RADIUS * 2.0, HURTBOX_RADIUS * 2.0)
	shape.shape = box
	hurtbox.add_child(shape)
	add_child(hurtbox)


## 被武器敲到时按当前词条判定：够条件就开，不够就提示。
func _on_damaged(_hit: CombatHit, _actual_damage: float) -> void:
	if _open:
		return
	if attempt_open():
		return
	_shake = 1.0
	if _flash != null and _flash.is_valid():
		_flash.kill()
	modulate = Color(0.62, 0.66, 0.72)
	_flash = create_tween()
	_flash.tween_property(self, "modulate", Color.WHITE, 0.18)


func _show_hint() -> void:
	_hint_remaining = HINT_DURATION
	queue_redraw()


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 6.0, 0.0)
	if _hint_remaining > 0.0:
		_hint_remaining = maxf(_hint_remaining - delta, 0.0)
	if _shake > 0.0 or _hint_remaining > 0.0:
		queue_redraw()


## 视觉：一堵带锁的石墙，上方浮出所需词条；缺词条时红字提示。
func _draw() -> void:
	if _open:
		return
	var offset: Vector2 = Vector2(sin(_shake * 40.0) * 2.0, 0.0) if _shake > 0.0 else Vector2.ZERO
	var body := Rect2(Vector2(-15.0, -20.0) + offset, Vector2(30.0, 36.0))
	draw_rect(Rect2(Vector2(-16.0, 15.0), Vector2(32.0, 4.0)), Color(0.05, 0.06, 0.07, 0.35))
	draw_rect(body, Color(0.30, 0.31, 0.36))
	draw_rect(body, Color(0.16, 0.17, 0.21), false, 2.0)
	# 砖缝
	draw_line(Vector2(-15.0, -8.0) + offset, Vector2(15.0, -8.0) + offset, Color(0.20, 0.21, 0.25), 1.0)
	draw_line(Vector2(-15.0, 4.0) + offset, Vector2(15.0, 4.0) + offset, Color(0.20, 0.21, 0.25), 1.0)
	# 锁孔：条件满足时金色，否则灰白
	var lock_color: Color = Color(1.0, 0.84, 0.36) if can_open() else Color(0.68, 0.70, 0.76)
	draw_circle(Vector2(0.0, -2.0) + offset, 4.0, lock_color)
	draw_rect(Rect2(Vector2(-1.5, -2.0) + offset, Vector2(3.0, 7.0)), lock_color)
	# Node2D 没有主题字体，用引擎兜底字体画需求提示。
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var label: String = SecretDoor.requirement_text(kind)
	var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x
	draw_string(font, Vector2(-width * 0.5, -26.0) + offset, label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.90, 0.92, 0.96))
	if _hint_remaining > 0.0:
		var hint := "缺少「%s」词条" % SecretDoor.trait_name_of(kind)
		var hint_width: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x
		draw_string(font, Vector2(-hint_width * 0.5, -42.0) + offset, hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(1.0, 0.52, 0.46))
