class_name MaterialVaultPanel
extends WorkshopPanel

## 材料库：解锁初始携带材料。开局携带格数初始 1，可解锁到 3。

const QUALITY_NAMES: Array[String] = ["普通", "稀有", "史诗", "传说"]


func _build_content(parent: VBoxContainer) -> void:
	set_titles("材料库", "选择出发时携带的材料")
	_build_rows(parent)


func _build_rows(parent: VBoxContainer) -> void:
	for material_id: int in MaterialCatalog.all_ids():
		var definition: Dictionary = MaterialCatalog.definition_of(material_id)
		var quality: int = int(definition.get("quality", 0))
		var carried: bool = manager.carried_material_ids.has(material_id)
		var description: String = "%s　[%s]" % [
			MaterialCatalog.display_name_of(material_id),
			QUALITY_NAMES[clampi(quality, 0, QUALITY_NAMES.size() - 1)],
		]
		var button_text: String = "取消携带" if carried else "携带"
		var row: HBoxContainer = make_row(description, button_text, _on_toggle.bind(material_id), true)
		parent.add_child(row)


func _on_toggle(material_id: int) -> void:
	var ids: PackedInt32Array = manager.carried_material_ids.duplicate()
	if ids.has(material_id):
		var index: int = ids.find(material_id)
		ids.remove_at(index)
		play_sfx(&"ui_back")
	else:
		ids.append(material_id)
		play_sfx(&"ui_click")
	if not manager.set_carried_materials(ids):
		play_sfx(&"brew_reject")
	refresh()


func refresh() -> void:
	if _content == null:
		return
	clear_content()
	var carried: int = manager.carried_material_ids.size()
	set_titles("材料库", "携带格数 %d / %d" % [carried, manager.material_slot_capacity])
	_build_rows(_content)
