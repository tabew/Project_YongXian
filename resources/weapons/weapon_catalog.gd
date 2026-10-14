class_name WeaponCatalog
extends RefCounted

## 武器扩展配置表（唯一真源）：斧 / 锤 / 矛 / 匕首 / 镰刀 / 拳套 / 鞭 / 盾 / 巨剑。
## 「剑」沿用仓库里已有的 longsword.tres，不在这张表里重复定义。
##
## 全部复用现有的 SwingWeaponDefinition + swing_attack.tscn，只靠参数区分手感；
## 刀身贴图用代码生成（不依赖美术资源），所以新增武器只改这张表。

const ATTACK_SCENE: String = "res://scenes/weapons/swing_attack.tscn"

const WEAPONS: Array[Dictionary] = [
	{"id": &"axe", "name": "斧", "desc": "慢而重，中距劈砍，亲和爆炸 / 回旋",
		"damage": 24.0, "knockback": 160.0, "crit": 0.05, "crit_mult": 2.1,
		"windup": 0.16, "active": 0.22, "recovery": 0.32, "reuse": 0.06,
		"blade_length": 40.0, "blade_width": 10.0, "arc": 150.0, "hand": 10.0,
		"tint": Color("c8b8a0"), "trail": Color(0.88, 0.80, 0.66, 0.42)},
	{"id": &"hammer", "name": "锤", "desc": "最慢最重，大范围震击，亲和地震 / 酸泥",
		"damage": 30.0, "knockback": 220.0, "crit": 0.04, "crit_mult": 2.0,
		"windup": 0.20, "active": 0.24, "recovery": 0.40, "reuse": 0.08,
		"blade_length": 44.0, "blade_width": 14.0, "arc": 170.0, "hand": 11.0,
		"tint": Color("9aa0a8"), "trail": Color(0.74, 0.78, 0.84, 0.42)},
	{"id": &"spear", "name": "长矛", "desc": "超长突刺，窄弧高伤",
		"damage": 22.0, "knockback": 150.0, "crit": 0.05, "crit_mult": 2.0,
		"windup": 0.12, "active": 0.16, "recovery": 0.26, "reuse": 0.05,
		"blade_length": 62.0, "blade_width": 5.0, "arc": 40.0, "hand": 11.0,
		"tint": Color("d8c9a8"), "trail": Color(0.85, 0.80, 0.65, 0.40)},
	{"id": &"dagger", "name": "匕首", "desc": "极快短打，低伤高频",
		"damage": 9.0, "knockback": 70.0, "crit": 0.12, "crit_mult": 2.2,
		"windup": 0.04, "active": 0.10, "recovery": 0.10, "reuse": 0.02,
		"blade_length": 20.0, "blade_width": 5.0, "arc": 120.0, "hand": 7.0,
		"tint": Color("cfd6e0"), "trail": Color(0.72, 0.92, 1.0, 0.45)},
	{"id": &"scythe", "name": "镰刀", "desc": "超大回旋，慢而重",
		"damage": 26.0, "knockback": 140.0, "crit": 0.06, "crit_mult": 2.0,
		"windup": 0.16, "active": 0.26, "recovery": 0.34, "reuse": 0.06,
		"blade_length": 46.0, "blade_width": 8.0, "arc": 240.0, "hand": 10.0,
		"tint": Color("9fd6b0"), "trail": Color(0.62, 0.90, 0.70, 0.42)},
	{"id": &"gauntlet", "name": "拳套", "desc": "贴身连击，范围最小",
		"damage": 7.0, "knockback": 90.0, "crit": 0.10, "crit_mult": 2.0,
		"windup": 0.03, "active": 0.08, "recovery": 0.08, "reuse": 0.02,
		"blade_length": 14.0, "blade_width": 8.0, "arc": 100.0, "hand": 6.0,
		"tint": Color("c9a06a"), "trail": Color(0.90, 0.72, 0.45, 0.40)},
	{"id": &"whip", "name": "鞭", "desc": "极长扫击，细而广",
		"damage": 14.0, "knockback": 100.0, "crit": 0.07, "crit_mult": 2.0,
		"windup": 0.10, "active": 0.24, "recovery": 0.30, "reuse": 0.05,
		"blade_length": 70.0, "blade_width": 4.0, "arc": 300.0, "hand": 12.0,
		"tint": Color("b58a5a"), "trail": Color(0.80, 0.60, 0.35, 0.38)},
	{"id": &"shield", "name": "盾", "desc": "重击强击退，短而宽",
		"damage": 20.0, "knockback": 260.0, "crit": 0.03, "crit_mult": 1.8,
		"windup": 0.18, "active": 0.20, "recovery": 0.36, "reuse": 0.06,
		"blade_length": 24.0, "blade_width": 14.0, "arc": 90.0, "hand": 8.0,
		"tint": Color("8f9aa8"), "trail": Color(0.70, 0.76, 0.84, 0.40)},
	{"id": &"greatsword", "name": "巨剑", "desc": "长而宽，一击最重",
		"damage": 34.0, "knockback": 190.0, "crit": 0.05, "crit_mult": 2.4,
		"windup": 0.20, "active": 0.28, "recovery": 0.40, "reuse": 0.08,
		"blade_length": 56.0, "blade_width": 12.0, "arc": 200.0, "hand": 12.0,
		"tint": Color("e0d2b0"), "trail": Color(0.95, 0.86, 0.62, 0.45)},
]

static var _definitions: Dictionary = {}


static func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in WEAPONS:
		ids.append(entry["id"])
	return ids


static func has_weapon(id: StringName) -> bool:
	for entry: Dictionary in WEAPONS:
		if entry["id"] == id:
			return true
	return false


## 按配置生成武器定义；未知 id 返回空定义（id 为空）。
static func definition_of(id: StringName) -> SwingWeaponDefinition:
	if _definitions.has(id):
		return _definitions[id]
	for entry: Dictionary in WEAPONS:
		if entry["id"] != id:
			continue
		var definition: SwingWeaponDefinition = _build(entry)
		_definitions[id] = definition
		return definition
	# 未知 id 返回空定义（id 置空），调用方据此判错。
	var empty: SwingWeaponDefinition = SwingWeaponDefinition.new()
	empty.id = &""
	return empty


static func all_definitions() -> Array[WeaponDefinition]:
	var result: Array[WeaponDefinition] = []
	for entry: Dictionary in WEAPONS:
		result.append(definition_of(entry["id"]))
	return result


## ── 内部 ────────────────────────────────────────────────────────────────

static func _build(entry: Dictionary) -> SwingWeaponDefinition:
	var definition: SwingWeaponDefinition = SwingWeaponDefinition.new()
	var texture: ImageTexture = build_texture(entry)
	definition.id = entry["id"]
	definition.display_name = String(entry.get("name", String(entry["id"])))
	definition.icon = texture
	definition.attack_scene = load(ATTACK_SCENE) as PackedScene
	definition.damage = float(entry.get("damage", 18.0))
	definition.critical_chance = float(entry.get("crit", 0.04))
	definition.critical_multiplier = float(entry.get("crit_mult", 2.0))
	definition.knockback = float(entry.get("knockback", 110.0))
	definition.hit_mask = 4
	definition.windup_seconds = float(entry.get("windup", 0.08))
	definition.active_seconds = float(entry.get("active", 0.18))
	definition.recovery_seconds = float(entry.get("recovery", 0.20))
	definition.reuse_delay = float(entry.get("reuse", 0.04))
	definition.auto_repeat = true
	definition.hand_distance = float(entry.get("hand", 9.0))
	definition.blade_length = float(entry.get("blade_length", 38.0))
	definition.blade_width = float(entry.get("blade_width", 7.0))
	definition.blade_inset = definition.blade_length * 0.15
	definition.arc_degrees = float(entry.get("arc", 150.0))
	definition.aim_offset_degrees = 0.0
	definition.texture = texture
	definition.texture_grip = grip_of(entry)
	definition.trail_color = entry.get("trail", Color(0.72, 0.92, 1.0, 0.45))
	definition.trail_degrees = 42.0
	return definition


## 刀身贴图：左侧握把 + 右侧刀身，刀身中线提亮、上下缘压暗。
static func build_texture(entry: Dictionary) -> ImageTexture:
	var blade_length: int = maxi(int(round(float(entry.get("blade_length", 38.0)))), 6)
	var height: int = maxi(int(round(float(entry.get("blade_width", 7.0)))), 3)
	var grip_width: int = maxi(int(round(float(height) * 1.2)), 3)
	var total_width: int = grip_width + blade_length
	var tint: Color = entry.get("tint", Color("cfd6e0"))
	var grip_color: Color = tint.darkened(0.62)
	var edge: Color = tint.lightened(0.35)
	var rim: Color = tint.darkened(0.30)
	var image: Image = Image.create(total_width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var mid: int = height / 2
	for y: int in range(height):
		for x: int in range(total_width):
			if x < grip_width:
				image.set_pixel(x, y, grip_color)
			elif y == 0 or y == height - 1:
				image.set_pixel(x, y, rim)
			elif y == mid:
				image.set_pixel(x, y, edge)
			else:
				image.set_pixel(x, y, tint)
	return ImageTexture.create_from_image(image)


## 握把枢轴：必须落在贴图内，取握把段中心。
static func grip_of(entry: Dictionary) -> Vector2:
	var height: int = maxi(int(round(float(entry.get("blade_width", 7.0)))), 3)
	var grip_width: int = maxi(int(round(float(height) * 1.2)), 3)
	return Vector2(float(grip_width) * 0.5, float(height) * 0.5)
