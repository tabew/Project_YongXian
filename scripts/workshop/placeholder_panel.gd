class_name PlaceholderPanel
extends WorkshopPanel

## 只留接口、本期不实现具体内容的交互点（图鉴台 / 遗物架 / 成就墙 / 商店）。

var point_name: String = ""
var planned: String = ""


func _build_content(parent: VBoxContainer) -> void:
	set_titles(point_name, "接口预留")
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.text = "该交互点本期只保留接口，不实现具体内容。\n\n计划内容：%s" % planned
	parent.add_child(label)


func refresh() -> void:
	set_titles(point_name, "接口预留")
