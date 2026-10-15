class_name TrainingGroundPanel
extends WorkshopPanel

## 训练场交互点：只做一件事——确认前往独立的空旷试验场。
##
## 工坊里不再直接刷材料 / 摆假人：假人与无限材料都在试验场（training_arena.tscn）里，
## 本面板只负责把「确认前往」的意图广播给 Workshop。

signal travel_requested

const TITLE: String = "训练场"
const SUBTITLE: String = "前往独立试验场：假人 + 无限材料，随便试炼金"


func _build_content(parent: VBoxContainer) -> void:
	set_titles(TITLE, SUBTITLE)
	parent.add_child(make_info_row(
		"试验场里有返回工坊的按钮，以及无限材料补充。",
		"空旷场地", Color(0.72, 0.76, 0.84)))
	parent.add_child(make_row(
		"前往独立试验场：一只打不死的假人 + 无限材料。",
		"确认前往", _on_travel, true))


func _on_travel() -> void:
	play_sfx(&"ui_click")
	travel_requested.emit()


func refresh() -> void:
	if _content == null:
		return
	clear_content()
	_build_content(_content)
