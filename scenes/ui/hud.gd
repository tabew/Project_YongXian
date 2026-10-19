extends Control

## 游戏内 HUD：左上角基本信息，右上角小地图 + 性能面板（F3 开关），
## 底部操作提示，顶部临时消息。

const REFRESH_INTERVAL: float = 0.2
## 左下角经验条的尺寸。
const XP_BAR_SIZE: Vector2 = Vector2(240.0, 8.0)

@onready var info_label: Label = $InfoLabel
@onready var minimap: Minimap = $Minimap
@onready var stats_label: Label = $StatsLabel
@onready var hint_label: Label = $HintLabel
@onready var toast_label: Label = $ToastLabel
@onready var weapon_icon: TextureRect = $WeaponIcon
@onready var weapon_label: Label = $WeaponLabel

var _world: ChunkManager = null
var _player: Node2D = null
var _refresh_timer: float = 0.0
var _toast_tween: Tween = null
var _pickup_label: Label = null
var _level_label: Label = null
var _xp_fill: ColorRect = null
var _boss_visible: bool = false
var _boss_mobile_layout: bool = false
var _stats_visible_before_boss: bool = true


func _ready() -> void:
	# ==========================================================================
	# ↓↓↓↓ 改动：操作提示跟着新的物品栏选中/使用方式走 ↓↓↓↓
	#操作提示分两行放在物品栏上方：物品栏常驻显示，提示压在它下面就会被挡住
	hint_label.text = "WASD 移动　·　E 拾取/开箱/用炼金台　·　左键 使用选中物品　·　右键 使用/投掷选中物品\n1-9 / 滚轮 / 点格子 换选中　·　Tab 背包　·　M 地图　·　R 重开世界"
	# ↑↑↑↑ 改动：操作提示结束 ↑↑↑↑
	# ==========================================================================
	_pickup_label = Label.new()
	_pickup_label.name = "PickupHint"
	_pickup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_label.add_theme_color_override("font_color", Color("f3dbab"))
	_pickup_label.add_theme_color_override("font_shadow_color", Color("29251c"))
	_pickup_label.add_theme_constant_override("shadow_offset_x", 2)
	_pickup_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_pickup_label)
	_pickup_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_pickup_label.offset_left = -200
	_pickup_label.offset_right = 200
	_pickup_label.offset_top = -196
	_pickup_label.offset_bottom = -166
	_pickup_label.visible = false
	_build_progress_readout()
	toast_label.modulate.a = 0.0
	EventBus.notification.connect(_on_notification)
	EventBus.world_ready.connect(_on_world_ready)
	var progress: Node = get_node_or_null("/root/RunProgress")
	if progress != null and progress.has_signal("experience_changed"):
		progress.experience_changed.connect(_on_experience_changed)
	_refresh_progress()
	resized.connect(_layout_for_boss)
	_layout_for_boss()


func set_boss_visible(value: bool) -> void:
	if _boss_visible == value:
		return
	_boss_visible = value
	_layout_for_boss()


func _layout_for_boss() -> void:
	if not is_node_ready():
		return
	var mobile: bool = _boss_visible and size.x < 720.0
	var compact: bool = _boss_visible and size.x < 1140.0 and not mobile
	if mobile and not _boss_mobile_layout:
		_stats_visible_before_boss = stats_label.visible
		stats_label.visible = false
	elif not mobile and _boss_mobile_layout:
		stats_label.visible = _stats_visible_before_boss
	_boss_mobile_layout = mobile
	info_label.position.y = 272.0 if mobile else (114.0 if compact else 10.0)
	minimap.size = Vector2(120.0, 120.0) if mobile else Vector2(164.0, 164.0)
	minimap.position = Vector2(roundf((size.x - 120.0) * 0.5), 112.0) if mobile else Vector2(size.x - 178.0, 114.0 if compact else 14.0)
	stats_label.position.y = 286.0 if compact else 186.0
	($BuffBar as Control).position.y = 400.0 if mobile else (240.0 if compact else 140.0)
	if mobile:
		toast_label.position = Vector2(14.0, 240.0)
		toast_label.size.x = maxf(0.0, size.x - 28.0)
	elif compact:
		toast_label.position = Vector2(372.0, 114.0)
		toast_label.size.x = maxf(0.0, size.x - 562.0)
	else:
		toast_label.position = Vector2((size.x - 480.0) * 0.5, 114.0 if _boss_visible else 24.0)
		toast_label.size.x = 480.0


## 左下角等级与经验条：贴在武器信息上方，不抢左上角信息面板的位置。
func _build_progress_readout() -> void:
	_level_label = Label.new()
	_level_label.name = "LevelLabel"
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_label.add_theme_color_override("font_color", Color("f3dbab"))
	_level_label.add_theme_color_override("font_shadow_color", Color("29251c"))
	_level_label.add_theme_constant_override("shadow_offset_x", 1)
	_level_label.add_theme_constant_override("shadow_offset_y", 1)
	_level_label.add_theme_font_size_override("font_size", 14)
	add_child(_level_label)
	_level_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_level_label.offset_left = 14.0
	_level_label.offset_right = 314.0
	_level_label.offset_top = -124.0
	_level_label.offset_bottom = -102.0

	var background := ColorRect.new()
	background.name = "XpBarBackground"
	background.color = Color(0.05, 0.06, 0.08, 0.72)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	background.offset_left = 14.0
	background.offset_right = 14.0 + XP_BAR_SIZE.x
	background.offset_top = -102.0
	background.offset_bottom = -102.0 + XP_BAR_SIZE.y

	_xp_fill = ColorRect.new()
	_xp_fill.name = "XpBarFill"
	_xp_fill.color = Color(0.62, 0.92, 0.86, 0.95)
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(_xp_fill)
	_xp_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_xp_fill.offset_right = 0.0


## 等级与经验条；由 experience_changed 或周期性刷新调用。
func _refresh_progress() -> void:
	if _level_label == null or _xp_fill == null:
		return
	var progress: Node = get_node_or_null("/root/RunProgress")
	if progress == null:
		_level_label.text = ""
		return
	_level_label.text = "等级 %d　经验 %d/%d" % [
		int(progress.level),
		int(floorf(progress.experience)),
		int(progress.experience_required()),
	]
	_xp_fill.offset_right = XP_BAR_SIZE.x * clampf(progress.experience_ratio(), 0.0, 1.0)


func _on_experience_changed(_current: float, _required: float, _level: int) -> void:
	_refresh_progress()


## 由 GameWorld 注入区块管理器与主角。
func bind_world(manager: ChunkManager, player: Node2D) -> void:
	if _player is PlayerCharacter:
		var previous_controller: WeaponController = (_player as PlayerCharacter).weapon_controller
		if previous_controller.weapon_changed.is_connected(_on_weapon_changed):
			previous_controller.weapon_changed.disconnect(_on_weapon_changed)
	_world = manager
	_player = player
	if player is PlayerCharacter:
		var controller: WeaponController = (player as PlayerCharacter).weapon_controller
		controller.weapon_changed.connect(_on_weapon_changed)
		_on_weapon_changed(controller.equipped_weapon)
	minimap.bind(manager, player)
	_refresh_timer = 0.0


func show_pickup(pickup: GroundPickup) -> void:
	if _pickup_label == null:
		return
	_pickup_label.visible = pickup != null
	if pickup != null:
		_pickup_label.text = "E · 拾取 %s ×%d" % [pickup.data.name, pickup.amount]


func _on_weapon_changed(weapon: WeaponDefinition) -> void:
	weapon_icon.texture = weapon.icon if weapon != null else null
	weapon_label.text = "%s\n%s 伤害  ·  %.1f 次/秒" % [weapon.display_name, str(weapon.damage), weapon.attacks_per_second()] if weapon != null else ""


func show_chest(chest: WorldChest) -> void:
	if _pickup_label == null:
		return
	_pickup_label.visible = chest != null and not chest.opened
	if _pickup_label.visible:
		_pickup_label.text = "E · 打开%s" % chest.display_name()


## 站在野外炼金台旁边的提示。
func show_alchemy_station(station: WorldStructure) -> void:
	if _pickup_label == null:
		return
	_pickup_label.visible = station != null
	if _pickup_label.visible:
		_pickup_label.text = "E · 使用炼金台"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.echo:
			return
	if event.is_action_pressed("toggle_minimap"):
		minimap.set_expanded(not minimap.is_expanded())
		AudioManager.play_sfx(&"ui_toggle")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_debug"):
		if _boss_mobile_layout:
			_stats_visible_before_boss = not _stats_visible_before_boss
		else:
			stats_label.visible = not stats_label.visible
		AudioManager.play_sfx(&"ui_toggle")


func _process(delta: float) -> void:
	if _world == null or _player == null:
		return

	# 文本刷新很便宜但没必要每帧做，0.2 秒一次足够
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = REFRESH_INTERVAL
	_refresh()
	_refresh_progress()


func _refresh() -> void:
	var position: Vector2 = _player.global_position
	var tile: Vector2i = WorldGenerator.world_to_tile(position)
	var chunk: Vector2i = WorldGenerator.tile_to_chunk(tile)
	var spec: MapSpec = _world.get_map_spec()

	var lines := PackedStringArray()
	lines.append("种子 %d" % GameState.world_seed)
	if spec != null:
		var room_kind: int = _world.get_generator().run.type_of(spec.node_id)
		lines.append("%s · %s　区域 %d × %d" % [_world.describe_map(), RoomType.name_of(room_kind), spec.extent.x, spec.extent.y])
		lines.append(spec.shape_name())
	if _player is PlayerCharacter:
		var character := _player as PlayerCharacter
		lines.append("生命 %s/%s" % [str(character.health), str(character.max_health)])
	lines.append("坐标 %d, %d　区块 %d, %d" % [tile.x, tile.y, chunk.x, chunk.y])
	var terrain_name: String = Terrain.name_of(_world.get_terrain_at(position))
	if spec != null and spec.cottage != null:
		var cottage_label: String = spec.cottage.label_at(tile - spec.origin)
		if not cottage_label.is_empty():
			terrain_name = cottage_label
	lines.append("地形 %s　群系 %s" % [
		terrain_name,
		Biome.name_of(_world.get_biome_at(position)),
	])

	var route: int = _world.get_route_at(position)
	if route != Route.Kind.NONE:
		lines.append("★ 走在%s上" % Route.name_of(route))

	info_label.text = "\n".join(lines)

	var stats: Dictionary = _world.get_stats()
	var stats_lines := PackedStringArray()
	stats_lines.append("已加载 %d　缓存 %d" % [stats["loaded"], stats["cached"]])
	stats_lines.append("队列 %d　生成中 %d" % [stats["queued"], stats["in_flight"]])
	stats_lines.append("生成 %.2f ms/块" % stats["generate_avg_ms"])
	stats_lines.append("铺图 %.2f ms/块" % stats["apply_avg_ms"])
	stats_lines.append("共生成 %d　缓存命中 %d" % [stats["generated"], stats["cache_hits"]])
	var spawner := _world.get_parent().get_node_or_null("MonsterSpawner") as MonsterSpawner
	if spawner != null:
		stats_lines.append("本区域怪物 %d　待生成 %d" % [spawner.get_spawned_monster_count(), spawner.get_pending_spawn_count()])
	stats_lines.append("FPS %d" % Engine.get_frames_per_second())
	stats_label.text = "\n".join(stats_lines)


func _on_world_ready(_seed_value: int) -> void:
	_refresh_timer = 0.0


func _on_notification(message: String) -> void:
	toast_label.text = message
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()

	toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.5)
