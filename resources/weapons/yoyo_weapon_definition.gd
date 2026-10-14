class_name YoyoWeaponDefinition
extends WeaponDefinition

## 溜溜球：球停在指针所在的位置，指针超出绳长时贴在绳长边界上；按住左键维持，
## 松手立刻收回。整段飞行都做判定，同一个目标每隔 hit_interval 秒可以再次受伤，
## 而不是一次攻击只吃一次。
##
## 时间轴沿用通用三阶段：前摇把球收在手里，有效期为全部滞空时间，后摇是收回。
## 因此 attack_duration() 仍然覆盖完整飞行，攻击实例在球回到手上时提前结束。

@export_group("Yoyo geometry (pixels)")
## 球心到角色中心的最大距离，也就是绳长上限。
@export_range(8.0, 512.0, 1.0) var max_range: float = 84.0
## 球的判定半径，同时用来缩放贴图。
@export_range(1.0, 32.0, 0.5) var head_radius: float = 6.0
## 绳子从角色中心外多远处画出，也是球收回后的停靠距离。
@export_range(0.0, 32.0, 0.5) var hand_distance: float = 8.0
## 球追向指针的速度（像素/秒）。够高时手感接近“球就贴在指针上”。
@export_range(16.0, 4000.0, 10.0) var follow_speed: float = 900.0
## 松手后收回的速度（像素/秒）。
@export_range(16.0, 4000.0, 10.0) var return_speed: float = 900.0

@export_group("Repeat hits")
## 同一个目标两次受伤之间的最短间隔（秒），对应泰拉瑞亚的受击无敌帧。
@export_range(0.05, 3.0, 0.01) var hit_interval: float = 0.33

@export_group("Appearance")
## 贴图朝右（+X），整张贴图宽度会缩放到球的直径。
@export var texture: Texture2D
## 球的自旋速度（度/秒），纯外观。
@export_range(0.0, 2880.0, 30.0) var spin_degrees_per_second: float = 900.0
@export var string_color: Color = Color(0.86, 0.88, 0.94, 0.8)
@export_range(0.5, 4.0, 0.5) var string_width: float = 1.0
@export var trail_color: Color = Color(0.86, 0.94, 1.0, 0.4)


## 把指针位置换算成球的目标偏移：范围内就落在指针上，超出绳长则贴在边界。
func target_offset(aim: Vector2) -> Vector2:
	if aim.is_zero_approx():
		return Vector2.RIGHT * hand_distance
	var length: float = clampf(aim.length(), hand_distance, max_range)
	return aim.normalized() * length


## 球从绳长上限回到握点所需的时间。
func return_seconds() -> float:
	return maxf(0.0, max_range - hand_distance) / maxf(return_speed, 1.0)


## 溜溜球的出手节奏由玩家松手时机决定，这里给出“甩到边界后立刻收回”的最短循环速率供 HUD 使用。
func attacks_per_second() -> float:
	return 1.0 / maxf(windup_seconds + return_seconds() + reuse_delay, 0.01)


func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = super.validation_errors()
	if max_range <= hand_distance:
		errors.append("Yoyo range must be longer than the hand distance.")
	if head_radius <= 0.0 or follow_speed <= 0.0 or return_speed <= 0.0:
		errors.append("Yoyo radius and flight speeds must be positive.")
	if hit_interval <= 0.0:
		errors.append("Repeat hit interval must be positive.")
	if recovery_seconds < return_seconds():
		errors.append("Recovery must cover the return trip.")
	if texture == null:
		errors.append("A yoyo texture is required.")
	return errors
