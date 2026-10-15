class_name Workshop
extends Node2D

## 炼金工坊（局外初始房间）：自由走动，靠近交互点按 E 打开界面。
##
## 流程：炼金工坊 → 出发门 → 局内 Run → 死亡/通关 → 结算灵感 → 回工坊 → 用灵感买永久升级。
##
## 本节点只做编排：房间绘制、交互点高亮、面板开关、出发。
## 数值与规则都在 resources/workshop 与 resources/inspiration 里。

const GAME_SCENE: String = "res://scenes/game/game_world.tscn"
## 训练场试验场：确认前往后切过去的独立空旷场地（假人 + 无限材料）。
const TRAINING_ARENA_SCENE: String = "res://scenes/workshop/training_arena.tscn"
const ALCHEMY_HUD: PackedScene = preload("res://scenes/ui/alchemy/alchemy_hud.tscn")
const CAMERA_ZOOM: Vector2 = Vector2(1.4, 1.4)
## 玩家离墙的最小距离，避免贴到边界外。
const WALL_MARGIN: float = 26.0

@onready var player: PlayerCharacter = $Player

var _manager: InspirationManager = null
var _interactables: Array[WorkshopInteractable] = []
## panel_id -> WorkshopPanel
var _panels: Dictionary = {}
var _active_panel: WorkshopPanel = null
var _current: WorkshopInteractable = null
var _counter_label: Label = null
var _prompt_label: Label = null
## 随身炼金台 HUD：工坊里没有怪物，按 E 会打开完整炼金台。
var _alchemy_hud: AlchemyHud = null
var _hud_root: Control = null


func _ready() -> void:
	_manager = get_node_or_null("/root/Inspiration") as InspirationManager
	_place_player()
	_build_interactables()
	_build_hud()
	_build_panels()
	if _manager != null:
		_manager.apply_to_alchemy_station(player.alchemy_station)
		_manager.permanent_changed.connect(_refresh_counter)
	_refresh_counter()
	queue_redraw()


func _place_player() -> void:
	var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.zoom = CAMERA_ZOOM
	player.global_position = WorkshopLayout.SPAWN
	player.terrain_source = null
	player.active_map = null


func _build_interactables() -> void:
	for entry: Dictionary in WorkshopLayout.POINTS:
		var point := WorkshopInteractable.new()
		point.id = StringName(entry["id"])
		point.display_name = String(entry["name"])
		point.panel_id = StringName(entry["panel"])
		point.placeholder = not bool(entry.get("implemented", false))
		point.position = entry["position"]
		add_child(point)
		_interactables.append(point)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WorkshopHud"
	layer.layer = 2
	add_child(layer)

	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	var title := Label.new()
	title.text = "炼金工坊"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("f2d98a"))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 18.0
	title.offset_top = 12.0
	title.offset_right = 320.0
	title.offset_bottom = 46.0

	_counter_label = Label.new()
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter_label.add_theme_font_size_override("font_size", 20)
	_counter_label.add_theme_color_override("font_color", Color("ffd76a"))
	_counter_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_counter_label.add_theme_constant_override("shadow_offset_x", 2)
	_counter_label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(_counter_label)
	_counter_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_counter_label.offset_left = -320.0
	_counter_label.offset_top = 12.0
	_counter_label.offset_right = -18.0
	_counter_label.offset_bottom = 44.0

	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_color", Color("ffe9a8"))
	_prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_prompt_label.add_theme_constant_override("shadow_offset_x", 2)
	_prompt_label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(_prompt_label)
	_prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -300.0
	_prompt_label.offset_top = -96.0
	_prompt_label.offset_right = 300.0
	_prompt_label.offset_bottom = -68.0

	var hint := Label.new()
	hint.text = "WASD 移动　·　靠近交互点按 E　·　无交互点时按 E 打开随身炼金台　·　Esc 关闭"
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

	# 随身炼金台：非战斗（工坊没有怪物）时按 E 打开完整炼金台。
	_alchemy_hud = ALCHEMY_HUD.instantiate() as AlchemyHud
	_alchemy_hud.name = "Alchemy"
	root.add_child(_alchemy_hud)
	_alchemy_hud.bind(player.alchemy_station)

	_hud_root = root


func _build_panels() -> void:
	_register_panel(&"upgrade", UpgradePanel.new())
	_register_panel(&"materials", MaterialVaultPanel.new())
	_register_panel(&"difficulty", DifficultyAltarPanel.new())
	_register_panel(&"departure", DepartureGatePanel.new())
	_register_panel(&"training", TrainingGroundPanel.new())

	var upgrade_panel: UpgradePanel = _panels[&"upgrade"] as UpgradePanel
	upgrade_panel.purchased.connect(_on_upgrade_purchased)
	var departure_panel: DepartureGatePanel = _panels[&"departure"] as DepartureGatePanel
	departure_panel.weapon_definitions = _available_weapon_definitions()
	departure_panel.start_run_requested.connect(start_run)
	departure_panel.weapon_selected.connect(_on_weapon_selected)
	var training_panel: TrainingGroundPanel = _panels[&"training"] as TrainingGroundPanel
	training_panel.travel_requested.connect(_on_training_travel)


## 可选武器定义：主角轮换列表里的 .tres 真武器优先，再补武器配置表里还没有的。
## 出发门要显示名字与数值，所以传定义本身；武器配置表查不到 .tres 真武器。
func _available_weapon_definitions() -> Array[WeaponDefinition]:
	var result: Array[WeaponDefinition] = []
	for definition: WeaponDefinition in player.weapon_loadout:
		if definition == null or definition.id == &"":
			continue
		result.append(definition)
	for definition: WeaponDefinition in WeaponCatalog.all_definitions():
		if definition == null or definition.id == &"":
			continue
		var exists: bool = false
		for entry: WeaponDefinition in result:
			if entry.id == definition.id:
				exists = true
				break
		if not exists:
			result.append(definition)
	return result


func _register_panel(id: StringName, panel: WorkshopPanel) -> void:
	panel.setup(_manager)
	panel.close_requested.connect(_on_panel_closed)
	_hud_root.add_child(panel)
	_panels[id] = panel


## 只留接口的交互点：打开时临时建一个占位面板。
func _placeholder_panel(entry: Dictionary) -> WorkshopPanel:
	var panel := PlaceholderPanel.new()
	panel.point_name = String(entry.get("name", "未实现"))
	panel.planned = String(entry.get("planned", "后续版本实现。"))
	panel.setup(_manager)
	panel.close_requested.connect(_on_panel_closed)
	_hud_root.add_child(panel)
	return panel


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载（与 player.gd 一致）。
func _play_sfx(id: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.call("play_sfx", id)


# ------------------------------------------------------------ 交互

func _input(event: InputEvent) -> void:
	if _active_panel != null:
		return
	if event.is_action_pressed("alchemy_brew") and not event.is_echo():
		if _current != null:
			_open_interactable(_current)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_clamp_player()
	_update_nearest()


func _clamp_player() -> void:
	var half: Vector2 = WorkshopLayout.ROOM_HALF - Vector2(WALL_MARGIN, WALL_MARGIN)
	player.global_position = Vector2(
		clampf(player.global_position.x, -half.x, half.x),
		clampf(player.global_position.y, -half.y, half.y),
	)


func _update_nearest() -> void:
	var nearest: WorkshopInteractable = null
	var best: float = INF
	for point: WorkshopInteractable in _interactables:
		if point.can_interact_from(player.global_position):
			var distance: float = point.global_position.distance_to(player.global_position)
			if distance < best:
				best = distance
				nearest = point
	if nearest == _current:
		return
	if _current != null:
		_current.set_highlighted(false)
	_current = nearest
	if _current != null:
		_current.set_highlighted(true)
		_prompt_label.text = "E · %s" % _current.display_name
	else:
		_prompt_label.text = ""


func _open_interactable(point: WorkshopInteractable) -> void:
	_play_sfx(&"ui_click")
	var panel: WorkshopPanel = _panels.get(point.panel_id, null) as WorkshopPanel
	if panel == null:
		var entry: Dictionary = WorkshopLayout.find_point(point.id)
		panel = _placeholder_panel(entry)
	_active_panel = panel
	panel.open()
	get_tree().paused = true


func _on_panel_closed() -> void:
	_active_panel = null
	get_tree().paused = false
	_refresh_counter()


func _on_upgrade_purchased(_id: StringName) -> void:
	if _manager != null:
		_manager.apply_to_alchemy_station(player.alchemy_station)


func _refresh_counter() -> void:
	if _counter_label == null or _manager == null:
		return
	_counter_label.text = "[灵感] %d" % _manager.state.inspiration


# ------------------------------------------------------------ 出发

## 出发门：带上武器 / 材料 / 难度进入局内。
func start_run() -> void:
	if _manager == null:
		return
	get_tree().paused = false
	_active_panel = null
	_manager.start_run()
	_manager.apply_to_alchemy_station(player.alchemy_station)
	_apply_loadout()
	GameState.start_new_world()
	SceneManager.change_scene(GAME_SCENE)


## 出发配置（武器 + 携带材料）由主角自己套用：局内会重建主角，两处走同一份逻辑。
func _apply_loadout() -> void:
	player.apply_run_loadout()


## 出发门选了武器：立刻套到工坊主角身上，选完当场就能看到生效（局内会再套一次）。
func _on_weapon_selected(weapon_id: StringName) -> void:
	player.equip_weapon_by_id(weapon_id)


# ------------------------------------------------------------ 训练场

## 训练场交互点：确认前往 → 切到独立的空旷试验场（返回与补材料都在那边）。
func _on_training_travel() -> void:
	_play_sfx(&"ui_click")
	get_tree().paused = false
	_active_panel = null
	SceneManager.change_scene(TRAINING_ARENA_SCENE)


func _draw() -> void:
	var half: Vector2 = WorkshopLayout.ROOM_HALF
	var floor_rect := Rect2(-half, half * 2.0)
	draw_rect(floor_rect, Color(0.15, 0.14, 0.12))

	# 地板网格，方便看清走动范围。
	var step: float = 40.0
	var grid_color := Color(0.20, 0.19, 0.16)
	var x: float = -half.x
	while x <= half.x:
		draw_line(Vector2(x, -half.y), Vector2(x, half.y), grid_color, 1.0)
		x += step
	var y: float = -half.y
	while y <= half.y:
		draw_line(Vector2(-half.x, y), Vector2(half.x, y), grid_color, 1.0)
		y += step

	draw_rect(floor_rect, Color(0.36, 0.31, 0.22), false, WorkshopLayout.WALL_THICKNESS)

	# 出发门单独画一条门框。
	var gate: Vector2 = WorkshopLayout.position_of(&"departure_gate")
	draw_rect(Rect2(gate + Vector2(-34.0, 6.0), Vector2(68.0, 12.0)), Color(0.62, 0.52, 0.28))
