class_name DepartureGatePanel
extends WorkshopPanel

## 出发门：选武器 → 确认携带材料 → 确认难度 → 开始游戏。

signal start_run_requested

## 可选武器：由 Workshop 从主角的武器轮换列表 + 武器配置表填充。
var weapon_ids: Array[StringName] = []


func _build_content(parent: VBoxContainer) -> void:
	set_titles("出发门", "选武器 → 携带材料 → 难度 → 开始")
	_build_rows(parent)


func _build_rows(parent: VBoxContainer) -> void:
	parent.add_child(make_heading("① 选择武器"))
	for weapon_id: StringName in _weapon_ids():
		var definition: WeaponDefinition = WeaponCatalog.definition_of(weapon_id)
		var name: String = definition.display_name if definition != null else String(weapon_id)
		var description: String = "%s　伤害 %s　%.1f 次/秒" % [name, str(definition.damage), definition.attacks_per_second()] if definition != null else name
		var current: bool = manager.selected_weapon_id == weapon_id
		parent.add_child(make_row(description, "已选择" if current else "选择", _on_weapon.bind(weapon_id), not current))

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


func _weapon_ids() -> Array[StringName]:
	return weapon_ids


func _on_weapon(weapon_id: StringName) -> void:
	manager.set_weapon(weapon_id)
	play_sfx(&"ui_click")
	refresh()


func _on_start() -> void:
	play_sfx(&"ui_click")
	start_run_requested.emit()


func refresh() -> void:
	if _content == null:
		return
	clear_content()
	set_titles("出发门", "选武器 → 携带材料 → 难度 → 开始")
	_build_rows(_content)
