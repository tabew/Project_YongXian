extends SceneTree

## 工坊视觉验收：真实渲染一帧并存图，用来肉眼确认布局、交互点与 UI 是否正常。
##
## godot --path . --script res://tools/capture_workshop.gd
## 产物：.godot/workshop-preview.png（以及打开面板后的 .godot/workshop-panel-preview.png）
##
## 不静态引用 Workshop：等 autoload 注册完成后再加载运行场景，避免测试编译期提前引用单例。

const OUTPUT: String = "res://.godot/workshop-preview.png"
const PANEL_OUTPUT: String = "res://.godot/workshop-panel-preview.png"
## 等场景稳定所需的帧数。
const WARMUP_FRAMES: int = 90

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/workshop/workshop.tscn")
	_check(scene != null, "工坊场景可加载")
	if scene == null:
		quit(1)
		return
	var workshop: Node = scene.instantiate()
	root.add_child(workshop)

	for index: int in WARMUP_FRAMES:
		await process_frame

	_check(workshop.get("_interactables").size() == WorkshopLayout.POINTS.size(), "交互点已建好")
	_check(workshop.get("_panels").size() == 5, "5 个已实现面板已注册")
	await _capture(OUTPUT)

	# 打开炼金台面板再截一张，确认面板与暂停逻辑。
	var upgrade: WorkshopPanel = workshop.get("_panels")[&"upgrade"] as WorkshopPanel
	_check(upgrade != null, "炼金台面板存在")
	if upgrade != null:
		upgrade.open()
		get_tree_paused_check()
		for index: int in 20:
			await process_frame
		await _capture(PANEL_OUTPUT)
		upgrade.close()

	print("WORKSHOP CAPTURE: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func get_tree_paused_check() -> void:
	_check(paused, "打开面板时世界暂停")


func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "截图图像为空 " + path)
	if image == null or image.is_empty():
		return
	var error: Error = image.save_png(path)
	_check(error == OK and FileAccess.file_exists(path), "截图保存失败 error=%d %s" % [error, path])
	if error == OK:
		print("  截图 -> ", ProjectSettings.globalize_path(path))
