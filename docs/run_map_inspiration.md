# 地图系统 + 初始房间（炼金工坊）+ 灵感系统

本文档描述新系统的模块拆分、数据结构、核心算法与实现顺序，对应任务书《地图系统 + 初始房间 + 灵感系统》。
旧的连续箱庭生成（`resources/world/*`）保留可用；新系统在 `resources/run/*` 与 `resources/inspiration/*` 下独立实现，
两者通过 `GameWorld` 的入口切换，不互相读取内部数据。

---

## 1. 模块拆分与依赖

```
resources/run/                     # 局内地图（纯逻辑，可单元测试）
├── room_kind.gd                   # 10 种房间类型 + 炼金决策归类
├── room_shape.gd                  # 7 种房间形状与词条倾向
├── region_theme.gd                # 区域主题实例
├── region_theme_catalog.gd        # 13 个区域主题配置表
├── scene_element_catalog.gd       # 可吸附场景元素配置表
├── breakable_catalog.gd           # 可破坏物配置表
├── secret_door.gd                 # 8 种词条门需求与判定
├── door_info.gd                   # 门（类型 + 主题 + 材料预告 + 抗性/弱点）
├── room_data.gd                   # RoomData
├── region_data.gd                 # RegionData
├── floor_data.gd                  # FloorData + 邻接表 + 连通性
├── run_map_config.gd              # 生成配置（数量范围、环路、热量曲线）
└── run_map_generator.gd           # 生成器：链式主干 + 跳边 + 类型分配 + 保底 + 门

resources/inspiration/             # 灵感系统（纯逻辑）
├── inspiration_rules.gd           # 掉落表 / 留存 / 贤者之石转化 / 结算公式
├── inspiration_drop.gd            # 光点表现参数（阶段、轨迹、速度、对象池）
└── inspiration_run.gd             # 局内账本：累计 / 死亡 / 通关结算

resources/workshop/                # 局外炼金工坊
├── difficulty_tier.gd             # 难度祭坛 3 档 + 解锁规则 + 修饰接口预留
├── permanent_upgrade.gd           # 永久升级配置项
├── permanent_upgrade_catalog.gd   # 永久升级配置表（升满 29100 灵感）
└── permanent_upgrade_state.gd     # 已购等级 / 永久灵感池 / 购买与前置
```

依赖方向单向向下：`场景 / UI → 系统状态 → 配置表 + 纯逻辑`。
`resources/run` 与 `resources/inspiration` 之间只有「灵感结算读房间结果」一条弱依赖；
两者都不引用节点、UI 或炼金内部结构。

### 与炼金系统的接口

炼金系统输出（由炼金侧提供，地图/灵感侧只读）：

| 接口 | 用途 |
|------|------|
| `GetCurrentAlchemyEffect() -> EffectData` | 小地图显示当前炼金效果 |
| `GetRemainingDuration() -> Float` | 小地图倒计时 |
| `GetHeatLevel() -> Float` | 小地图热量条 |
| `OnAlchemySuccess(EffectId)` / `OnAlchemyFailed(Reason)` / `OnOverload()` | 事件回执 |

地图系统对炼金系统提供：

| 接口 | 说明 |
|------|------|
| `GetNearbyAlchemyMaterials(Position, Radius) -> MaterialList` | 附近可吸附场景元素 |
| `GetRoomThemeMaterials(Theme) -> MaterialList` | 房间主题对应材料 |
| `GetRoomHeatBudget(RoomType) -> HeatRange` | 房间热量预算 |

灵感系统与战斗系统对接：

| 接口 | 说明 |
|------|------|
| `OnEnemyKilled(Enemy, EnemyType)` | 触发灵感掉落 |
| `OnBreakableDestroyed(BreakableId, Position)` | 场景破坏掉落 |
| `OnPlayerDeath()` | 死亡结算 |
| `OnRunEnd(Result) -> FinalInspiration` | 通关结算 |

只留接口、本期不实现的系统：遗物（`GetEquippedRelics` / `ApplyRelicEffects`）、难度诅咒
（`GetDifficultyTier` / `GetDifficultyModifiers` / `GetShardMultiplier`）、图鉴
（`GetCodexCompletion` / `OnCodexEntryDiscovered`）、成就（`GetAchievements` / `OnAchievementUnlocked`）。

---

## 2. 数据结构设计

### RoomData（`resources/run/room_data.gd`）

| 字段 | 类型 | 说明 |
|------|------|------|
| `node_id` | int | 全层唯一（区域下标 × 100 + 房内下标） |
| `region_index` / `depth` | int | 所属区域 / 距起点深度 |
| `kind` | RoomKind.Kind | 房间类型 |
| `theme_id` | StringName | 区域主题 |
| `shape` | RoomShape.Shape | 房间形状 |
| `scene_elements` | Array[StringName] | 可吸附元素 |
| `breakables` | Array[StringName] | 可破坏物 |
| `enemy_spawns` | Array[Dictionary] | 刷怪槽（主题 / 档位 / 种子） |
| `doors` | Array[DoorInfo] | 打完后的可选路线 |
| `material_drops` | Array[Dictionary] | 材料掉落 |
| `secret_door` | Dictionary | 词条门（目标 + 需求） |
| `heat_budget` | Vector2 | 热量预算区间 |

### RegionData / FloorData

- `RegionData`：`index` / `theme_id` / `rooms` / `material_pool` / `enemy_pool` / `links`，并提供 `loop_count()`。
- `FloorData`：`floor_index` / `regions` / `boss_room` / `rooms` / `links`，提供 `reachable_from()`、
  `is_fully_connected()`、`start_room()`。

### InspirationDrop / InspirationRun

- `InspirationDrop` 是纯参数：阶段时长、散开与飞入速度、光点直径、拖尾节数、对象池 200、合并阈值 30，
  以及每种来源的悬停时长 / 轨迹 / 音效 / 是否分批飞入。
- `InspirationRun` 是局内账本：`gained`（已飞入）、`in_flight`（飞行中）、`by_source`，
  提供 `launch()` / `collect()` / `death()` / `settle()`。

### PermanentUpgrade / PermanentUpgradeState

- `PermanentUpgrade`：`id` / `name` / `max_level` / `costs[]` / `effects[]` / `effect_kind` /
  `trait_id` / `prerequisite_id` / `prerequisite_level` / `description`，效果为累计语义。
- `PermanentUpgradeState`：`inspiration`（永久池）、`levels`、`clears`，提供
  `can_purchase()` / `purchase()` / `effect_value()` / `element_level()` / `retention_ratio()` / `to_dict()`。

---

## 3. 核心算法伪代码

### 3.1 房间图生成（树状 + 少量环路）

```
for 区域 in 区域列表:
    房间数 = rng(4..8)
    建立 房间[0..n-1]，node_id = 区域下标 * 100 + 房内下标
    for i in 0..n-2:            # 主干链
        连接(i, i+1)
    for i in 0..n-3:            # 跳边 → 环路 + 第二个出口
        if rng < loop_chance: 连接(i, i+2)
    for i in 0..n-4:            # 偶发跳两间 → 第三个出口
        if rng < loop_chance*0.35: 连接(i, i+3)
跨区域：上一区域所有末端房间 → 下一区域起点
Boss：末区域所有末端房间 → Boss 房
```

### 3.2 房间类型分配与保底

```
全部房间默认 战斗房
随机撒点：40% 取材/冷却，22% 精英
每区域至少保留 2 个战斗房
保底（按全层均分取 4 个互不相同的槽位）：
  续组合→战斗房、换组合→精英房、取材→事件/商店/宝箱、冷却→休息/炼金
热量曲线：连续战斗房 > 4 时，把段内第一个非保底战斗房改成冷却房
秘密房：额外生成 1 个房间，挂在随机宿主房上（词条门进入，不出现在普通门里）
```

### 3.3 门分配

```
对每个非 Boss / 非秘密房：
    候选 = 邻接表中排除秘密房的目标
    取前 3 个，生成 DoorInfo（目标房类型 + 主题 + 2 个材料预告 + 抗性/弱点）
```

### 3.4 灵感掉落与飞入

```
roll(来源, rng):
    if rng.randf() > 概率: return 0
    return rng.randint(最小, 最大)

光点生命周期：
    0.0~0.1s 生成：从敌人位置爆出，带闪光
    0.1~0.4s 散开：随机方向弹射，偏向上方，3~5 格/秒，距离 0.5~1.5 格
    0.4~0.8s 悬停：减速到 0，轻微上下浮动，闪烁（精英 0.4s / Boss 0.6s）
    0.8s 之后：无条件实时追踪玩家，穿墙，初速 2 格/秒加速到 20 格/秒
    最后 0.2s：加速冲入，缩小消失
同屏光点 > 30 时合并为光团，飞入后拆分数字；对象池预分配 200
```

### 3.5 贤者之石结算

```
材料转化 = Σ 品质转化值(普通 2 / 稀有 8 / 史诗 25 / 传说 80) + Boss 材料 200 × 数量
基数     = 局内已获得灵感 + 贤者之石基础 100 + 材料转化 + 表现加成
最终灵感 = round(基数 × 难度倍率(学徒 1.0 / 炼金师 1.2 / 大师 1.5) × (1 + 图鉴加成))
死亡结算：保留 = round(局内灵感 × 留存比例(0/5/10/15/20/25%))，其余损失
```

---

## 4. 实现顺序与状态

### P0

| # | 内容 | 状态 |
|---|------|------|
| 1 | 炼金工坊场景 + 交互点框架（按 E 打开界面） | 已完成（`scenes/workshop/workshop.tscn`、`scripts/workshop/workshop.gd`、`workshop_interactable.gd`） |
| 2 | 出发门：选武器 + 携带材料 + 难度 + 开始 | 已完成（`departure_gate_panel.gd` → `workshop.start_run()`） |
| 3 | 永久升级数据结构 + 炼金台 UI + 灵感购买 | 已完成（`permanent_upgrade_*` + `upgrade_panel.gd`，升满 29100 灵感） |
| 4 | 灵感掉落：小怪 / 精英 / Boss 概率与数量 | 已完成（`inspiration_rules.gd`） |
| 5 | 灵感光点动画：生成→散开→悬停→无条件飞入 | 已完成（`inspiration_flight.gd` 纯函数 + `inspiration_field.gd` / `inspiration_pickup.gd` 对象池节点） |
| 6 | 灵感 UI 计数 + 飘字 | 已完成（`scripts/inspiration/inspiration_hud.gd`） |
| 7 | 死亡结算：损失所有 + 灵感留存 | 已完成（`inspiration_run.death()` + `game_world._on_player_defeated()`） |
| 8 | 贤者之石结算：材料转化 + 结算界面 | 已完成（`inspiration_rules.settlement()` + `run_settlement_panel.gd`） |
| 9 | 房间图生成：树状 + 环路、房间类型分配、保底与热量曲线 | 已完成（`run_map_generator.gd`） |
| 10 | 基础房间模板：战斗 / 精英 / 休息 / 商店 / 事件 / 宝箱 / 炼金 / 秘密 | 已完成（`room_data.gd` + 生成器落内容：刷怪 / 掉落 / 门 / 热量预算） |
| 11 | 门选择 UI：类型 + 主题 + 材料预告 + 抗性/弱点 | 已完成（`door_info.gd` + `scripts/ui/door_choice_panel.gd`） |
| 12 | 场景可吸附元素放置 | 已完成（`scene_element_catalog.gd` + `room_props.gd` + `game_world._setup_room_props()`） |

### P1 / P2

| 内容 | 状态 |
|------|------|
| 区域主题配置 + 材料掉落联动 | 已完成（`region_theme_catalog.gd`，13 个主题，含抗性 / 弱点） |
| 训练场 / 材料库 / 难度祭坛 3 档 | 已完成（`training_ground_panel.gd` 确认前往 `training_arena.tscn` 独立试验场；`material_vault_panel.gd`、`difficulty_altar_panel.gd`） |
| 秘密房 + 词条门（数据） | 已完成（`secret_door.gd` 8 种门 + `room_data.secret_door`） |
| 秘密房入口运行时 | 已完成：宿主房出口生成词条门（`scripts/items/secret_door_prop.gd`），未开门时封路，带对应词条敲开或按 E 开门 |
| 图鉴台 / 遗物架 / 成就墙 / 商店 | 只留接口（`placeholder_panel.gd`） |
| 小地图（房间类型 / 主题色 / 未探索 ? / 秘密房 / 炼金效果 + 热量条） | 已完成（`minimap_layout.gd` + `scenes/ui/minimap.gd`；旧的按地形采样的小地图已删除） |
| Boss 多阶段弱点变化 | 未做 |
| 事件房内容 / 挑战房 / 宝箱房 / 炼金房 | 房间类型已在生成器里分配，具体内容未做 |

---

## 5. 测试

```sh
# 纯逻辑
godot --headless --path . --script res://tests/test_run_map.gd             # 987 项
godot --headless --path . --script res://tests/test_inspiration.gd         # 2131 项
godot --headless --path . --script res://tests/test_permanent_upgrades.gd  # 264 项
godot --headless --path . --script res://tests/test_room_props.gd          # 2290 项
godot --headless --path . --script res://tests/test_secret_door.gd         # 231 项
godot --headless --path . --script res://tests/test_secret_door_world.gd   # 15 项
godot --headless --path . --script res://tests/test_run_settlement.gd      # 21 项
godot --headless --path . --script res://tests/test_weapon_catalog.gd      # 123 项
# 场景 / 世界集成
godot --headless --path . --script res://tests/test_workshop.gd            # 139 项
godot --headless --path . --script res://tests/test_run_map_world.gd       # 1157 项
godot --headless --path . --script res://tests/test_inspiration_world.gd   # 21 项
godot --headless --path . --script res://tests/test_minimap_layout.gd      # 389 项
godot --headless --path . --script res://tests/test_minimap_room_world.gd  # 24 项
```

也可以一次跑完 `tests/` 下的全部脚本测试（单个测试带超时，避免渲染型测试在无头模式挂住）：

```sh
pwsh -File tools/run_tests.ps1
```

新增 `class_name` 脚本后需要先让编辑器扫描一次：

```sh
godot --headless --path . --editor --import --quit
```
