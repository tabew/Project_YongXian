extends Control

## 主菜单：开始游戏 -> 生成随机地图；退出。

@onready var btn_start: Button = $VBoxContainer/BtnStart
@onready var btn_quit: Button = $VBoxContainer/BtnQuit
@onready var version_label: Label = $VersionLabel


func _ready() -> void:
	btn_start.pressed.connect(_on_start_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)

	version_label.text = "v" + str(
		ProjectSettings.get_setting("application/config/version", "0.1.0")
	)
	btn_start.grab_focus()

	# 淡入
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4)


func _on_start_pressed() -> void:
	GameState.start_new_world()
	SceneManager.change_scene("res://scenes/game/game_world.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
