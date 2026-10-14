class_name UpgradePanel
extends WorkshopPanel

## 炼金台：用灵感买永久升级。

signal purchased(id: StringName)

const QUALITY_NAMES: Array[String] = ["普通", "稀有", "史诗", "传说"]


func _build_content(parent: VBoxContainer) -> void:
	set_titles("炼金台", "用灵感购买永久升级（永久池只增不减）")
	_build_rows(parent)


func _build_rows(parent: VBoxContainer) -> void:
	for upgrade: PermanentUpgrade in PermanentUpgradeCatalog.all():
		var level: int = manager.state.level_of(upgrade.id)
		var cost: int = manager.state.cost_of(upgrade.id)
		var description: String = "%s　[%d/%d]　%s" % [upgrade.name, level, upgrade.max_level, upgrade.description]
		if not manager.state.prerequisite_met(upgrade.id):
			description += "　（需要先点：%s）" % _name_of(upgrade.prerequisite_id)
		var button_text: String = "已满级" if cost < 0 else "购买 %d 灵感" % cost
		var row: HBoxContainer = make_row(description, button_text, _on_purchase.bind(upgrade.id), manager.state.can_purchase(upgrade.id))
		parent.add_child(row)


func _name_of(id: StringName) -> String:
	var upgrade: PermanentUpgrade = PermanentUpgradeCatalog.find(id)
	return upgrade.name if upgrade != null else String(id)


func _on_purchase(id: StringName) -> void:
	if manager.purchase_upgrade(id):
		play_sfx(&"brew_activate")
		purchased.emit(id)
	else:
		play_sfx(&"brew_reject")
	refresh()


func refresh() -> void:
	if _content == null:
		return
	clear_content()
	set_titles("炼金台", "永久灵感池：%d" % manager.state.inspiration)
	_build_rows(_content)
