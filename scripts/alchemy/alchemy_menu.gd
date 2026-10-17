extends Node2D

## 炼金台界面：只在玩家站到野外炼金台旁按 E 时打开 / 关闭。
## B 键的老入口已移除（原 alchemy_menu 动作一并删除），Esc 或 Tab 也能关掉。

func is_open() -> bool:
	return visible


func open_station() -> void:
	visible = true


func close_station() -> void:
	visible = false


func toggle_station() -> void:
	visible = not visible


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action("ui_cancel") or event.is_action("open_inventory"):
			visible = false
