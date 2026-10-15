class_name DepartureGatePanel
extends WorkshopPanel

## 出发门：选武器 → 确认携带材料 → 确认难度 → 开始游戏。

signal start_run_requested
## 选中武器：Workshop 收到后立刻把工坊主角也换上，选完当场就能看到生效。
signal weapon_selected(weapon_id: StringName)

## 可选武器定义：由 Workshop 从主角的武器轮换列表 + 武器配置表填充。
## 这里必须传定义本身：武器配置表里只有扩展武器，.tres 真武器查不到，
## 只传 id 再回头查表会退化成空定义（名字变成默认的 "Weapon"、数值也不对）。
var weapon_definitions: Array[WeaponDefinition] = []

## 出发门内容最多（12 把武器 + 三段信息 + 开始按钮），用更高的面板。
const DEPARTURE_PANEL_SIZE: Vector2 = Vector2(680.0, 620.0)
## 武器列表自己的滚动区高度，保证「开始游戏」始终留在面板里。
const WEAPON_LIST_HEIGHT: float = 230.0


func panel_size() -> Vector2:
	return DEPARTURE_PANEL_SIZE


func _build_content(parent: VBoxContainer) -> void:
	_build_rows(parent)


func _build_rows(parent: VBoxContainer) -> void:
	set_titles("出发门", "当前武器：%s　·　选武器 → 携带材料 → 难度 → 开始" % _current_weapon_name())
	parent.add_child(make_heading("① 选择武器"))
	var list := ScrollContainer.new()
	list.name = "WeaponList"
	list.custom_minimum_size = Vector2(0.0, WEAPON_LIST_HEIGHT)
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(list)
	var column := VBoxContainer.new()
	column.name = "Rows"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", ROW_SEPARATION)
	list.add_child(column)
	for definition: WeaponDefinition in weapon_definitions:
		if definition == null or definition.id == &"":
			continue
		var current: bool = manager.selected_weapon_id == definition.id
		column.add_child(make_row(
			"%s　伤害 %s　%.1f 次/秒" % [definition.display_name, str(definition.damage), definition.attacks_per_second()],
			"已选择" if current else "选择", _on_weapon.bind(definition.id), not current))

	parent.add_child(make_heading("② 携带材料"))
	var carried_text: String = "（空）"
	if not manager.carried_material_ids.is_empty():
		var names := PackedStringArray()
		for material_id: int in manager.carried_material_ids:
			names.append(MaterialCatalog.display_name_of(material_id))
		carried_text = "、".join(names)
	parent.add_child(make_info_row("来自材料库（%d/%d）：%s" % [
		manager.carried_material_ids.size(), manager.material_slot_capacity, carried_text,
	], "去材料库调整", Color(0.72, 0.76, 0.84)))

	parent.add_child(make_heading("③ 确认难度"))
	parent.add_child(make_info_row(
		"%s（%.1fx）" % [DifficultyTier.name_of(manager.difficulty_tier), DifficultyTier.multiplier(manager.difficulty_tier)],
		"去难度祭坛调整", Color(0.72, 0.76, 0.84)))

	parent.add_child(make_heading("④ 开始"))
	parent.add_child(make_row("准备好后进入局内：层 → 区域 → 房间。", "开始游戏", _on_start, true))


## 当前选中武器的显示名；查不到就退回 id，方便排查。
func _current_weapon_name() -> String:
	if manager == null:
		return ""
	for definition: WeaponDefinition in weapon_definitions:
		if definition != null and definition.id == manager.selected_weapon_id:
			return definition.display_name
	return String(manager.selected_weapon_id)


func _on_weapon(weapon_id: StringName) -> void:
	manager.set_weapon(weapon_id)
	play_sfx(&"ui_click")
	weapon_selected.emit(weapon_id)
	refresh()


func _on_start() -> void:
	play_sfx(&"ui_click")
	start_run_requested.emit()


func refresh() -> void:
	if _content == null:
		return
	# 刷新会重建整列行，先把滚动位置记下来，否则选完最后一把武器会跳回顶部。
	var keep_scroll: int = 0
	var old_list: ScrollContainer = _content.get_node_or_null("WeaponList") as ScrollContainer
	if old_list != null:
		keep_scroll = old_list.scroll_vertical
	clear_content()
	_build_rows(_content)
	var new_list: ScrollContainer = _content.get_node_or_null("WeaponList") as ScrollContainer
	if new_list != null:
		new_list.set_deferred("scroll_vertical", keep_scroll)
