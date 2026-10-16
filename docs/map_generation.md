# 地图生成架构：固定骨架 + 随机血肉 + 约束校验 + 种子系统

本文档描述关卡地图的生成架构：可配置房间骨架、按种子分配的区域单一群系、起始小屋、低频柏林噪声大片地形，以及出入口黑屏淡入淡出、区块流式加载和生成约束校验。每个区域的群系身份固定，区域内部的噪声只改变地形与轮廓。

## 分层

| 层 | 文件 | 职责 |
| --- | --- | --- |
| 种子 | `resources/world/map_rng.gd` | 统一随机源，全部从主种子派生 |
| 骨架 | `resources/world/room_graph.gd`、`run_graph.gd` | 房间图：节点=区域，边=连接；类型、主路径、关键房间 |
| 类型 | `resources/world/room_type.gd` | START / COMBAT / REWARD / SHOP / REST / EVENT / BOSS |
| 节奏 | `resources/world/map_config.gd` | 节奏模板、数量范围、评分权重、重试上限 |
| 模板 | `resources/world/region_template.gd`、`region_templates.gd` | 区域规格：尺寸范围、允许类型、门朝向、权重 |
| 群系 | `resources/world/region_biomes.gd` | 区域主题按种子打乱，固定 START 森林与战斗/Boss 雨林保障 |
| 小屋 | `resources/world/cottage_layout.gd`、`scenes/world/cottage_view.gd` | 初始屋布局与家具、通行地形、绘制与切图显示 |
| 生成 | `resources/world/world_generator.gd`、`map_spec.gd` | 区域单一群系 + 低频大片地形 + 区域轮廓 + 内部道路 |
| 校验 | `resources/world/map_validator.gd` | 硬约束校验与同种子变体重生成 |
| 评分 | `resources/world/map_scorer.gd` | 软约束评分，best-of-N |
| 内容 | `resources/world/map_content.gd` | 按房间类型产出内容预算与落点 |
| 地表兴趣点 | `resources/world/world_population.gd` | 营地、遗迹、石阵、补给点、药草园、随机宝箱与散落物资 |
| 调试 | `resources/world/map_debug.gd` | 报告、ASCII 布局 |

入口：`scenes/game/game_world.gd` 的 `build_world(seed)` → `MapScorer.build_best(seed)`。

## 种子系统

`MapRng` 提供两套随机：

- **无状态派生**（地图用）：`noise_seed`、`node_seed`、`node_rng`、`layout_rng`、`rng(stream, salt)`。同一个 `(主种子, 流, 盐)` 永远得到同一序列，不依赖调用顺序，所以工作线程、分块生成与重复生成结果一致。
- **命名共享流**（战斗等拿不到生成器引用的子系统用）：`MapRng.shared(stream)`，开新世界时用 `MapRng.set_shared_master(seed)` 重置。

流：`MAP` 地形、`ROOM` 骨架与模板、`ENEMY` 刷怪、`LOOT` 物品、`DECOR` 装饰、`COMBAT` 战斗判定。

## 配置

`MapConfig` 有完整默认值：原 8 层主线和 14 个节点 ID 均保留，第 3 列额外加入一个分支（共 15 个箱庭）；将 `pyramid_third_branch` 设为 `false` 可恢复原节点数量。

- 骨架：`floor_count`、`branch_floors`、`pyramid_third_branch`、`min_path_len`/`max_path_len`、`min_branches`/`max_branches`。
- 关键房间：`shop_count`、`min_rewards`/`max_rewards`、`rest_every_floors`/`min_rests`、`boss_key_buffer`。
- 节奏：`rhythm_templates`（留空用 `DEFAULT_RHYTHM_TEMPLATES`）。模板长度与 `floor_count` 不一致时自动伸缩，只增删战斗位，不丢关键房间；随后按配置强制校正关键房间数量与位置。
- 分支：`branch_reward_chance`。
- 校验/评分：`max_retries`、`candidate_count`、`weight_*`。
- 区域模板：`RegionTemplates.defaults()` 按房间类型给出尺寸倾向；`RegionTemplate.matches()` 按类型 + 门朝向 + 形状筛选，无匹配时降级到 `fallback()`。

## 横向金字塔列

关卡仍有 8 层原主路径，旧节点编号和所有旧双向连接保持不变。默认在第 3 列加一个真正可到达的新岔路：前 3 列分别为 1、2、3 个箱庭，之后的双房列和最后的单房列继续使用原节奏。新岔路由第 2 列下侧分支进入，再经下一列下侧分支返回主线；启用 `pyramid_third_branch=false` 可恢复原 14 个节点。

同列箱庭上下边相接，相邻列东西边相接；同列统一宽度，`MapSpec.template_extent` 保留抽样的原模板尺寸，非小屋箱庭的庭室中心、池塘位置随最终宽度等比例伸展。整个地图呈横向连片金字塔，不允许矩形重叠、断层或只在角点碰触，这些布局规则现由 `MapValidator` 验证。图边仍由原有东/西门控制，部分上下错位的图边仍在黑屏中传送，不能从任意地块接缝步行跨区。

玩家触门后复用 `SceneManager` 的黑幕：先淡入全黑并冻结玩家与攻击，黑屏绘制完成时执行原 `_enter_map` 同步加载、限相机和保留背包/实体的流程，目标视口铺好后淡出。期间拒绝重复切换；无图形的自动化环境不等待渲染回调。

按 M 展开的地图包含整局所有箱庭，以低亮度群系底色显示未探索区的布局轮廓，已探索的地形仍使用每格快照；隐藏邻图预加载不会计入探索。compact 小地图仍按世界坐标采样当前周边区域。

## 区域单一群系与大片地形

每张 `MapSpec` 保存一个 `biome_id: int`。区域完整 `Rect2i(origin, extent)` 内的所有格子都满足 `sample_biome(tile) == spec.biome_id`，包括山林边缘、室内、家具和池塘。水地形不会改写群系身份，边界也使用当前区域主题。

`RegionBiomes` 将区域主题序列按主种子打乱分配；同种子与同布局变体的分配保持确定。START 0 固定为森林。正式游戏通过 `MapConfig.combat_biomes` 从现有怪物定义派生可用群系并集，所有 COMBAT/BOSS 区域匹配这个内容池；目前为稀树草原、草原、森林和热带雨林，其他房型保留多样主题。配置允许雨林时保证至少一个雨林战斗区域，不会强行覆盖仅支持其他主题的自定义池。独立生成器的该参数留空时仍不限制主题；区块与小地图采样继续使用主生成器的同一配置。数据层仍保留全部 14 种群系定义，实际陆地区域从主题列表分配。

区域内的地表、树林和边缘使用同种子的世界坐标低频 `FastNoiseLite.TYPE_PERLIN`，单 octave 生成大簇同主题地面、连续森林与岩壁；共享箱庭边缘另外在 8 格宽度内轻微混合相邻主题，只改变图集显示，不改各地图独立的群系与碰撞。道路、屋墙和水岸仍会产生必要的地形边界。回归脚本统计完整矩形中水平/垂直相邻格子的地形变更率，以及可走地面和阻挡格子的四连通簇；出生连通块和可走主连通块至少覆盖 95% 的可走格子，单格阻挡簇数量最多占全部格子的 0.5%。邻格变更率同时输出测量值，以 0.13 作为包含道路、墙与水边的初步上限，后续调整需结合地图外观和通行质量。

## 地块视觉过渡

[TerrainTransitions](../resources/world/terrain_transitions.gd) 在铺图时读取本区块及外围一格邻居，为草地、土路、岩地、密林和水岸选择融合贴图。四个邻边合并为掩码，对角接触补圆角；邻格跨区块时继续查询同一生成器，因此不会出现区块接缝。桥面和屋内结构保持原有轮廓。

图集由 [生成工具](../tools/generate_terrain_transitions.py) 从已有 16 种地形和 3 种道路贴图生成，边沿约 6 像素宽，包含四档箱庭入口色调混合。不同箱庭的入口两侧在约 10 格内向相邻区域地面色靠近，门带附近最多混合一半；每个箱庭的 `biome_id`、道路、碰撞和可走性继续使用原始数据。图集作为 TileSet 的第三个来源，铺图仍通过 TileMapLayer 池复用。

## 地面炼金材料

[GroundMaterials](../resources/world/ground_materials.gd) 使用 LOOT 独立随机流，将主种子、变体和区域编号派生为固定材料布局。每图按面积规划 20–70 个材料点，16 格世界网格内最多一个，相邻材料至少间隔 6 格，避开水域、阻挡、屋内、出生点和门口。森林主题木棍较多，荒漠和岩地石头较多；每图都有两类材料，小屋平台右侧优先放置两种材料供开局尝试。

靠近后按 E 拾取最近且通路无遮挡的材料；背包、炼金界面打开或任何 GUI 拖拽进行时关闭世界拾取，保留快捷栏拖拽中 E 键旋转物品的原操作。界面显示名称和数量，材料进入背包并可堆叠。地面节点归属地图实体根，离图隐藏暂停，返回保留未拾取的物品且不补刷已拾取点位；换世界时清理旧节点并生成新分布，沿用背包保留规则。

石头（id=2）提供矿物属性，木棍（id=3）提供木质属性。通过原背包拖拽及炼金投放区生成独立 IngredientModel 刚体，坩埚消耗两者反应为固结属性（id=5）；固结会给出「固化」效果（减伤），矿物加火反应则产出「护己」（自己扔的药水不伤自己）。地面 [GroundPickup](../scripts/items/ground_pickup.gd) 不使用炼金刚体，避免世界物品滚动或阻挡通行。

## 地表结构、宝箱与掉落物

`WorldPopulation` 在基础地形完成后为每个区域规划 6–16 处结构，包含营地、残垣遗迹、石阵、废弃补给点和药草园；类型轮换保证多样性，位置、配色变体按种子随机。完整结构及周边一格必须是无水、无道路的可通行空地，并避开小屋、出生点、出入口和其他兴趣点。帐篷、遗迹石柱、立石和补给箱的实心格由 `WorldGenerator` 统一覆盖为阻挡地形，画面与玩家、怪物的通行查询使用同一份数据，主道路保持畅通。

每个区域另有 2–4 个随机宝箱，奖励区域增加 2 个；每个宝箱有 25% 概率为珍稀宝箱。普通箱掉落 3 堆、每堆 1–3 件，珍稀箱掉落 4 堆、每堆 2–5 件。当前物品池为已有的草药、木棍、石头、炸弹，不引入新物品 ID，也不将怪物专属材料放入宝箱。每区还散落 10–24 堆草药、木棍和石头，与原有材料点共同避让。

靠近后按 E 开箱，再靠近掉落物按 E 拾取入包；交互提示同时显示目标名称。统一选择最近且可达的宝箱或物品，背包、炼金界面、拖拽、死亡和切图期间沿用世界交互限制。宝箱和掉落物归属地图实体根，切图隐藏暂停，返回保留本局开启及拾取状态；重开世界重置分布。此状态与现有材料一样保存在当前游戏会话中，不包含磁盘存档。

规划使用独立 DECOR/LOOT 子随机流，主种子、区域和布局变体相同时结果一致。区块工作线程共享已完成的只读兴趣点数据，各自保留独立噪声实例，避免反复规划整局结构。`GroundPickup` 将世界物品图标限制在 16 像素内，兼容炸弹等较大分辨率的原始图标。

专项验证：

```sh
godot --headless --path . --script res://tools/test_world_population.gd
godot --path . --rendering-method gl_compatibility --script res://tools/test_world_population.gd -- --capture --runtime-only
```

数据检查覆盖四个种子的全部区域，验证布局复现、不同种子差异、结构碰撞、完整四连通可达性、工作线程区块一致性和原材料点避让；运行时检查 E 开箱、落地拾取、重复操作、界面阻断、离图暂停、回图不补刷和新世界重置。截图保存为 `.godot/population-*.png`。

## 起始小屋

只有 START 0 的 `MapSpec.cottage: CottageLayout` 非空，其他区域为 `null`。初图 `shape_name()` 返回「起始小屋」，关闭池塘与河流，`MapContent.ENEMY` 预算为 0，保证开局安全。

小屋数据全部使用区域本地格子坐标：

| 字段/接口 | 约定 |
| --- | --- |
| `bounds: Rect2i` | 宽 20–24 格，高 16–18 格，位于区域内 |
| `spawn_tile: Vector2i` | 屋内中心，地板可走，作为初始玩家落点 |
| `door_tile: Vector2i` | 右墙上的门格，连通屋内与屋外 |
| `porch_tile: Vector2i` | 门外右侧 3 格，作为外部道路的连接点 |
| `furniture: Array` | 每项为 `{kind, rect}`，家具矩形阻挡通行 |
| `terrain_at(local)` | 石地 `STONE` 为地板，山地 `MOUNTAIN` 代表木墙/家具，屋外返回 `-1` |
| `label_at(local)` | 对应格子的名称，供显示与查询使用 |

`MapSpec.build_roads()` 继续使用每段五个浮点数的打包格式 `[ax, ay, bx, by, phase]`。小屋内部只生成 `center/spawn → porch` 的直线段，`phase = -1`；其他出入口与侧庭的主连接从 porch 出发，保留屋外侧庭回路。生成器优先保留小屋墙壁和家具的阻挡，不能由普通道路判定将它们变成可走格。

运行时 `GameWorld` 加载后玩家位于屋内。直属 `CottageView` 节点绑定当前 `MapSpec`，离开初图时隐藏、返回初图时显示；换种子重建后重新绑定新布局。切图仍按当前区域矩形设置相机 limits，保留玩家生命、装备与背包/炼金界面实例；重建世界沿用生命重置行为。

## 硬约束（`MapValidator.validate`）

1. 全图连通。2. 起点到 Boss 可达。3. 所有关键房间可达。4. 无区域重叠。5. 门对齐。6. 无死锁。7. 主路径长度在范围内。

不合格时在**同一主种子下换布局变体**重试（`variant`，最多 `max_retries` 次），世界身份不变；超过上限用问题最少的候选兜底。

地形与材料专项 [验收脚本](../tools/test_transitions_materials.gd) 已在 Godot 4.6 通过 7,388 项带截图检查，覆盖四个种子、2,374 个材料点位，验证边沿掩码与圆角、跨区块 halo、入口混色不改变群系、材料点位确定性与合法性、真实 E 键拾取、返回不补刷、背包保留，以及投放区模型和坩埚反应。连续通路、26 项切图状态和小地图模式回归也通过。添加 `-- --capture` 可保存 `.godot/transitions-materials-preview.png`。

[协作者兼容验收](../tools/test_inventory_material_compatibility.gd) 通过 225 项检查，验证新旧物品/属性 ID 保留、背包与快捷栏数量同步、整堆交换和同类多格、返还背包、真实 GUI 拖拽中 E 只旋转不拾取，以及原治疗升级与持续治疗配方。四个种子各两个变体逐房核对所有正敌人预算区域，均可使用现有怪物定义；实际游戏战斗房可实例化怪物，追加群系与不限制群系的定义均自动适配，森林单一池不会被雨林保障覆盖。直接首次调用通用刷怪接口时也会创建带类型的空怪物数组，避免首次登记的类型错误。

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
godot --headless --path . --script res://tools/test_pyramid_world.gd
godot --headless --path . --script res://tools/test_cottage_biomes.gd
godot --headless --path . --script res://tools/test_transitions_materials.gd
godot --headless --path . --script res://tools/test_inventory_material_compatibility.gd
```

`test_cottage_biomes.gd` 使用四个种子与两个变体，比较整张 `MapSpec`（含小屋与群系）及覆盖全部区域的区块数据，检查完整矩形单群系、起始屋安全预算、不同种子布局多样性与 `MapValidator.validate()` 空结果。四个种子各选初图和至少两个非初始区域进行整图四连通 BFS，验证出生点可达全部有效门和侧庭，并打印地形碎片统计。运行时加载真实游戏场景，检查小屋显示/隐藏/返回、初始位置、相机 limits、种子重建内容变化和原有状态保留；等 autoload 注册后动态加载场景，避免测试编译提前引用运行时单例。

金字塔专项测试覆盖 4 个种子 × 2 种布局变体、相接边的混色、原主线和新增岔路双向通行、全屏总览不泄露隐藏地图，以及黑幕期间输入锁。Godot 4.6 的无图形模式通过 1,076 项检查；有图形渲染时另验证画布中央与边角像素全黑，共 1,079 项。金字塔地图及全黑切换截图需要正常图形渲染：

```sh
godot --path . --script res://tools/test_pyramid_world.gd -- --capture
```

输出 `.godot/pyramid-map-preview.png` 和 `.godot/pyramid-gate-fade.png`，实际图形帧均已检视；全屏视图中未探索区域仅显示低亮度群系底色，已探索区域显示真实逐格地形。小屋的可选截图也需要正常图形渲染运行：

```sh
godot --path . --script res://tools/test_cottage_biomes.gd -- --capture
```

在 `RenderingServer.frame_post_draw` 后读取真实 viewport，保存 `.godot/cottage-preview.png` 和 `.godot/region-biome-preview.png`（非初始热带雨林区域），并检查图片非空、保存错误码与文件存在。本轮使用 Godot 4.6 生成验收采样 3,723,787 格、4,963 个区块；12 次整图 BFS 的出生连通块覆盖率均为 100%，邻格地形变更率为 0.96%–2.00%，无单格阻挡碎片。专项脚本还验证 100/100 个种子通过硬约束、约 88,546 个道路样本连续，回程怪物死亡记录和已拾取物品不会补刷；黑幕截图确认真实全黑。仅需截图或运行时复核时可加 `-- --capture --runtime-only`，避免重复已通过的完整区块采样。
