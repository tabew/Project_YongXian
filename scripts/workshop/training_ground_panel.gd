class_name TrainingGroundPanel
extends WorkshopPanel

## 训练场：无限材料试炼金 + 假人测试。

## 由 Workshop 注入，用于把材料直接塞进炼金背包。
var player: PlayerCharacter = null

const GRANT_AMOUNT: int = 99


func _build_content(parent: VBoxContainer) -> void:
	set_titles("训练场", "无限材料试炼金，右侧假人可打")
	_build_rows(parent)


func _build_rows(parent: VBoxContainer) -> void:
	parent.add_child(make_info_row("提示", "补充的材料直接进炼金背包", Color(0.72, 0.76, 0.84)))
	for material_id: int in MaterialCatalog.all_ids():
		var description: String = MaterialCatalog.display_name_of(material_id)
		var owned: int = _owned(material_id)
		parent.add_child(make_row("%s　（背包 %d）" % [description, owned], "补充 %d" % GRANT_AMOUNT, _on_grant.bind(material_id), player != null))


func _owned(material_id: int) -> int:
	if player == null or player.alchemy_station == null:
		return 0
	return player.alchemy_station.bag.count(material_id)


func _on_grant(material_id: int) -> void:
	if player == null:
		return
	player.alchemy_station.absorb_material(material_id, GRANT_AMOUNT)
	play_sfx(&"pickup_material")
	refresh()


func refresh() -> void:
	if _content == null:
		return
	clear_content()
	set_titles("训练场", "无限材料试炼金，右侧假人可打")
	_build_rows(_content)
