class_name CheatPanel
extends Control

enum Mode { ITEMS, BUFFS }

const SCOPE_NAMES: Array[String] = ["通用", "武器", "炼金", "机制", "代价"]
const MAX_AMOUNT: int = 999

var mode: Mode = Mode.ITEMS
var _player: PlayerCharacter
var _registry: Node
var _progress: Node
var _was_paused: bool = false
var _cards_edited: bool = false
var _updating: bool = false
var _batch_grant: bool = false
var _selected_item: int = -1
var _selected_card: StringName = &""
var _detail_key: String = ""

var _panel: PanelContainer
var _tabs: TabBar
var _search: LineEdit
var _filter: OptionButton
var _list: Tree
var _details: Label
var _amount_label: Label
var _amount: SpinBox
var _apply: Button
var _bulk: Button
var _remove: Button
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_player = get_tree().get_first_node_in_group("player") as PlayerCharacter
	_registry = get_node_or_null("/root/ItemListGlobal")
	_progress = get_node_or_null("/root/RunProgress")
	_build()
	visible = false
	get_viewport().size_changed.connect(_layout)
	if _player != null and _player.inventory != null:
		_player.inventory.inventory_update.connect(_on_inventory_changed)
	if _progress != null:
		_progress.cards_changed.connect(_on_cards_changed)
	_layout()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("242827")
	style.border_color = Color("789b90")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.add_theme_font_size_override("font_size", 16)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "运行调试"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.icon = get_theme_icon("close", "Window")
	close_button.tooltip_text = "关闭"
	close_button.custom_minimum_size = Vector2(34, 34)
	close_button.pressed.connect(close_panel)
	header.add_child(close_button)
	_tabs = TabBar.new()
	_tabs.add_tab("物资")
	_tabs.add_tab("增益")
	_tabs.tab_changed.connect(_on_tab_changed)
	column.add_child(_tabs)
	var filters := HBoxContainer.new()
	column.add_child(filters)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索名称或编号"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String) -> void: _refresh_rows())
	filters.add_child(_search)
	_filter = OptionButton.new()
	_filter.custom_minimum_size.x = 120
	_filter.item_selected.connect(func(_index: int) -> void: _refresh_rows())
	filters.add_child(_filter)
	_list = Tree.new()
	_list.columns = 3
	_list.hide_root = true
	_list.select_mode = Tree.SELECT_ROW
	_list.column_titles_visible = true
	_list.set_column_expand(0, true)
	_list.set_column_expand(1, false)
	_list.set_column_expand(2, false)
	_list.set_column_custom_minimum_width(1, 120)
	_list.set_column_custom_minimum_width(2, 84)
	_list.add_theme_constant_override("v_separation", 8)
	_list.custom_minimum_size.y = 112
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	column.add_child(_list)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size.y = 76
	_details.add_theme_color_override("font_color", Color("d5ded9"))
	column.add_child(_details)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	column.add_child(actions)
	var amount_box := HBoxContainer.new()
	actions.add_child(amount_box)
	_amount_label = Label.new()
	amount_box.add_child(_amount_label)
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = MAX_AMOUNT
	_amount.step = 1
	_amount.value = 99
	_amount.custom_minimum_size = Vector2(108, 34)
	amount_box.add_child(_amount)
	_apply = _command("获取", _on_apply, actions)
	_remove = _command("移除", _on_remove, actions)
	_bulk = _command("全部材料", _on_bulk, actions)
	_status = Label.new()
	_status.text = " "
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.custom_minimum_size.y = 24
	_status.add_theme_color_override("font_color", Color("a8d9bc"))
	column.add_child(_status)


func _command(caption: String, callback: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(96, 34)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _layout() -> void:
	var available: Vector2 = get_viewport_rect().size
	_panel.size = Vector2(minf(800.0, available.x - 32.0), minf(620.0, available.y - 32.0))
	_panel.position = (available - _panel.size) * 0.5


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("debug_items"):
		toggle(Mode.ITEMS)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_buffs"):
		toggle(Mode.BUFFS)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func _unhandled_input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()


func toggle(requested: Mode) -> void:
	if visible and mode == requested:
		close_panel()
		return
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	if not visible:
		_was_paused = get_tree().paused
		_cards_edited = false
		_player.weapon_controller.cancel_attack()
		visible = true
		get_tree().paused = true
	_set_mode(requested)
	_search.grab_focus()


func close_panel() -> void:
	if not visible:
		return
	hide()
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	get_tree().paused = _was_paused
	if _cards_edited:
		var manager := get_parent().get_node_or_null("UpgradeManager") as UpgradeManager
		if manager != null:
			manager.refresh_pending_choices()
	_cards_edited = false


func _exit_tree() -> void:
	if visible and not _was_paused:
		get_tree().paused = false


func _on_tab_changed(index: int) -> void:
	if not _updating:
		_set_mode(index as Mode)


func _set_mode(requested: Mode) -> void:
	mode = requested
	_updating = true
	_tabs.current_tab = mode
	_search.clear()
	_filter.clear()
	_filter.add_item("全部")
	var categories: Array[String] = []
	categories.assign(["材料", "武器", "药水"] if mode == Mode.ITEMS else SCOPE_NAMES)
	for category: String in categories:
		_filter.add_item(category)
	_filter.select(0)
	_list.set_column_title(0, "物品" if mode == Mode.ITEMS else "增益")
	_list.set_column_title(1, "类别" if mode == Mode.ITEMS else "作用对象")
	_list.set_column_title(2, "背包" if mode == Mode.ITEMS else "层数")
	_amount_label.text = "数量" if mode == Mode.ITEMS else "层数"
	_apply.text = "获取" if mode == Mode.ITEMS else "应用"
	_bulk.text = "全部材料" if mode == Mode.ITEMS else "清空增益"
	_remove.visible = mode == Mode.BUFFS
	_status.text = " "
	_detail_key = ""
	_updating = false
	_refresh_rows()


func _item_category(item: ItemData) -> int:
	if item is WeaponData:
		return 2
	if item is PotionData:
		return 3
	return 1


func _find_item(id: int) -> ItemData:
	if _registry == null:
		return null
	return _registry.runtime_instances.get(id, _registry.table.get(id)) as ItemData


func _weapon_name(id: StringName) -> String:
	if _registry != null:
		for item: ItemData in _registry.table.values():
			if item is WeaponData and (item as WeaponData).weapon != null and (item as WeaponData).weapon.id == id:
				return item.name
	return str(id)


func _matches(text: String) -> bool:
	return _search.text.strip_edges().is_empty() or text.to_lower().contains(_search.text.strip_edges().to_lower())


func _refresh_rows() -> void:
	if _updating or _list == null:
		return
	_updating = true
	_list.clear()
	var tree_root: TreeItem = _list.create_item()
	var selected: TreeItem = null
	if mode == Mode.ITEMS and _registry != null:
		var items: Dictionary = _registry.table.duplicate()
		items.merge(_registry.runtime_instances, true)
		var ids: Array = items.keys()
		ids.sort()
		for id: int in ids:
			var item: ItemData = items[id]
			var category: int = _item_category(item)
			if (_filter.selected > 0 and _filter.selected != category) or not _matches("%s %d" % [item.name, id]):
				continue
			var row: TreeItem = _list.create_item(tree_root)
			row.set_text(0, item.name)
			row.set_icon(0, item.texture)
			row.set_icon_max_width(0, 36)
			row.set_text(1, ["", "材料", "武器", "药水"][category])
			row.set_text(2, str(_player.inventory.get_count(id)))
			row.set_metadata(0, id)
			if id == _selected_item:
				selected = row
	elif mode == Mode.BUFFS and _progress != null:
		for card: UpgradeCard in UpgradePool.catalog().values():
			var target: String = _weapon_name(card.weapon_id) if not card.weapon_id.is_empty() else SCOPE_NAMES[card.scope]
			if (_filter.selected > 0 and _filter.selected - 1 != card.scope) or not _matches("%s %s %s %s" % [card.display_name, card.id, card.description, target]):
				continue
			var row: TreeItem = _list.create_item(tree_root)
			row.set_text(0, card.display_name)
			row.set_custom_color(0, UpgradePanel.RARITY_COLORS[card.rarity])
			row.set_text(1, target)
			row.set_text(2, "%d / %d" % [_progress.stacks_of(card.id), card.max_stacks])
			row.set_metadata(0, card.id)
			if card.id == _selected_card:
				selected = row
	if selected == null:
		selected = tree_root.get_first_child()
	if selected != null:
		selected.select(0)
	_updating = false
	_on_selected()


func _on_selected() -> void:
	if _updating:
		return
	var row: TreeItem = _list.get_selected()
	_apply.disabled = row == null
	_remove.disabled = row == null
	_amount.editable = row != null
	if row == null:
		_details.text = "没有匹配的结果"
		return
	if mode == Mode.ITEMS:
		_selected_item = int(row.get_metadata(0))
		var item: ItemData = _find_item(_selected_item)
		_amount.min_value = 1
		_amount.max_value = mini(MAX_AMOUNT, maxi(item.max_stack, 1))
		var attributes: PackedStringArray = []
		for attribute: AlchemicalData in item.alchemical_attribute:
			if attribute != null:
				attributes.append("%s %d" % [attribute.name, attribute.level])
		_details.text = "%s  ·  #%d\n%s" % [item.name, item.id, "、".join(attributes)]
		if item is WeaponData and (item as WeaponData).weapon != null:
			var weapon: WeaponDefinition = (item as WeaponData).weapon
			_details.text += "伤害 %s  ·  %.2f 次/秒" % [str(weapon.damage), weapon.attacks_per_second()]
	else:
		_selected_card = StringName(row.get_metadata(0))
		var card: UpgradeCard = UpgradePool.get_card(_selected_card)
		_amount.min_value = 0
		_amount.max_value = card.max_stacks
		if _detail_key != str(card.id):
			_amount.value = maxi(_progress.stacks_of(card.id), 1)
		var target: String = _weapon_name(card.weapon_id) if not card.weapon_id.is_empty() else SCOPE_NAMES[card.scope]
		_details.text = "%s  ·  %s  ·  %s\n%s" % [card.display_name, UpgradeCard.rarity_name(card.rarity), target, card.description]
		_detail_key = str(card.id)
		_remove.disabled = _progress.stacks_of(card.id) == 0


func grant_item(id: int, requested: int) -> int:
	var item: ItemData = _find_item(id)
	if item == null or requested <= 0 or not is_instance_valid(_player) or _player.inventory == null:
		return 0
	var count: int = mini(requested, mini(MAX_AMOUNT, maxi(item.max_stack, 1)))
	if item is PotionData:
		# Bottles own their attributes and registration, just like alchemy output.
		var potion: PotionData = item.duplicate(true) as PotionData
		potion.alchemical_attribute = []
		for attribute: AlchemicalData in item.alchemical_attribute:
			if attribute != null:
				var copied: AlchemicalData = attribute.duplicate(true) as AlchemicalData
				copied.level = attribute.level
				potion.alchemical_attribute.append(copied)
		potion.id = PotionData.next_potion_id()
		while _registry.runtime_instances.has(potion.id) or _player.inventory.get_item_data.has(potion.id):
			potion.id = PotionData.next_potion_id()
		if not _registry.register_instance(potion):
			return 0
		_player.inventory.add_item(potion.id, 1)
		return 1
	_player.inventory.add_item(id, count)
	return count


func _on_apply() -> void:
	if _list.get_selected() == null:
		return
	_amount.apply()
	if mode == Mode.ITEMS:
		var item: ItemData = _find_item(_selected_item)
		var count: int = grant_item(_selected_item, int(_amount.value))
		_status.text = "已获取 %s × %d" % [item.name, count] if count > 0 else "未能获取物品"
	else:
		var card: UpgradeCard = UpgradePool.get_card(_selected_card)
		if _progress.debug_set_card_stacks(card.id, int(_amount.value)):
			_status.text = "%s  ·  %d / %d 层" % [card.display_name, _progress.stacks_of(card.id), card.max_stacks]


func _on_remove() -> void:
	if mode == Mode.BUFFS and _list.get_selected() != null:
		_progress.debug_set_card_stacks(_selected_card, 0)
		_amount.value = 0
		_status.text = "已移除 %s" % UpgradePool.get_card(_selected_card).display_name


func _on_bulk() -> void:
	if mode == Mode.BUFFS:
		_progress.debug_clear_cards()
		_amount.value = 0
		_status.text = "已清空本局增益"
		return
	_amount.apply()
	var requested: int = maxi(int(_amount.value), 1)
	var kinds: int = 0
	_batch_grant = true
	for item: ItemData in _registry.table.values():
		if _item_category(item) == 1 and grant_item(item.id, requested) > 0:
			kinds += 1
	_batch_grant = false
	_refresh_rows()
	_status.text = "已获取 %d 种材料，各 %d 份" % [kinds, requested]


func _on_inventory_changed() -> void:
	if visible and mode == Mode.ITEMS and not _batch_grant:
		_refresh_rows()


func _on_cards_changed() -> void:
	if visible:
		_cards_edited = true
		if mode == Mode.BUFFS:
			_refresh_rows()
