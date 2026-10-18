class_name DodgeAfterimage
extends Sprite2D

## 闪避残影：复制角色当前帧的一张半透明影子，很快淡出后自删。
## 由 PlayerCharacter 在闪避位移期间生成，参数（帧、翻转、缩放）从角色身上抄。

##淡出时长(秒)
var fade_seconds: float = 0.25


##开始淡出，结束自动删除
func fade(seconds: float = 0.25) -> void:
	fade_seconds = maxf(seconds, 0.02)

	var tween: Tween = create_tween()

	if tween == null:
		queue_free()
		return
	tween.tween_property(self, "modulate:a", 0.0, fade_seconds)
	tween.tween_callback(queue_free)
