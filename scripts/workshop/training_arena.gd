class_name TrainingArena
extends Node2D

## 训练场试验场：一块独立的空旷场地，用来试炼金。
##
## 场地里有：
## - 一只不会移动、血量高到打不死的假人，旁边挂一个 DPS 计数器；
## - 右侧常驻的无限材料面板，点一下补满一种材料；
## - 左上角的「返回工坊」按钮。
##
## 本节点只做编排：场地绘制、玩家落位、HUD、材料补充与 DPS 统计。

const WORKSHOP_SCENE: String = "res://scenes/workshop/workshop.tscn"
const ALCHEMY_HUD: PackedScene = preload("res://scenes/ui/alchemy/alchemy_hud.tscn")
const CAMERA_ZOOM: Vector2 = Vector2(1.4, 1.4)
## 场地半宽 / 半高（像素）。
const ARENA_HALF: Vector2 = Vector2(420.0, 320.0)
## 墙体厚度。
const WALL_THICKNESS: float = 8.0
## 玩家离墙的最小距离，避免贴到边界外。
const WALL_MARGIN: float = 26.0
## 玩家出生点。
const SPAWN: Vector2 = Vector2(0.0, 170.0)
## 假人血量：大到打不死，只用来量伤害。
const DUMMY_MAX_HEALTH: float = 1000000000000.0
## DPS 统计窗口（秒）：只统计最近这段时间的伤害。
const DPS_WINDOW: float = 5.0
## 每次补充的材料数量。
const GRANT_AMOUNT: int = 99
## 材料面板宽度。
const MATERIAL_PANEL_WIDTH: float = 300.0

@onready var player: PlayerCharacter = $Player
@onready var dummy: TrainingDummy = $TrainingDummy

## 假人头顶的 DPS 计数器。
var _dps_label: Label = null
## 伤害样本：[时间, 伤害]，只保留 DPS_WINDOW 内的。
var _damage_samples: Array[Array] = []
## 进场后的累计时间，用作窗口未填满时的分母。
var _elapsed: float = 0.0


func _ready() -> void:
	player.global_position = SPAWN
	player.terrain_source = null
	player.active_map = null
	var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.zoom = CAMERA_ZOOM
	# 进场就套用出发配置，武器与携带材料和工坊 / 局内保持一致。
	player.apply_run_loadout()
	_setup_dummy()
	_build_hud()
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	_clamp_player()
	_update_dps()


## 假人：固定不动 + 血量拉满，只当伤害计量器。
func _setup_dummy() -> void:
	dummy.immobile = true
	dummy.health.max_health = DUMMY_MAX_HEALTH
	dummy.health.reset()
	dummy.health.damaged.connect(_on_dummy_damaged)
	_dps_label = Label.new()
	_dps_label.name = "DpsCounter"
	_dps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dps_label.add_theme_font_size_override("font_size", 14)
	_dps_label.add_theme_color_override("font_color", Color("ffd76a"))
	_dps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_dps_label.add_theme_constant_override("shadow_offset_x", 1)
	_dps_label.add_theme_constant_override("shadow_offset_y", 1)
	_dps_label.position = Vector2(-80.0, -64.0)
	_dps_label.size = Vector2(160.0, 20.0)
	_dps_label.z_index = 5
	_dps_label.text = "DPS 0.0"
	dummy.add_child(_dps_label)


func _on_dummy_damaged(_hit: CombatHit, actual_damage: float) -> void:
	_damage_samples.append([_elapsed, actual_damage])


## DPS：最近 DPS_WINDOW 秒内的总伤害 ÷ 窗口长度（窗口没走满时按已过时间算）。
func _update_dps() -> void:
	if _dps_label == null:
		return
	var cutoff: float = _elapsed - DPS_WINDOW
	while not _damage_samples.is_empty() and float(_damage_samples[0][0]) < cutoff:
		_damage_samples.remove_at(0)
	var total: float = 0.0
	for sample: Array in _damage_samples:
		total += float(sample[1])
	var span: float = minf(DPS_WINDOW, maxf(_elapsed, 0.1))
	_dps_label.text = "DPS %.1f" % (total / span)


func _clamp_player() -> void:
	var half: Vector2 = ARENA_HALF - Vector2(WALL_MARGIN, WALL_MARGIN)
	player.global_position = Vector2(
		clampf(player.global_position.x, -half.x, half.x),
		clampf(player.global_position.y, -half.y, half.y),
	)


# ------------------------------------------------------------ HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ArenaHud"
	layer.layer = 2
	add_child(layer)

	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	var title := Label.new()
	title.text = "训练场 · 试验场"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("f2d98a"))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 18.0
	title.offset_top = 12.0
	title.offset_right = 340.0
	title.offset_bottom = 46.0

	var back := Button.new()
	back.name = "BackButton"
	back.text = "返回工坊"
	back.mouse_entered.connect(func() -> void: _play_sfx(&"ui_hover"))
	back.pressed.connect(_on_back_pressed)
	root.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	back.offset_left = 18.0
	back.offset_top = 52.0
	back.offset_right = 158.0
	back.offset_bottom = 88.0

	var hint := Label.new()
	hint.text = "WASD 移动　·　左键 攻击（假人打不死）　·　E 随身炼金台　·　右侧点一下补材料"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 18.0
	hint.offset_top = -30.0
	hint.offset_right = 900.0
	hint.offset_bottom = -8.0

	_build_material_panel(root)

	# 随身炼金台：场地里没有怪物，按 E 直接打开完整炼金台。
	var alchemy_hud: AlchemyHud = ALCHEMY_HUD.instantiate() as AlchemyHud
	alchemy_hud.name = "Alchemy"
	root.add_child(alchemy_hud)
	alchemy_hud.bind(player.alchemy_station)


## 右侧常驻的无限材料面板：每种材料一行按钮，点一下补 GRANT_AMOUNT 个。
func _build_material_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "MaterialPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.12, 0.94)
	style.border_color = Color(0.46, 0.40, 0.24, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -MATERIAL_PANEL_WIDTH - 18.0
	panel.offset_right = -18.0
	panel.offset_top = 18.0
	panel.offset_bottom = -40.0

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = "无限材料（点一下补 %d）" % GRANT_AMOUNT
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", Color("c9b26a"))
	column.add_child(heading)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)

	for material_id: int in MaterialCatalog.all_ids():
		var button := Button.new()
		button.text = "%s ×%d" % [MaterialCatalog.display_name_of(material_id), GRANT_AMOUNT]
		button.custom_minimum_size = Vector2(0.0, 26.0)
		button.mouse_entered.connect(func() -> void: _play_sfx(&"ui_hover"))
		button.pressed.connect(_on_grant.bind(material_id))
		grid.add_child(button)


func _on_grant(material_id: int) -> void:
	player.alchemy_station.absorb_material(material_id, GRANT_AMOUNT)
	_play_sfx(&"pickup_material")


func _on_back_pressed() -> void:
	_play_sfx(&"ui_click")
	get_tree().paused = false
	_change_scene(WORKSHOP_SCENE)


## 场景管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载（与 player.gd 一致）。
func _change_scene(scene_path: String) -> void:
	var manager: Node = get_node_or_null("/root/SceneManager")
	if manager != null:
		manager.call("change_scene", scene_path)


## 音频管理器同样是自动加载单例，用运行期查找。
func _play_sfx(id: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.call("play_sfx", id)


func _draw() -> void:
	var half: Vector2 = ARENA_HALF
	var floor_rect := Rect2(-half, half * 2.0)
	draw_rect(floor_rect, Color(0.13, 0.15, 0.13))

	# 地板网格，方便看清走动范围。
	var step: float = 40.0
	var grid_color := Color(0.18, 0.20, 0.18)
	var x: float = -half.x
	while x <= half.x:
		draw_line(Vector2(x, -half.y), Vector2(x, half.y), grid_color, 1.0)
		x += step
	var y: float = -half.y
	while y <= half.y:
		draw_line(Vector2(-half.x, y), Vector2(half.x, y), grid_color, 1.0)
		y += step

	draw_rect(floor_rect, Color(0.36, 0.31, 0.22), false, WALL_THICKNESS)
