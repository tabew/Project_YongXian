class_name EnemyAIConfig
extends Resource

## 单种怪物的 AI 数据配置。怪物脚本不写死数值，所有行为参数都在这里。
##
## 每个怪物进入场景树时会复制一份自己的配置，运行时修改只影响该怪物，
## 因此多个怪物可以共享同一个 .tres 而不会互相污染。

@export_group("标识")
## 用于随机种子与调试显示；同一种怪物保持一致即可。
@export var ai_id: StringName = &"monster"

@export_group("巡逻")
## 巡逻半径（格）。为 0 时怪物只在 PatrolAnchor 原地等待环顾，适合哨兵。
@export_range(0.0, 64.0, 0.5) var patrol_radius_tiles: float = 4.0
## 到达巡逻点后的等待/环顾时间。
@export_range(0.0, 20.0, 0.1) var patrol_wait_time: float = 1.2
## 出生后先原地环顾的时间，避免刚生成就立刻走开。
@export_range(0.0, 20.0, 0.1) var patrol_start_delay: float = 0.6
## 每次选点最多尝试多少个候选格子。
@export_range(1, 64, 1) var patrol_point_attempts: int = 12
## 等待环顾时朝向旋转速度（度/秒），只在配置了视野锥时有意义。
@export_range(0.0, 720.0, 1.0) var patrol_scan_speed_degrees: float = 45.0

@export_group("感知")
@export_range(0.0, 64.0, 0.5) var vision_distance_tiles: float = 10.0
## 360 表示全向视野；小于 360 时只在朝向锥内看到玩家。
@export_range(10.0, 360.0, 1.0) var vision_angle_degrees: float = 360.0
## 视线评估间隔；配合 PerceptionManager 与 stagger 分帧，避免每帧全量检测。
@export_range(0.0, 5.0, 0.01) var perception_interval: float = 0.15
## 听到噪音/警报的半径。
@export_range(0.0, 64.0, 0.5) var hearing_radius_tiles: float = 8.0
## 可疑事件的有效时间，过期后不再触发搜索。
@export_range(0.0, 60.0, 0.5) var suspicious_event_lifetime: float = 5.0

@export_group("攻击")
## 进入 Attack 状态的距离（格）。攻击实现自带 attack_range() 时以它为准。
@export_range(0.0, 64.0, 0.5) var attack_range_tiles: float = 2.0
@export_range(0.0, 30.0, 0.05) var attack_cooldown: float = 1.0
## 丢失视野后允许继续追击/攻击的宽限时间，超时后以当前位置为锚点回到 Patrol。
@export_range(0.0, 30.0, 0.1) var lose_sight_grace: float = 2.5
## 开启后 Chase/Attack 丢失视野会先进入 Search 再回 Patrol；最终仍不回出生点。
@export var search_on_lost_sight: bool = false

@export_group("搜索")
@export_range(0.0, 120.0, 0.5) var search_duration: float = 6.0
@export_range(0.0, 64.0, 0.5) var search_radius_tiles: float = 4.0
@export_range(1, 16, 1) var search_point_count: int = 4
## 每个搜索点的停留/环顾时间。
@export_range(0.0, 20.0, 0.1) var search_point_dwell_time: float = 0.9

@export_group("移动与寻路")
@export_range(1.0, 1000.0, 1.0) var move_speed: float = 72.0
## 同一怪物的两次寻路请求最短间隔。
@export_range(0.05, 10.0, 0.05) var path_refresh_interval: float = 0.4
## 路径失败或选不到点后的等待时间，避免卡墙时每帧重试。
@export_range(0.05, 10.0, 0.05) var path_failure_retry_delay: float = 1.0
## AStar 区域相对起点/终点外扩的格数。
@export_range(1, 32, 1) var path_margin_tiles: int = 6

@export_group("性能")
## 决策间隔；感知与状态转换按它分帧，路径跟随仍然每帧进行。
@export_range(0.0, 2.0, 0.01) var update_interval: float = 0.1
@export var lod_enabled: bool = true
## 超过该距离（格）进入 LOD：降低感知/寻路/动画更新频率。
@export_range(0.0, 256.0, 1.0) var lod_distance_tiles: float = 14.0
@export_range(1.0, 10.0, 0.5) var lod_interval_scale: float = 3.0
@export_range(1.0, 60.0, 1.0) var lod_animation_hz: float = 10.0
