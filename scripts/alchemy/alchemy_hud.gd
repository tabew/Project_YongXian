extends Control

class_name AlchemyHud

## 炼金台 P0 基础 UI：武器旁常驻状态条 + 非战斗完整面板 + 战斗中慢动作轮盘。
## 布局在代码里创建，避免维护复杂手写 .tscn；只订阅 AlchemyStation，不做数值计算。

const PANEL_SIZE: Vector2 = Vector2(760, 560)
const WHEEL_SIZE: Vector2 = Vector2(520, 470)
const STATUS_X: float = 12.0
const STATUS_Y: float = -64.0
const STATUS_W: float = 280.0
const STATUS_H: float = 56.0
## 武器旁常驻状态环的直径（像素）。
const RING_SIZE: float = 28.0
## 过载红闪的持续时间（秒）。
const FLASH_SECONDS: float = 0.55
## 短按 E 失败等提示的停留时间（秒）。
const TOAST_SECONDS: float = 1.5

## 完整炼金台的页签：背包 / 图鉴 / 预设 / 实验 / 合金，按 Tab（alchemy_cycle）循环。
enum Tab { BAG, COMPENDIUM, PRESET, EXPERIMENT, FORGE }
const TAB_NAMES: Array[String] = ["背包", "图鉴", "预设", "实验", "合金"]

var station: AlchemyStation = null

var _status_panel: PanelContainer
var _status_ring: StatusRing
var _status_effect: Label
var _status_duration_bar: ProgressBar
var _status_heat_bar: ProgressBar
var _status_style: StyleBoxFlat

var _panel: PanelContainer
var _slots_row: HBoxContainer
var _slot_buttons: Array[Button] = []
var _bag_grid: GridContainer
var _pool_label: Label
var _preview_label: Label
var _active_label: Label
var _heat_label: Label

var _wheel: PanelContainer
var _wheel_slots_row: HBoxContainer
var _wheel_slot_buttons: Array[Button] = []
var _wheel_pool_label: Label
## 轮盘预览：相同组合叠加 / 不同组合替换提示。
var _wheel_preview_label: Label
## 轮盘当前生效：组合描述 + 剩余秒数。
var _wheel_active_label: Label
var _wheel_heat_bar: ProgressBar
var _wheel_hint: Label
## 非战斗打开完整炼金台时是否已把游戏世界完全暂停。
var _world_paused: bool = false

var _tab: int = Tab.BAG
var _tab_buttons: Array[Button] = []
var _bag_page: VBoxContainer
var _compendium_page: VBoxContainer
var _preset_page: VBoxContainer
var _compendium_summary_label: Label
var _compendium_list_label: Label
var _preset_rows: VBoxContainer
var _preset_status_labels: Array[Label] = []
var _experiment_page: VBoxContainer
var _experiment_summary_label: Label
var _experiment_list_label: Label
var _forge_page: VBoxContainer
var _forge_summary_label: Label
var _forge_list_label: Label
var _forge_material_grid: GridContainer
var _forge_slot_label: Label
var _curse_label: Label
var _curse_row: HBoxContainer

## 过热警告表现：抖动 / 警告音 / 红闪 / 耳鸣。
var _overload_flash: ColorRect
var _warning_player: AudioStreamPlayer
var _tinnitus_player: AudioStreamPlayer
var _shake_time: float = 0.0
var _flash_remaining: float = 0.0
var _last_warning_level: int = -1
## 短按 E 失败 / 预设不可用等一次性提示。
var _toast_label: Label
var _toast_remaining: float = 0.0


func _ready() -> void:
	# 暂停时仍需渲染面板并接收点击 / Esc，所以本节点必须始终处理。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_build_feedback()
	_build_toast()
	set_process(true)


func bind(target: AlchemyStation) -> void:
	if station != null:
		station.bag_changed.disconnect(_rebuild_bag_buttons)
		station.slots_changed.disconnect(_rebuild_slot_buttons)
		if station.overloaded.is_connected(_on_overloaded):
			station.overloaded.disconnect(_on_overloaded)
		if station.brew_rejected.is_connected(_on_brew_rejected):
			station.brew_rejected.disconnect(_on_brew_rejected)
	station = target
	if station != null:
		station.bag_changed.connect(_rebuild_bag_buttons)
		station.slots_changed.connect(_rebuild_slot_buttons)
		station.overloaded.connect(_on_overloaded)
		station.brew_rejected.connect(_on_brew_rejected)
	_rebuild_slot_buttons()
	_rebuild_bag_buttons()
	_update_all()


func _exit_tree() -> void:
	if not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0
	_set_world_paused(false)
	if station != null:
		station.bag_changed.disconnect(_rebuild_bag_buttons)
		station.slots_changed.disconnect(_rebuild_slot_buttons)
		if station.overloaded.is_connected(_on_overloaded):
			station.overloaded.disconnect(_on_overloaded)
		if station.brew_rejected.is_connected(_on_brew_rejected):
			station.brew_rejected.disconnect(_on_brew_rejected)


## 暂停期间玩家节点不再收到输入，Esc 由常驻的本面板兜底。
func _unhandled_input(event: InputEvent) -> void:
	if station == null or not station.is_menu_open():
		return
	if event.is_action_pressed("alchemy_cancel") and not event.is_echo():
		if station.cancel():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("alchemy_cycle") and not event.is_echo():
		cycle_tab()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if station == null:
		return
	_update_all()
	_update_feedback(_delta)


func _update_all() -> void:
	_update_status()
	# 面板 / 轮盘只在打开时刷新，避免隐藏状态下每帧拼图鉴与预设文本。
	if station.is_menu_open():
		_update_panel()
	if station.is_wheel_open():
		_update_wheel()
	_update_visibility()


## ── 过热警告表现 ────────────────────────────────────────────────────────

func _build_feedback() -> void:
	_overload_flash = ColorRect.new()
	_overload_flash.name = "OverloadFlash"
	_overload_flash.color = Color(0.85, 0.05, 0.05, 0.0)
	_overload_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overload_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overload_flash)
	move_child(_overload_flash, 0)
	_warning_player = AudioStreamPlayer.new()
	_warning_player.stream = _make_tone(880.0, 0.18, 0.5)
	_warning_player.volume_db = -6.0
	add_child(_warning_player)
	_tinnitus_player = AudioStreamPlayer.new()
	_tinnitus_player.stream = _make_tone(3000.0, 1.2, 0.35)
	_tinnitus_player.volume_db = -10.0
	add_child(_tinnitus_player)


func _update_feedback(delta: float) -> void:
	_update_warning_shake(delta)
	if _flash_remaining > 0.0:
		_flash_remaining = maxf(_flash_remaining - delta, 0.0)
	if _overload_flash != null:
		_overload_flash.color.a = clampf(_flash_remaining / FLASH_SECONDS, 0.0, 1.0) * 0.55
	if _toast_remaining > 0.0:
		_toast_remaining = maxf(_toast_remaining - delta, 0.0)
		if _toast_remaining <= 0.0 and _toast_label != null:
			_toast_label.text = ""


## 短按 E 失败 / 预设不可用等即时反馈。
func _on_brew_rejected(reason: String) -> void:
	_show_toast(reason)


## 在状态条上方显示一条限时提示（实验解锁、事故反噬等复用）。
func _show_toast(text: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_remaining = TOAST_SECONDS


## 状态条上方的一次性提示条（默认空）。
func _build_toast() -> void:
	_toast_label = Label.new()
	_toast_label.name = "Toast"
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toast_label.offset_left = STATUS_X + 6.0
	_toast_label.offset_top = STATUS_Y - 24.0
	_toast_label.offset_right = STATUS_X + STATUS_W
	_toast_label.offset_bottom = STATUS_Y - 2.0
	_toast_label.add_theme_font_size_override("font_size", 13)
	_toast_label.add_theme_color_override("font_color", Color("ffb86b"))
	_toast_label.text = ""
	add_child(_toast_label)


## 50~74% 轻微、75~89% 明显、90~99% 剧烈抖动；过载瞬间改走红闪。
func _update_warning_shake(delta: float) -> void:
	var level: int = station.warning_level()
	if level != _last_warning_level:
		if level >= 3 and _audio_available():
			_warning_player.play()
		_last_warning_level = level
	var amplitude: float = _shake_amplitude(level)
	var jitter: Vector2 = Vector2.ZERO
	if amplitude > 0.0:
		_shake_time += delta * (1.0 + float(level) * 0.6)
		jitter = Vector2(sin(_shake_time * 47.0), cos(_shake_time * 61.0)) * amplitude
	_apply_status_offset(jitter)


func _shake_amplitude(level: int) -> float:
	match level:
		1:
			return 1.2
		2:
			return 2.8
		3:
			return 5.0
	return 0.0


func _apply_status_offset(jitter: Vector2) -> void:
	if _status_panel == null:
		return
	_status_panel.offset_left = STATUS_X + jitter.x
	_status_panel.offset_right = STATUS_X + STATUS_W + jitter.x
	_status_panel.offset_top = STATUS_Y + jitter.y
	_status_panel.offset_bottom = STATUS_Y + STATUS_H + jitter.y


## 过载：屏幕红闪 + 耳鸣。
func _on_overloaded(_report: Dictionary) -> void:
	_flash_remaining = FLASH_SECONDS
	if _tinnitus_player != null and _audio_available():
		_tinnitus_player.play()


## 无音频驱动的环境（headless 测试）不播放，避免留下未释放的播放实例。
static func _audio_available() -> bool:
	return DisplayServer.get_name() != "headless"


## 代码生成短音，避免依赖音频资源；带线性衰减包络。
static func _make_tone(frequency: float, duration: float, volume: float) -> AudioStreamWAV:
	const MIX_RATE: int = 22050
	var frames: int = maxi(int(float(MIX_RATE) * duration), 1)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	for index: int in range(frames):
		var t: float = float(index) / float(MIX_RATE)
		var envelope: float = 1.0 - float(index) / float(frames)
		var sample: float = sin(TAU * frequency * t) * volume * envelope
		data.encode_s16(index * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


## ── 构建 ────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = _build_panel()
	_wheel = _build_wheel()
	_status_panel = _build_status()
	add_child(_status_panel)
	add_child(_panel)
	add_child(_wheel)
	_panel.visible = false
	_wheel.visible = false
	_status_panel.add_to_group("alchemy_status")


func _build_status() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "StatusPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = STATUS_X
	panel.offset_top = STATUS_Y
	panel.offset_right = STATUS_X + STATUS_W
	panel.offset_bottom = STATUS_Y + STATUS_H
	_status_style = StyleBoxFlat.new()
	_status_style.bg_color = Color(0.08, 0.09, 0.11, 0.88)
	_status_style.corner_radius_top_left = 6
	_status_style.corner_radius_top_right = 6
	_status_style.corner_radius_bottom_left = 6
	_status_style.corner_radius_bottom_right = 6
	_status_style.content_margin_left = 8
	_status_style.content_margin_right = 8
	_status_style.content_margin_top = 6
	_status_style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", _status_style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var effect_row := HBoxContainer.new()
	effect_row.add_theme_constant_override("separation", 6)
	box.add_child(effect_row)
	_status_ring = StatusRing.new()
	_status_ring.custom_minimum_size = Vector2(RING_SIZE, RING_SIZE)
	_status_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_row.add_child(_status_ring)
	_status_effect = Label.new()
	_status_effect.custom_minimum_size = Vector2(118, 0)
	_status_effect.add_theme_font_size_override("font_size", 13)
	effect_row.add_child(_status_effect)
	_status_duration_bar = ProgressBar.new()
	_status_duration_bar.custom_minimum_size = Vector2(80, 12)
	_status_duration_bar.show_percentage = false
	_status_duration_bar.max_value = 1.0
	effect_row.add_child(_status_duration_bar)
	var heat_row := HBoxContainer.new()
	heat_row.add_theme_constant_override("separation", 6)
	box.add_child(heat_row)
	var heat_name := Label.new()
	heat_name.text = "热"
	heat_name.add_theme_font_size_override("font_size", 13)
	heat_row.add_child(heat_name)
	_status_heat_bar = ProgressBar.new()
	_status_heat_bar.custom_minimum_size = Vector2(100, 10)
	_status_heat_bar.show_percentage = false
	_status_heat_bar.max_value = 1.0
	heat_row.add_child(_status_heat_bar)
	_status_effect.text = "无炼金效果"
	return panel


func _build_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "FullPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = PANEL_SIZE
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.14, 0.97)
	style.border_color = Color(0.45, 0.55, 0.45)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "随身炼金台"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	box.add_child(HSeparator.new())
	box.add_child(_build_tab_row())
	_bag_page = _build_bag_page()
	box.add_child(_bag_page)
	_compendium_page = _build_compendium_page()
	box.add_child(_compendium_page)
	_preset_page = _build_preset_page()
	box.add_child(_preset_page)
	_experiment_page = _build_experiment_page()
	box.add_child(_experiment_page)
	_forge_page = _build_forge_page()
	box.add_child(_forge_page)
	_apply_tab_visibility()
	return panel


func _build_tab_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_tab_buttons.clear()
	for index: int in range(TAB_NAMES.size()):
		var button := Button.new()
		button.text = TAB_NAMES[index]
		button.custom_minimum_size = Vector2(110, 34)
		button.pressed.connect(_on_tab_pressed.bind(index))
		row.add_child(button)
		_tab_buttons.append(button)
	var hint := Label.new()
	hint.text = "Tab 切换"
	hint.add_theme_font_size_override("font_size", 12)
	row.add_child(hint)
	return row


func _build_bag_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	_slots_row = HBoxContainer.new()
	_slots_row.add_theme_constant_override("separation", 8)
	page.add_child(_slots_row)
	var bag_title := Label.new()
	bag_title.text = "材料背包（左键放入素材槽，右键移出）"
	bag_title.add_theme_font_size_override("font_size", 14)
	page.add_child(bag_title)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 5
	_bag_grid.add_theme_constant_override("h_separation", 6)
	_bag_grid.add_theme_constant_override("v_separation", 6)
	page.add_child(_bag_grid)
	_pool_label = Label.new()
	_pool_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pool_label.custom_minimum_size = Vector2(0, 70)
	page.add_child(_pool_label)
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.add_theme_color_override("font_color", Color("d8e8c8"))
	page.add_child(_preview_label)
	_active_label = Label.new()
	page.add_child(_active_label)
	_heat_label = Label.new()
	page.add_child(_heat_label)
	# 诅咒炼金：手动选一条诅咒，本次炼金换取强度 / 时长，代价是自伤 / 热量 / 额外材料。
	_curse_label = Label.new()
	_curse_label.add_theme_color_override("font_color", Color("d8a0d8"))
	page.add_child(_curse_label)
	_curse_row = HBoxContainer.new()
	_curse_row.add_theme_constant_override("separation", 6)
	page.add_child(_curse_row)
	_build_curse_buttons()
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	page.add_child(action_row)
	var brew_button := Button.new()
	brew_button.text = "炼金"
	brew_button.custom_minimum_size = Vector2(120, 40)
	brew_button.pressed.connect(_on_brew_pressed)
	action_row.add_child(brew_button)
	var clear_button := Button.new()
	clear_button.text = "清空素材槽"
	clear_button.custom_minimum_size = Vector2(140, 40)
	clear_button.pressed.connect(_on_clear_slots_pressed)
	action_row.add_child(clear_button)
	var cancel_button := Button.new()
	cancel_button.text = "关闭（Esc）"
	cancel_button.custom_minimum_size = Vector2(140, 40)
	cancel_button.pressed.connect(_on_cancel_pressed)
	action_row.add_child(cancel_button)
	return page


func _build_compendium_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	_compendium_summary_label = Label.new()
	_compendium_summary_label.add_theme_font_size_override("font_size", 16)
	page.add_child(_compendium_summary_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_compendium_list_label = Label.new()
	_compendium_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compendium_list_label.custom_minimum_size = Vector2(PANEL_SIZE.x - 70, 0)
	_compendium_list_label.add_theme_font_size_override("font_size", 13)
	scroll.add_child(_compendium_list_label)
	return page


func _build_preset_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var hint := Label.new()
	hint.text = "预设保存当前素材槽布局；材料足够时可一键复原。"
	hint.add_theme_font_size_override("font_size", 14)
	page.add_child(hint)
	_preset_rows = VBoxContainer.new()
	_preset_rows.add_theme_constant_override("separation", 6)
	page.add_child(_preset_rows)
	return page


## 实验页：未解锁只显示「？？？」，用当前素材槽做实验。
func _build_experiment_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var hint := Label.new()
	hint.text = "用素材槽里的组合做实验：成功解锁图鉴，失败出事故（自伤 + 额外热量）。"
	hint.add_theme_font_size_override("font_size", 14)
	page.add_child(hint)
	_experiment_summary_label = Label.new()
	_experiment_summary_label.add_theme_font_size_override("font_size", 16)
	page.add_child(_experiment_summary_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_experiment_list_label = Label.new()
	_experiment_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_experiment_list_label.custom_minimum_size = Vector2(PANEL_SIZE.x - 70, 0)
	_experiment_list_label.add_theme_font_size_override("font_size", 13)
	scroll.add_child(_experiment_list_label)
	var run_button := Button.new()
	run_button.text = "对当前素材槽做实验"
	run_button.custom_minimum_size = Vector2(220, 40)
	run_button.pressed.connect(_on_experiment_pressed)
	page.add_child(run_button)
	return page


## 切换页签（Tab）；step 可为负。
func cycle_tab(step: int = 1) -> void:
	_tab = posmod(_tab + step, TAB_NAMES.size())
	_apply_tab_visibility()


func _apply_tab_visibility() -> void:
	if _bag_page != null:
		_bag_page.visible = _tab == Tab.BAG
	if _compendium_page != null:
		_compendium_page.visible = _tab == Tab.COMPENDIUM
	if _preset_page != null:
		_preset_page.visible = _tab == Tab.PRESET
	if _experiment_page != null:
		_experiment_page.visible = _tab == Tab.EXPERIMENT
	if _forge_page != null:
		_forge_page.visible = _tab == Tab.FORGE
	for index: int in range(_tab_buttons.size()):
		_tab_buttons[index].disabled = index == _tab


func _build_wheel() -> PanelContainer:
	var wheel := PanelContainer.new()
	wheel.name = "CombatWheel"
	wheel.mouse_filter = Control.MOUSE_FILTER_STOP
	wheel.set_anchors_preset(Control.PRESET_CENTER)
	wheel.custom_minimum_size = WHEEL_SIZE
	wheel.offset_left = -WHEEL_SIZE.x * 0.5
	wheel.offset_top = -WHEEL_SIZE.y * 0.5
	wheel.offset_right = WHEEL_SIZE.x * 0.5
	wheel.offset_bottom = WHEEL_SIZE.y * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.10, 0.13, 0.94)
	style.border_color = Color(0.70, 0.45, 0.22)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	wheel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	wheel.add_child(box)
	var title := Label.new()
	title.text = "战斗炼金"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_wheel_slots_row = HBoxContainer.new()
	_wheel_slots_row.add_theme_constant_override("separation", 8)
	box.add_child(_wheel_slots_row)
	_wheel_pool_label = Label.new()
	_wheel_pool_label.custom_minimum_size = Vector2(0, 90)
	_wheel_pool_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_wheel_pool_label)
	# 预览：相同组合 → 时间叠加；不同组合 → 替换旧效果（50% 爆发）。
	_wheel_preview_label = Label.new()
	_wheel_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wheel_preview_label.add_theme_color_override("font_color", Color("d8e8c8"))
	box.add_child(_wheel_preview_label)
	# 当前生效：组合描述 + 剩余时间。
	_wheel_active_label = Label.new()
	_wheel_active_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_wheel_active_label)
	var heat_row := HBoxContainer.new()
	heat_row.add_theme_constant_override("separation", 6)
	box.add_child(heat_row)
	var heat_name := Label.new()
	heat_name.text = "热量"
	heat_row.add_child(heat_name)
	_wheel_heat_bar = ProgressBar.new()
	_wheel_heat_bar.custom_minimum_size = Vector2(180, 14)
	_wheel_heat_bar.show_percentage = false
	_wheel_heat_bar.max_value = 1.0
	heat_row.add_child(_wheel_heat_bar)
	_wheel_hint = Label.new()
	_wheel_hint.text = "松开 E 关闭 · 左键炼金 · 右键移除 · 受击自动打断"
	_wheel_hint.add_theme_color_override("font_color", Color("c8bfa8"))
	box.add_child(_wheel_hint)
	return wheel


## ── 刷新 ────────────────────────────────────────────────────────────────

func _update_status() -> void:
	var combo: BrewCombo = station.active_combo()
	var ratio: float = station.duration_ratio()
	# 武器旁常驻：图标色按主导元素，圆环扫过剩余时长。
	_status_ring.active = AlchemyStatusRing.is_active(combo)
	_status_ring.color = AlchemyStatusRing.effect_color(combo)
	_status_ring.ratio = ratio
	_status_ring.queue_redraw()
	if combo != null:
		_status_effect.text = combo.describe()
		_status_duration_bar.value = ratio
	else:
		_status_effect.text = "无效果"
		_status_duration_bar.value = 0.0
	_status_heat_bar.value = station.heat() / AlchemyRules.HEAT_MAX
	_status_style.bg_color = Color(_warning_color(station.warning_level()).lerp(Color(0.08, 0.09, 0.11, 0.88), 0.55))


func _update_panel() -> void:
	if _slot_buttons.is_empty() and station.slots != null and station.slots.slot_count() > 0:
		_rebuild_slot_buttons()
	_update_slot_text(_slot_buttons)
	_pool_label.text = _pool_text()
	_preview_label.text = _preview_text()
	var combo: BrewCombo = station.active_combo()
	_active_label.text = "当前：%s　剩余 %.1f 秒" % [_combo_description(combo), station.duration_remaining()]
	_heat_label.text = "热量 %.0f / %.0f　警告等级 %d" % [station.heat(), AlchemyRules.HEAT_MAX, station.warning_level()]
	_update_compendium()
	_update_presets()
	_update_experiments()
	_update_forge()
	_update_curse_label()


## 图鉴页：完成度 + 五栏条目（未发现显示「？？？」）。
func _update_compendium() -> void:
	if station == null or station.compendium == null or _compendium_list_label == null:
		return
	var book: AlchemyCompendium = station.compendium
	_compendium_summary_label.text = "图鉴完成度 %.1f%%（%d / %d）" % [
		book.completion_ratio() * 100.0, book.discovered_count(), book.total_entries()]
	var lines: PackedStringArray = []
	for section: int in [AlchemyCompendium.Section.ELEMENT, AlchemyCompendium.Section.BEHAVIOR,
			AlchemyCompendium.Section.TRIGGER, AlchemyCompendium.Section.MODIFIER,
			AlchemyCompendium.Section.REACTION, AlchemyCompendium.Section.CONFLICT]:
		lines.append("【%s】" % book.section_name(section))
		for entry: Dictionary in book.entries_of(section):
			lines.append(_compendium_line(section, entry))
	_compendium_list_label.text = "\n".join(lines)


func _compendium_line(section: int, entry: Dictionary) -> String:
	if not bool(entry.get("discovered", false)):
		return "　" + AlchemyCompendium.UNKNOWN_TEXT
	if section == AlchemyCompendium.Section.REACTION:
		return "　%s（%s + %s）" % [
			String(entry.get("name", "")),
			AlchemyCompendium.identifier_name(entry.get("a", &"")),
			AlchemyCompendium.identifier_name(entry.get("b", &"")),
		]
	var line: String = "　%s %s" % [String(entry.get("name", "")), _roman(int(entry.get("level", 1)))]
	var effect: String = String(entry.get("effect", ""))
	if not effect.is_empty():
		line += "　" + effect
	return line


## 预设页：每格显示材料名与可用性。
func _update_presets() -> void:
	if station == null or station.presets == null or _preset_rows == null:
		return
	if _preset_status_labels.size() != station.presets.preset_count():
		_rebuild_preset_rows()
	for index: int in range(_preset_status_labels.size()):
		_preset_status_labels[index].text = _preset_status_text(index)


## 实验页：解锁进度 + 全部实验条目（未解锁显示「？？？」）。
func _update_experiments() -> void:
	if station == null or station.experiments == null or _experiment_list_label == null:
		return
	var lab: AlchemyExperiments = station.experiments
	_experiment_summary_label.text = "实验解锁 %d / %d（%.0f%%）" % [
		lab.unlocked_count(), AlchemyExperiments.EXPERIMENTS.size(), lab.completion_ratio() * 100.0]
	var lines: PackedStringArray = []
	for entry: Dictionary in AlchemyExperiments.EXPERIMENTS:
		var experiment_id: StringName = entry["id"]
		var mark: String = "✔" if lab.is_unlocked(experiment_id) else ""
		lines.append("　%s　（%s）%s" % [lab.display_name(experiment_id), lab.hint_of(experiment_id), mark])
	_experiment_list_label.text = "\n".join(lines)


func _on_experiment_pressed() -> void:
	if station == null:
		return
	var result: Dictionary = station.run_experiment()
	var status: String = String(result.get("status", ""))
	if status == "unlocked":
		_show_toast("实验成功：解锁「%s」" % String(result.get("name", "")))
	elif status == "accident":
		_show_toast("实验事故！「%s」反噬" % String(result.get("name", "")))
	elif status == "known":
		_show_toast("已经掌握「%s」" % String(result.get("name", "")))


## 合金页：左键选合金原料（最多两种），右键选重铸材料。
func _build_forge_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var hint := Label.new()
	hint.text = "非战斗合金 / 重铸：左键选两种同品质材料合金，右键选一件材料重铸。"
	hint.add_theme_font_size_override("font_size", 14)
	page.add_child(hint)
	_forge_summary_label = Label.new()
	_forge_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forge_summary_label.add_theme_font_size_override("font_size", 16)
	page.add_child(_forge_summary_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_forge_material_grid = GridContainer.new()
	_forge_material_grid.columns = 4
	_forge_material_grid.add_theme_constant_override("h_separation", 6)
	_forge_material_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_forge_material_grid)
	_forge_list_label = Label.new()
	_forge_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forge_list_label.custom_minimum_size = Vector2(PANEL_SIZE.x - 70, 0)
	_forge_list_label.add_theme_font_size_override("font_size", 13)
	page.add_child(_forge_list_label)
	_forge_slot_label = Label.new()
	_forge_slot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forge_slot_label.add_theme_font_size_override("font_size", 13)
	page.add_child(_forge_slot_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var alloy_button := Button.new()
	alloy_button.text = "合金"
	alloy_button.custom_minimum_size = Vector2(140, 40)
	alloy_button.pressed.connect(_on_alloy_pressed)
	row.add_child(alloy_button)
	var reforge_button := Button.new()
	reforge_button.text = "重铸"
	reforge_button.custom_minimum_size = Vector2(140, 40)
	reforge_button.pressed.connect(_on_reforge_pressed)
	row.add_child(reforge_button)
	var clear_button := Button.new()
	clear_button.text = "清空选择"
	clear_button.custom_minimum_size = Vector2(120, 40)
	clear_button.pressed.connect(_on_forge_clear_pressed)
	row.add_child(clear_button)
	var slot_button := Button.new()
	slot_button.text = "熔成永久槽"
	slot_button.tooltip_text = "把当前素材槽的组合熔成武器永久炼金槽（仅非战斗）"
	slot_button.custom_minimum_size = Vector2(160, 40)
	slot_button.pressed.connect(_on_permanent_slot_pressed)
	row.add_child(slot_button)
	page.add_child(row)
	return page


## 诅咒按钮：点一条即选中，再点同一条取消。
func _build_curse_buttons() -> void:
	if _curse_row == null:
		return
	var none_button := Button.new()
	none_button.text = "不诅咒"
	none_button.custom_minimum_size = Vector2(88, 30)
	none_button.pressed.connect(_on_curse_pressed.bind(&""))
	_curse_row.add_child(none_button)
	for curse_id: StringName in AlchemyCurses.all_curse_ids():
		var button := Button.new()
		button.text = AlchemyCurses.display_name_of(curse_id)
		button.tooltip_text = String(AlchemyCurses.curse_of(curse_id).get("desc", ""))
		button.custom_minimum_size = Vector2(88, 30)
		button.pressed.connect(_on_curse_pressed.bind(curse_id))
		_curse_row.add_child(button)


func _on_curse_pressed(curse_id: StringName) -> void:
	if station == null:
		return
	station.select_curse(curse_id)


## 诅咒行状态：显示当前选择与它的收益 / 代价。
func _update_curse_label() -> void:
	if station == null or station.curses == null or _curse_label == null:
		return
	var active: Array[StringName] = station.active_curses()
	if active.is_empty():
		_curse_label.text = "诅咒：无（选一条可换取强度，但会付出代价）"
		return
	var parts: PackedStringArray = []
	for curse_id: StringName in active:
		parts.append("%s（%s）" % [AlchemyCurses.display_name_of(curse_id),
			String(AlchemyCurses.curse_of(curse_id).get("desc", ""))])
	_curse_label.text = "诅咒：" + "、".join(parts)


## 合金页：候选材料 + 当前选择 + 可合金 / 可重铸的产物预览。
func _update_forge() -> void:
	if station == null or station.forge == null or _forge_summary_label == null:
		return
	_rebuild_forge_buttons()
	var selected: Array[int] = station.forge.alloy_selection
	var names: PackedStringArray = []
	for material_id: int in selected:
		names.append(MaterialCatalog.display_name_of(material_id))
	if names.is_empty():
		_forge_summary_label.text = "合金：未选择材料（左键选两种同品质材料）"
	else:
		_forge_summary_label.text = "合金：%s" % " + ".join(names)
	var lines: PackedStringArray = []
	if selected.size() == 2:
		if AlchemyForge.can_alloy(selected[0], selected[1]):
			var candidates: Array[int] = AlchemyForge.alloy_candidates(selected[0], selected[1])
			var labels: PackedStringArray = []
			for material_id: int in candidates:
				labels.append(MaterialCatalog.display_name_of(material_id))
			lines.append("可合金 → %s" % "、".join(labels))
		else:
			lines.append("这两种材料无法合金（需要同品质且未到 Boss 档）")
	var reforge_id: int = station.forge.reforge_selection
	if reforge_id >= 0:
		var reforge_labels: PackedStringArray = []
		for material_id: int in AlchemyForge.reforge_candidates(reforge_id):
			reforge_labels.append(MaterialCatalog.display_name_of(material_id))
		lines.append("重铸「%s」→ %s" % [MaterialCatalog.display_name_of(reforge_id), "、".join(reforge_labels)])
	else:
		lines.append("重铸：未选择材料（右键选一件材料）")
	_forge_list_label.text = "\n".join(lines)
	if _forge_slot_label != null:
		_forge_slot_label.text = _weapon_slot_text()


## 武器炼金槽状态：临时槽数量 + 永久槽内容。
func _weapon_slot_text() -> String:
	var slots: AlchemyWeaponSlots = station.weapon_slots
	if slots == null:
		return ""
	var parts: PackedStringArray = []
	parts.append("临时槽 %d/%d" % [slots.temporary_count(), slots.temporary_limit])
	if slots.permanent_count() > 0:
		var names: PackedStringArray = []
		for combo: BrewCombo in slots.permanent:
			names.append(combo.describe())
		parts.append("永久槽：%s" % "、".join(names))
	else:
		parts.append("永久槽：空（用当前素材槽熔一个）")
	return "武器炼金槽：" + "　".join(parts)


func _on_permanent_slot_pressed() -> void:
	if station == null:
		return
	var combo: BrewCombo = station.alloy_permanent_slot()
	if combo != null:
		_show_toast("永久槽 +1：%s" % combo.describe())


## 合金页的材料按钮：左键选合金，右键选重铸。
func _rebuild_forge_buttons() -> void:
	if station == null or station.bag == null or _forge_material_grid == null:
		return
	for child: Node in _forge_material_grid.get_children():
		child.queue_free()
	for material_id: int in station.bag.material_ids():
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 34)
		var marks: PackedStringArray = []
		if station.forge.alloy_selection.has(material_id):
			marks.append("合金")
		if station.forge.reforge_selection == material_id:
			marks.append("重铸")
		var suffix: String = "" if marks.is_empty() else "　[%s]" % "/".join(marks)
		button.text = "%s ×%d%s" % [MaterialCatalog.display_name_of(material_id), station.bag.count(material_id), suffix]
		button.pressed.connect(_on_forge_material_pressed.bind(material_id))
		button.gui_input.connect(_on_forge_material_gui_input.bind(material_id))
		_forge_material_grid.add_child(button)


func _on_forge_material_pressed(material_id: int) -> void:
	if station == null:
		return
	station.toggle_alloy_material(material_id)


func _on_forge_material_gui_input(event: InputEvent, material_id: int) -> void:
	if station == null:
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_RIGHT:
		return
	station.set_reforge_material(material_id)
	accept_event()


func _on_alloy_pressed() -> void:
	if station == null:
		return
	var product: int = station.alloy_now()
	if product > 0:
		_show_toast("合金成功：得到「%s」" % MaterialCatalog.display_name_of(product))


func _on_reforge_pressed() -> void:
	if station == null:
		return
	var product: int = station.reforge_now()
	if product > 0:
		_show_toast("重铸成功：得到「%s」" % MaterialCatalog.display_name_of(product))


func _on_forge_clear_pressed() -> void:
	if station == null:
		return
	station.clear_alloy_selection()


func _preset_status_text(index: int) -> String:
	var material_ids: Array[int] = station.presets.preset_at(index)
	if material_ids.is_empty():
		return "（空）"
	var names: PackedStringArray = []
	for material_id: int in material_ids:
		names.append(MaterialCatalog.display_name_of(material_id))
	return "%s　%s" % ["、".join(names), "就绪" if station.preset_ready(index) else "材料不足"]


func _rebuild_preset_rows() -> void:
	for child: Node in _preset_rows.get_children():
		child.queue_free()
	_preset_status_labels.clear()
	for index: int in range(station.presets.preset_count()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_label := Label.new()
		name_label.text = "预设 %d" % (index + 1)
		name_label.custom_minimum_size = Vector2(76, 0)
		row.add_child(name_label)
		var status_label := Label.new()
		status_label.custom_minimum_size = Vector2(240, 0)
		row.add_child(status_label)
		_preset_status_labels.append(status_label)
		row.add_child(_preset_button("应用", _on_preset_apply, index))
		row.add_child(_preset_button("存入", _on_preset_save, index))
		row.add_child(_preset_button("清空", _on_preset_clear, index))
		_preset_rows.add_child(row)


func _preset_button(text: String, handler: Callable, index: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(72, 32)
	button.pressed.connect(func() -> void: handler.call(index))
	return button


func _on_tab_pressed(index: int) -> void:
	_tab = index
	_apply_tab_visibility()


func _on_preset_apply(index: int) -> void:
	if station != null:
		station.apply_preset(index)


func _on_preset_save(index: int) -> void:
	if station != null:
		station.save_preset(index)


func _on_preset_clear(index: int) -> void:
	if station != null:
		station.clear_preset(index)


func _update_wheel() -> void:
	if _wheel_slot_buttons.is_empty() and station.slots != null and station.slots.slot_count() > 0:
		_rebuild_wheel_slots()
	_update_slot_text(_wheel_slot_buttons)
	_wheel_pool_label.text = _pool_text()
	# 预览：相同组合叠加 / 不同组合替换提示；当前生效：组合描述 + 剩余时间。
	_wheel_preview_label.text = _preview_text()
	var active: BrewCombo = station.active_combo()
	_wheel_active_label.text = "当前：%s　剩余 %.1f 秒" % [_combo_description(active), station.duration_remaining()]
	_wheel_heat_bar.value = station.heat() / AlchemyRules.HEAT_MAX


func _update_visibility() -> void:
	var show_panel: bool = station.is_menu_open()
	var show_wheel: bool = station.is_wheel_open()
	_panel.visible = show_panel
	_wheel.visible = show_wheel
	if show_panel or show_wheel:
		add_to_group("alchemy_panel")
	elif is_in_group("alchemy_panel"):
		remove_from_group("alchemy_panel")
	# 非战斗按 E 打开完整炼金台：完全暂停游戏世界；关闭（Esc / 炼金完成）后恢复。
	_set_world_paused(show_panel)
	var target: float = station.slow_motion_scale if show_wheel else 1.0
	if not is_equal_approx(Engine.time_scale, target):
		Engine.time_scale = target


## 完全暂停 / 恢复游戏世界；幂等，暂停不可用时静默降级。
func _set_world_paused(paused: bool) -> void:
	if _world_paused == paused:
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	_world_paused = paused
	tree.paused = paused


func _rebuild_slot_buttons() -> void:
	if station == null or station.slots == null or _slots_row == null:
		return
	for child: Node in _slots_row.get_children():
		child.queue_free()
	_slot_buttons.clear()
	var count: int = station.slots.slot_count()
	for index: int in range(count):
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 44)
		button.pressed.connect(_on_slot_pressed.bind(index))
		button.gui_input.connect(_on_slot_gui_input.bind(index))
		_slots_row.add_child(button)
		_slot_buttons.append(button)
	if _wheel_slots_row != null:
		_rebuild_wheel_slots()


func _rebuild_wheel_slots() -> void:
	if station == null or station.slots == null or _wheel_slots_row == null:
		return
	for child: Node in _wheel_slots_row.get_children():
		child.queue_free()
	_wheel_slot_buttons.clear()
	var count: int = station.slots.slot_count()
	for index: int in range(count):
		var button := Button.new()
		button.custom_minimum_size = Vector2(120, 40)
		button.pressed.connect(_on_slot_pressed.bind(index))
		button.gui_input.connect(_on_slot_gui_input.bind(index))
		_wheel_slots_row.add_child(button)
		_wheel_slot_buttons.append(button)


func _rebuild_bag_buttons() -> void:
	if station == null or station.bag == null or _bag_grid == null:
		return
	for child: Node in _bag_grid.get_children():
		child.queue_free()
	for material_id: int in station.bag.material_ids():
		var button := Button.new()
		button.custom_minimum_size = Vector2(120, 34)
		button.text = "%s ×%d" % [MaterialCatalog.display_name_of(material_id), station.bag.count(material_id)]
		button.pressed.connect(_on_bag_pressed.bind(material_id))
		button.gui_input.connect(_on_bag_gui_input.bind(material_id))
		_bag_grid.add_child(button)


func _update_slot_text(buttons: Array[Button]) -> void:
	if station == null or station.slots == null:
		return
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		var material_id: int = station.slots.material_at(index)
		if material_id == MaterialSlots.EMPTY:
			button.text = "空格"
		else:
			button.text = "%s\n%d 个" % [MaterialCatalog.display_name_of(material_id), station.bag.count(material_id)]


func _pool_text() -> String:
	if station == null:
		return "词条池：空"
	var pool: TraitPoolResult = station.preview()
	if pool.is_empty():
		return "词条池：空"
	var parts: PackedStringArray = []
	for trait_instance: TraitInstance in pool.traits:
		parts.append("%s %s×%d" % [trait_instance.display_name, _roman(trait_instance.level), trait_instance.stacks])
	var line: String = "词条池：\n" + "、".join(parts)
	if not pool.reactions.is_empty():
		var reactions: PackedStringArray = []
		for reaction: Dictionary in pool.reactions:
			reactions.append("%s %s" % [String(reaction.get("name", "")), _roman(int(reaction.get("level", 1)))])
		line += "\n反应：" + "、".join(reactions)
	return line


func _preview_text() -> String:
	if station == null:
		return "预览：空"
	var pool: TraitPoolResult = station.preview()
	if pool.is_empty():
		return "预览：素材槽为空"
	var combo: BrewCombo = BrewPipeline.from_pool(pool)
	var lines: PackedStringArray = []
	lines.append("预览：" + combo.describe())
	var active: BrewCombo = station.active_combo()
	if active != null and active.matches(combo):
		lines.append("相同组合 → 时间叠加")
	else:
		lines.append("新组合 → 替换旧效果（50% 爆发）")
	return "\n".join(lines)


func _combo_description(combo: BrewCombo) -> String:
	return combo.describe() if combo != null else "无效果"


func _warning_color(level: int) -> Color:
	match level:
		1:
			return Color(0.85, 0.72, 0.15)
		2:
			return Color(0.92, 0.52, 0.12)
		3:
			return Color(0.95, 0.22, 0.16)
		4:
			return Color(0.98, 0.08, 0.06)
	return Color(0.30, 0.32, 0.36)


func _roman(level: int) -> String:
	var names: Array[String] = ["I", "II", "III", "IV", "V"]
	return names[clampi(level - 1, 0, names.size() - 1)]


## ── 交互 ────────────────────────────────────────────────────────────────

func _on_brew_pressed() -> void:
	if station != null:
		station.brew_from_slots()


func _on_clear_slots_pressed() -> void:
	if station != null:
		station.clear_slots()


func _on_cancel_pressed() -> void:
	if station != null:
		station.cancel()


func _on_slot_pressed(index: int) -> void:
	if station != null:
		# 点击素材槽：没填时从背包自动放入，已填时清空。
		if station.slots.material_at(index) == MaterialSlots.EMPTY:
			station.fill_first_free_slot()
		else:
			station.clear_slot(index)


func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and (event as InputEventMouseButton).pressed:
		if station != null:
			station.clear_slot(index)


func _on_bag_pressed(material_id: int) -> void:
	if station != null:
		station.fill_first_free_slot(material_id)


func _on_bag_gui_input(event: InputEvent, material_id: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and (event as InputEventMouseButton).pressed:
		if station != null:
			station.bag.remove(material_id, 1)
## 武器旁常驻的倒计时环：画一圈底色 + 一段按剩余时长扫过的弧。
## 只读 AlchemyStatusRing 算好的颜色与比例，不自己算数值。
class StatusRing extends Control:
	var active: bool = false
	var color: Color = AlchemyStatusRing.IDLE_COLOR
	var ratio: float = 0.0

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.5 - 2.0
		if radius <= 0.0:
			return
		# 图标底色：激活时是元素色实心圆，否则是灰色描边圆。
		if active:
			draw_circle(center, radius - 3.0, Color(color.r, color.g, color.b, 0.85))
		draw_arc(center, radius, 0.0, TAU, 24, Color(0.25, 0.27, 0.3, 0.9), 2.0, true)
		if not active or ratio <= 0.0:
			return
		var sweep: float = AlchemyStatusRing.sweep_radians(ratio)
		var alpha: float = AlchemyStatusRing.ring_alpha(ratio)
		draw_arc(center, radius, AlchemyStatusRing.START_ANGLE, AlchemyStatusRing.START_ANGLE + sweep,
			32, Color(color.r, color.g, color.b, alpha), 2.5, true)
