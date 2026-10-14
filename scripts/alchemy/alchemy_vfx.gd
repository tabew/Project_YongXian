class_name AlchemyVfx
extends Node2D

## 炼金表现层：替换爆发 / 词条反应 / 过载爆炸的可视化。
##
## 图形全部用代码生成（Line2D 圆环 + CPUParticles2D），不依赖美术资源；
## 只接收数值与 id，不做任何炼金计算，可以在测试里单独实例化验证。

## 反应 id → 表现主色；未列出的反应回退到默认色。
const REACTION_COLORS: Dictionary = {
	&"poison_smoke": Color("8fd14f"),
	&"steam_burst": Color("cfe9ff"),
	&"magnetic_field": Color("7fd4ff"),
	&"corrosive_sunder": Color("b6e26a"),
	&"skeleton_summon": Color("e6e0c8"),
	&"annihilation": Color("f0e6ff"),
	&"dust_storm": Color("e0c48a"),
	&"deflagration": Color("ff9a3c"),
	&"fire_storm": Color("ff7a2f"),
	&"blizzard": Color("bfe8ff"),
	&"thunderstorm": Color("a9c6ff"),
	&"ice_sheet": Color("cfeeff"),
	&"holy_flame": Color("fff2b0"),
	&"dark_venom": Color("9b6bd6"),
	&"toxic_blood": Color("a34f6b"),
	&"frostbite_bleed": Color("9fd6e8"),
	&"parasite_spur": Color("cfd98a"),
	&"soul_drain": Color("c9a7ff"),
	&"soul_devour": Color("8f6bd6"),
	&"soul_disorder": Color("b9a0e0"),
	&"bone_char": Color("8f8577"),
	&"blood_bone": Color("c76a6a"),
	&"acid_venom": Color("b4d94f"),
	&"bone_dissolve": Color("d6cfae"),
	&"magnetic_bone": Color("a8d8e8"),
	&"soul_magnet": Color("b8a6f0"),
	&"glass_forge": Color("cfe8f2"),
	&"acid_etch": Color("c2de6a"),
	&"sand_bone": Color("e6d5a8"),
	&"purify": Color("fff8d0"),
	&"holy_blood": Color("ffd6c0"),
	&"dark_blood": Color("a05a8f"),
}

## 效果标签 → 兜底颜色；没有反应时用第一个标签取色。
const TAG_COLORS: Dictionary = {
	&"fire": Color("ff8a3c"),
	&"poison": Color("8fd14f"),
	&"ice": Color("bfe8ff"),
	&"electric": Color("ffe86a"),
	&"acid": Color("b4d94f"),
	&"magnet": Color("7fd4ff"),
	&"soul": Color("c9a7ff"),
	&"bone": Color("e6e0c8"),
	&"blood": Color("e05a6a"),
	&"wind": Color("c8f0e0"),
	&"sand": Color("e0c48a"),
	&"light": Color("fff2b0"),
	&"dark": Color("9b6bd6"),
}

const DEFAULT_COLOR: Color = Color("ffcf7a")
const RING_SEGMENTS: int = 32
## 爆发基准半径（像素）。
const BURST_BASE_RADIUS: float = 26.0
const BURST_SECONDS: float = 0.45
const REACTION_SECONDS: float = 0.6
const BLAST_SECONDS: float = 0.55

## 当前活跃的表现节点，供测试与调试检查。
var _effects: Array[Node2D] = []


## 替换爆发：旧效果以 50% 强度爆发一次，并逐个触发词条反应。
func burst(combo: BrewCombo, power: float, reactions: Array) -> void:
	var strength: float = clampf(power, 0.3, 3.0)
	_spawn_ring(burst_color(combo, reactions), BURST_BASE_RADIUS * strength, BURST_SECONDS)
	for reaction: Dictionary in reactions:
		_spawn_puff(reaction_color(StringName(reaction.get("id", &""))), strength, REACTION_SECONDS)


## 过载爆炸：红色大环 + 冲击粒子。
func overload_blast(radius_pixels: float) -> void:
	var radius: float = maxf(radius_pixels, BURST_BASE_RADIUS)
	_spawn_ring(Color("ff3b2f"), radius, BLAST_SECONDS)
	_spawn_puff(Color("ff7a2f"), clampf(radius / BURST_BASE_RADIUS, 0.5, 4.0), BLAST_SECONDS)


## 反应 id 对应的表现色。
static func reaction_color(id: StringName) -> Color:
	return REACTION_COLORS.get(id, DEFAULT_COLOR)


## 爆发主色：优先取第一个反应的颜色，其次取第一个效果标签的颜色。
static func burst_color(combo: BrewCombo, reactions: Array) -> Color:
	for reaction: Dictionary in reactions:
		var id: StringName = StringName(reaction.get("id", &""))
		if REACTION_COLORS.has(id):
			return REACTION_COLORS[id]
	if combo != null:
		for tag: StringName in combo.effect_tags:
			if TAG_COLORS.has(tag):
				return TAG_COLORS[tag]
	return DEFAULT_COLOR


## 活跃表现节点数（测试用）。
func active_effect_count() -> int:
	_prune()
	return _effects.size()


## ── 内部 ────────────────────────────────────────────────────────────────

func _prune() -> void:
	var alive: Array[Node2D] = []
	for effect: Node2D in _effects:
		if is_instance_valid(effect) and not effect.is_queued_for_deletion():
			alive.append(effect)
	_effects = alive


func _spawn_ring(color: Color, radius: float, seconds: float) -> void:
	var ring: Line2D = Line2D.new()
	ring.name = "BurstRing"
	ring.width = 3.0
	ring.default_color = color
	ring.closed = true
	for index: int in range(RING_SEGMENTS):
		var angle: float = TAU * float(index) / float(RING_SEGMENTS)
		ring.add_point(Vector2(cos(angle), sin(angle)) * radius)
	add_child(ring)
	_effects.append(ring)
	if not is_inside_tree():
		return
	ring.scale = Vector2(0.25, 0.25)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2.ONE, seconds)
	tween.tween_property(ring, "modulate:a", 0.0, seconds)
	tween.chain().tween_callback(ring.queue_free)


func _spawn_puff(color: Color, strength: float, seconds: float) -> void:
	var puff: CPUParticles2D = CPUParticles2D.new()
	puff.name = "ReactionPuff"
	puff.one_shot = true
	puff.amount = 14
	puff.lifetime = seconds
	puff.explosiveness = 1.0
	puff.direction = Vector2.UP
	puff.spread = 180.0
	puff.gravity = Vector2.ZERO
	puff.initial_velocity_min = 40.0 * strength
	puff.initial_velocity_max = 90.0 * strength
	puff.scale_amount_min = 0.5
	puff.scale_amount_max = 1.2
	puff.color = color
	puff.texture = soft_dot_texture()
	puff.emitting = true
	add_child(puff)
	_effects.append(puff)
	if not is_inside_tree():
		return
	get_tree().create_timer(seconds + 0.15).timeout.connect(puff.queue_free)


static var _dot_texture: ImageTexture = null


## 柔边圆点贴图：粒子共用一张，避免每个表现各建一张。
static func soft_dot_texture() -> ImageTexture:
	if _dot_texture != null:
		return _dot_texture
	var size: int = 8
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center: float = float(size - 1) * 0.5
	for y: int in range(size):
		for x: int in range(size):
			var distance: float = Vector2(float(x), float(y)).distance_to(Vector2(center, center))
			var alpha: float = clampf(1.0 - distance / (center + 0.5), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * alpha))
	_dot_texture = ImageTexture.create_from_image(image)
	return _dot_texture
