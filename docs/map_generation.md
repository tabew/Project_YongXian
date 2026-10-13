# 地图生成架构：固定骨架 + 随机血肉 + 约束校验 + 种子系统

本文档描述关卡地图的生成架构。改造是**增量**的：原有噪声地形、箱庭轮廓、出入口瞬切与区块流式加载全部保留，只是在其上加了一层可配置的骨架与校验。

## 分层

| 层 | 文件 | 职责 |
| --- | --- | --- |
| 种子 | `resources/world/map_rng.gd` | 统一随机源，全部从主种子派生 |
| 骨架 | `resources/world/room_graph.gd`、`run_graph.gd` | 房间图：节点=区域，边=连接；类型、主路径、关键房间 |
| 类型 | `resources/world/room_type.gd` | START / COMBAT / REWARD / SHOP / REST / EVENT / BOSS |
| 节奏 | `resources/world/map_config.gd` | 节奏模板、数量范围、评分权重、重试上限 |
| 模板 | `resources/world/region_template.gd`、`region_templates.gd` | 区域规格：尺寸范围、允许类型、门朝向、权重 |
| 生成 | `resources/world/world_generator.gd`、`map_spec.gd` | 噪声地形 + 区域轮廓 + 内部道路 |
| 校验 | `resources/world/map_validator.gd` | 硬约束校验与同种子变体重生成 |
| 评分 | `resources/world/map_scorer.gd` | 软约束评分，best-of-N |
| 内容 | `resources/world/map_content.gd` | 按房间类型产出内容预算与落点 |
| 调试 | `resources/world/map_debug.gd` | 报告、ASCII 布局 |

入口：`scenes/game/game_world.gd` 的 `build_world(seed)` → `MapScorer.build_best(seed)`。

## 种子系统

`MapRng` 提供两套随机：

- **无状态派生**（地图用）：`noise_seed`、`node_seed`、`node_rng`、`layout_rng`、`rng(stream, salt)`。同一个 `(主种子, 流, 盐)` 永远得到同一序列，不依赖调用顺序，所以工作线程、分块生成与重复生成结果一致。
- **命名共享流**（战斗等拿不到生成器引用的子系统用）：`MapRng.shared(stream)`，开新世界时用 `MapRng.set_shared_master(seed)` 重置。

流：`MAP` 地形、`ROOM` 骨架与模板、`ENEMY` 刷怪、`LOOT` 物品、`DECOR` 装饰、`COMBAT` 战斗判定。

## 配置

`MapConfig` 有完整默认值，不配置也能跑，默认值与改造前的 8 层 14 区域一致。

- 骨架：`floor_count`、`branch_floors`、`min_path_len`/`max_path_len`、`min_branches`/`max_branches`。
- 关键房间：`shop_count`、`min_rewards`/`max_rewards`、`rest_every_floors`/`min_rests`、`boss_key_buffer`。
- 节奏：`rhythm_templates`（留空用 `DEFAULT_RHYTHM_TEMPLATES`）。模板长度与 `floor_count` 不一致时自动伸缩，只增删战斗位，不丢关键房间；随后按配置强制校正关键房间数量与位置。
- 分支：`branch_reward_chance`。
- 校验/评分：`max_retries`、`candidate_count`、`weight_*`。
- 区域模板：`RegionTemplates.defaults()` 按房间类型给出尺寸倾向；`RegionTemplate.matches()` 按类型 + 门朝向 + 形状筛选，无匹配时降级到 `fallback()`。

## 硬约束（`MapValidator.validate`）

1. 全图连通。2. 起点到 Boss 可达。3. 所有关键房间可达。4. 无区域重叠。5. 门对齐。6. 无死锁。7. 主路径长度在范围内。

不合格时在**同一主种子下换布局变体**重试（`variant`，最多 `max_retries` 次），世界身份不变；超过上限用问题最少的候选兜底。

## 调试

```
godot --headless --path . --script res://tools/map_debug.gd -- --seed 97231   # 指定 seed 的完整报告
godot --headless --path . --script res://tools/batch_generate.gd -- --count 100  # 批量生成与统计
```

游戏内把 `GameWorld.debug_map_report` 打开，每次生成世界都会打印报告。

## 回归

```
godot --headless --path . --script res://tools/test_seed_determinism.gd
godot --headless --path . --script res://tools/test_room_graph.gd
godot --headless --path . --script res://tools/test_region_templates.gd
godot --headless --path . --script res://tools/test_map_validation.gd
godot --headless --path . --script res://tools/test_map_scorer.gd
godot --headless --path . --script res://tools/test_map_content.gd
godot --headless --path . --script res://tools/test_continuous_world.gd
```
