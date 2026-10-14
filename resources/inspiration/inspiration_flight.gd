class_name InspirationFlight
extends RefCounted

## 灵感光点的飞行数学（纯函数，不依赖场景树，可单元测试）。
## 五个阶段：生成 → 散开 → 悬停 → 飞向玩家 → 飞入。
## 关键特性：悬停结束后**无条件**实时追踪玩家，穿墙，不受物理阻挡。

enum Phase {
	BURST = 0,    ## 生成
	SCATTER = 1,  ## 散开
	HOVER = 2,    ## 悬停
	FLY = 3,      ## 飞向玩家
	ARRIVED = 4,  ## 已到达
}

## 一格等于多少像素：与 Terrain 的格宽保持一致。
const TILE_SIZE: float = 16.0


## 当前阶段。hover_duration 来自 InspirationDrop（不同来源不同）。
static func phase_at(elapsed: float, hover_duration: float) -> int:
	if elapsed < 0.0:
		return Phase.BURST
	if elapsed < InspirationDrop.BURST_END:
		return Phase.BURST
	if elapsed < InspirationDrop.SCATTER_END:
		return Phase.SCATTER
	if elapsed < InspirationDrop.SCATTER_END + hover_duration:
		return Phase.HOVER
	return Phase.FLY


## 悬停结束时刻（进入无条件追踪的时间点）。
static func fly_start_time(hover_duration: float) -> float:
	return InspirationDrop.SCATTER_END + hover_duration


## 散开位移：向随机方向弹射，偏向上方，先快后慢。
## direction 是单位向量（调用方从随机源取），distance_tiles 在 0.5~1.5 格之间。
static func scatter_offset(elapsed: float, direction: Vector2, distance_tiles: float) -> Vector2:
	if elapsed <= InspirationDrop.BURST_END:
		return Vector2.ZERO
	var span: float = InspirationDrop.SCATTER_END - InspirationDrop.BURST_END
	var t: float = clampf((elapsed - InspirationDrop.BURST_END) / span, 0.0, 1.0)
	# 先快后慢：出速最大，接近散开终点时减速到 0。
	var progress: float = 1.0 - pow(1.0 - t, 2.0)
	var distance: float = distance_tiles * TILE_SIZE * progress
	var biased: Vector2 = (direction + Vector2.UP * InspirationDrop.SCATTER_UPWARD_BIAS).normalized()
	return biased * distance


## 悬停时的上下浮动：轻微正弦，幅度 1.5px。
static func hover_bob(elapsed: float) -> float:
	var since: float = maxf(elapsed - InspirationDrop.SCATTER_END, 0.0)
	return sin(since * TAU * 2.0) * 1.5


## 散开速度（格/秒），用于表现层取样；与散开位移曲线一致。
static func scatter_speed(elapsed: float, distance_tiles: float) -> float:
	var span: float = InspirationDrop.SCATTER_END - InspirationDrop.BURST_END
	if span <= 0.0 or elapsed < InspirationDrop.BURST_END or elapsed > InspirationDrop.SCATTER_END:
		return 0.0
	var t: float = (elapsed - InspirationDrop.BURST_END) / span
	return distance_tiles * TILE_SIZE * 2.0 * (1.0 - t) / span


## 飞入进度曲线：先慢后快（初速 2 格/秒 → 末速 20 格/秒）。
## 返回 0~1 的位移比例。
static func fly_progress(fly_elapsed: float, fly_duration: float) -> float:
	if fly_duration <= 0.0:
		return 1.0
	var t: float = clampf(fly_elapsed / fly_duration, 0.0, 1.0)
	# 速度从 v0 线性升到 v1，位移是速度的积分，归一化后得到下面的曲线。
	var v0: float = InspirationDrop.FLY_SPEED_START
	var v1: float = InspirationDrop.FLY_SPEED_END
	var total: float = (v0 + v1) * 0.5
	return (v0 * t + (v1 - v0) * 0.5 * t * t) / total


## 当前位置：start 是散开后的悬停位置，target 是玩家实时位置。
static func position_at(start: Vector2, target: Vector2, fly_elapsed: float, fly_duration: float) -> Vector2:
	return start.lerp(target, fly_progress(fly_elapsed, fly_duration))


## 螺旋飞入：在直线插值的基础上叠加旋转偏移，Boss 光点用。
static func spiral_position_at(start: Vector2, target: Vector2, fly_elapsed: float, fly_duration: float, turns: float = 2.0, radius_px: float = 18.0) -> Vector2:
	var base: Vector2 = position_at(start, target, fly_elapsed, fly_duration)
	var t: float = clampf(fly_elapsed / maxf(fly_duration, 0.001), 0.0, 1.0)
	var angle: float = t * TAU * turns
	# 越接近目标螺旋半径越小，最后归零，避免抖动。
	var shrink: float = radius_px * (1.0 - t)
	return base + Vector2(cos(angle), sin(angle)) * shrink


## 飞入最后 0.2s 的缩放：1 → 0。
static func arrival_scale(fly_elapsed: float, fly_duration: float) -> float:
	var remaining: float = fly_duration - fly_elapsed
	if remaining >= InspirationDrop.FLY_IN_LAST:
		return 1.0
	return clampf(remaining / InspirationDrop.FLY_IN_LAST, 0.0, 1.0)


## 拖尾每节的透明度：0 最亮，越靠后越淡。
static func trail_alpha(index: int, segments: int) -> float:
	if segments <= 0:
		return 0.0
	return clampf(1.0 - float(index) / float(segments), 0.0, 1.0) * 0.6


## 拖尾每节的大小比例。
static func trail_scale(index: int, segments: int) -> float:
	if segments <= 0:
		return 0.0
	return clampf(1.0 - float(index) / float(segments), 0.2, 1.0)


## 光点直径：数值越大越粗，夹在 4~12px。
static func diameter_for(amount: int) -> float:
	return clampf(InspirationDrop.DIAMETER_MIN + float(maxi(amount, 1)) * 0.6, InspirationDrop.DIAMETER_MIN, InspirationDrop.DIAMETER_MAX)


## 拖尾节数：数值越大越长，夹在 3~8 节。
static func trail_segments_for(amount: int) -> int:
	return clampi(InspirationDrop.TRAIL_SEGMENTS_MIN + maxi(amount, 1) / 3, InspirationDrop.TRAIL_SEGMENTS_MIN, InspirationDrop.TRAIL_SEGMENTS_MAX)


## 拖尾颜色：金 → 琥珀 → 透明。
static func trail_color(index: int, segments: int) -> Color:
	var t: float = 0.0 if segments <= 1 else clampf(float(index) / float(segments - 1), 0.0, 1.0)
	var gold := Color(1.0, 0.86, 0.36)
	var amber := Color(0.85, 0.55, 0.12)
	var color: Color = gold.lerp(amber, t)
	color.a = trail_alpha(index, segments) / 0.6
	return color


## 合并判定：同屏光点超过阈值就合并成光团。
static func should_merge(active_points: int) -> bool:
	return active_points > InspirationDrop.MERGE_THRESHOLD
