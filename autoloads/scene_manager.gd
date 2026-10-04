extends CanvasLayer

## 统一场景切换入口，切换时盖一层黑幕做淡入淡出。
## 注册为自动加载单例：SceneManager.change_scene("res://scenes/...")

const FADE_DURATION: float = 0.25

@onready var fade_rect: ColorRect = $ColorRect

var _is_transitioning: bool = false


func _ready() -> void:
	fade_rect.visible = false
	fade_rect.modulate.a = 0.0


## 淡出 -> 换场景 -> 淡入。
func change_scene(scene_path: String) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	await _fade_to(1.0)
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await _fade_to(0.0)

	_is_transitioning = false


## 不做过渡，立刻切换（调试或跳过开场时用）。
func change_scene_immediate(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


func _fade_to(target_alpha: float) -> void:
	fade_rect.visible = true
	var tween: Tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", target_alpha, FADE_DURATION)
	await tween.finished
	if is_zero_approx(target_alpha):
		fade_rect.visible = false
