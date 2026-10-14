# Project YongXian

使用 **Godot 4.7** 开发的 2D 肉鸽游戏项目。目前包含主菜单、**8 层关卡图 + 14 个随机陆地箱庭区域 + 区块流式加载 + 14 种生物群系**、右上角小地图与 M 全屏探索地图，以及一个可用 WASD 控制、带加速度的占位主角。已加入可配置近战武器系统、第一把长剑与可重生训练靶。

## 近战武器

鼠标瞄准，左键挥击，按住连续攻击，Q 切换长剑 / 长棍。长剑做大范围扇形横扫；长棍做 40° 小扇形挥舞，并带由远到近的大小、明暗过渡和短弧形拖尾。出生点附近的训练靶可验证伤害、暴击与击退。

- **调整现有武器**：在 Inspector 编辑 `resources/weapons/longsword.tres` 或 `resources/weapons/long_staff.tres`。
- **长剑类通用模板**：[swing_weapon_template.tres](resources/weapons/templates/swing_weapon_template.tres)，150° 扇形横扫。
- **长棍类通用模板**：[staff_weapon_template.tres](resources/weapons/templates/staff_weapon_template.tres)，40° 小扇形与由远到近过渡。
- **添加同类武器**：复制对应模板，修改唯一 ID、名称、数值和贴图，再加入玩家的 `weapon_loadout` 数组；无需新增脚本或攻击场景。
- **添加不同类型武器**：继承 `WeaponDefinition` / `WeaponAttack`，配置独立攻击场景，无需修改玩家或控制器。
- **完整说明**：[武器架构、参数、扩展和测试](docs/weapons.md)。

---

## 目录结构

```
Project_YongXian/
├── project.godot                  # 项目配置（自动加载、输入映射、主场景）
│
├── autoloads/                     # 全局单例
│   ├── event_bus.gd               # 跨场景信号总线
│   ├── game_state.gd              # 本局世界种子
│   └── scene_manager.tscn/.gd     # 场景切换（黑幕淡入淡出）
│
├── resources/
│   ├── world/                     # 世界数据层（不含任何节点，可跨线程使用）
│   │   ├── terrain.gd             # 16 种地形定义
│   │   ├── biome.gd               # 14 种生物群系定义
│   │   ├── route.gd               # 箱庭内道路定义（主路/支线/木桥）
│   │   ├── run_graph.gd           # 8 层 / 14 区域的主干与岔路关卡图
│   │   ├── map_spec.gd            # 箱庭尺寸、重叠庭室、山林边界与出入口
│   │   ├── chunk_data.gd          # 单个区块的地形 + 群系 + 路网字节数组
│   │   └── world_generator.gd     # 随机箱庭布局 + 群系 + 内部道路 + 区块生成
│   └── terrain_tileset.tres       # TileSet（2 个图集源：地形 + 路网）
│
├── scenes/
│   ├── menus/main_menu.tscn/.gd   # 主菜单
│   ├── world/chunk_manager.gd     # 区块加载器（异步生成 / 缓存 / 池化）
│   ├── game/
│   │   ├── game_world.tscn/.gd    # 游戏世界
│   │   └── player.tscn            # 主角（占位图 + 摄像机）
│   └── ui/
│       ├── hud.tscn/.gd           # HUD 与性能面板
│       └── minimap.gd             # 右上角小地图
│
├── scripts/player.gd              # 主角移动逻辑
│
├── assets/
│   ├── terrain_tiles.png          # 16x256 地形图集
│   ├── road_tiles.png             # 16x48 路网图集
│   └── player_placeholder.png     # 主角占位图
│
└── tools/generate_art.py          # 生成上面三张占位图的脚本
```

---

## 随机陆地箱庭与内部道路

[RunGraph](resources/world/run_graph.gd) 将一局组织为 **8 层、14 个区域**：首尾层各一个主干区域，中间六层各有主干和岔路。主干可以向下一层主干或岔路推进，岔路汇回下一层主干；区域之间以出入口连接，可以沿对应入口返回。

关卡骨架现在带**房间类型与节奏**：`RoomGraph` 在既有拓扑上标注起点 / 战斗 / 奖励 / 商店 / 休息 / 事件 / Boss，主路径按节奏模板分配，关键房间由配置强制校正；生成后再过一遍硬约束校验与软约束评分，不合格就在同一主种子下换布局变体重试。全部随机走统一的 `MapRng` 种子系统，同种子必然同图。架构、配置与调试命令见 [地图生成架构](docs/map_generation.md)。

[MapSpec](resources/world/map_spec.gd) 按种子分别随机箱庭宽高，通常各为 **112–224 格**。非初始区域使用宽阔原野、狭长山谷、林间空地、折返山径、阶梯台地和双庭丘陵六类轮廓，由随机重叠庭室组成主庭与可探索侧庭，并用内部道路连成可返回的回路。地图以陆地为主，少量池塘或河带点缀，外围由主题对应的山林围合。

**区域 0 是森林主题的「起始小屋」**，每局按种子生成 **20–24 × 16–18 格**的小屋与家具，玩家出生在房内中心。石地表示可走地板；木墙与家具使用不可通行地形，由 `CottageView` 绘制小屋外观。门位于右墙，门外右侧 3 格是屋前落点；室内仅保留出生点穿门到屋前的直线道路，其他出口与侧庭道路从屋前连接，避免道路穿透墙壁和家具。初始区域不生成水域，敌人内容预算为 0；离开后小屋隐藏，返回时重新显示。

**道路只存在于箱庭内部**，连接主庭、侧庭及出入口；主路用石板、支线用土路，跨水处显示木桥。路面与空地可通行，森林、针叶林、雨林会阻挡移动，小屋木墙与家具也保持阻挡。区域之间的间隙没有实体道路，角色不能步行穿越箱庭之间。

草地、土路、岩土、树林和水岸的接触边沿使用像素融合与圆角过渡，跨区块保持一致；箱庭出入口附近也会逐渐混入相邻区域的地面色调，同时保留每个箱庭的单一群系与通行规则。

地面按种子随机散落**石头和木棍**，每图约 20–70 个，分布疏松；小屋外优先放置两种材料。靠近后按 **E** 拾取，材料进入背包并可堆叠，已拾取点位在返回地图后不会补刷。按 **B** 打开炼金界面，从背包拖入材料：石头提供矿物属性，木棍提供木质属性，两者反应生成固结属性；固结目前是无直接使用效果的终产物属性。背包与快捷栏之间除了拖拽，还支持 **shift+左键** 整堆挪动：背包→快捷栏优先叠进已有的同种格子，没有同种就放第一个空格，快捷栏占满时整堆留在背包里；快捷栏→背包整格挪回。

触及出入口时，角色与画面**双向瞬切**到目标箱庭的对应入口，不播放跨区域行走或淡入淡出。汇流区域保留来自不同主干 / 岔路的多个入口，各入口对应自己的返回方向。相机以当前地图矩形设置硬 `limit`，切图时重置 `smoothing`，避免画面滑过区域间隙。

---

## 小地图与全屏探索地图

右上角 compact 小地图覆盖玩家周围 **512×512 格**，生成 **128×128 像素**底图（4 格 / 像素）。它使用独立生成器采样，也能显示未加载区域，并缓存采样像素；显示多个箱庭标签、当前区域标记与相机视野框。

| 设计 | 说明 |
|------|------|
| compact 数据来源 | 独立采样与像素缓存，不依赖已加载的 5×5 区块范围 |
| 全屏地图 | 按 M 铺满窗口，至少显示以玩家为中心的 15×7 区块，并包含更远的已探索区域 |
| 探索记录 | 保存当前可见箱庭已加载观察过的区块快照，区块离开缓存后仍可显示，生成新世界时清空 |
| 隐藏邻图 | 预加载的直连邻图不计入探索，compact 采样也不增加探索记录 |
| 共享边界 | 同一区块跨越多个箱庭时，仅按当前地图矩形裁剪并记录像素，其他箱庭访问后再补入 |
| 分辨率 | compact 为 4 格 / 像素；全屏快照为 1 格 / 像素，保留详细地形 |
| 配色 | 调色板从图集上现取，避免颜色表和图集两边各写一份而对不上 |
| 路线高亮 | 路面在地图上偏向暖黄，不管在什么群系上都一眼能看出路线 |
| 更新 | compact 按采样窗口变化重建并复用像素缓存，全屏按探索进度更新；角色、标签与相机框持续更新 |

---

## 箱庭区块加载

地形与内部道路由世界种子、地图布局和格子坐标共同决定，区块可独立生成。加载范围由当前箱庭及其直连邻图的完整矩形决定。

| 概念 | 取值 / 行为 |
|------|-------------|
| 格子 | 16 × 16 像素 |
| 区块 | 32 × 32 格 = 512 × 512 像素 |
| 可见地图 | 每张地图独立 root，仅当前地图 visible；铺格子按地图矩形进行 cell clip |
| 邻图预铺 | 所有直连邻图在隐藏 root 中后台预加载，包括可返回的入口邻图 |
| 首次进入 | 同步补齐当前相机视口，其余整图区块后台生成与铺图 |
| 每帧预算 | 默认最多提交 4 块生成、应用 4 块图层 |
| 数据缓存 | LRU 缓存上限 512 个区块，同种子跨地图复用 |
| 换种子安全 | 等待旧任务结束并推进 epoch，清空旧缓存，防止旧种子结果混入新世界 |

区块管理由 [chunk_manager.gd](scenes/world/chunk_manager.gd) 负责。后台生成使用 `WorkerThreadPool` 与独立生成器，主线程按预算铺图；`TileMapLayer` 池化复用，格子坐标保持在区块本地范围。共享边界区块的数据可以复用，但各地图图层分别裁剪，隐藏邻图不会出现在当前主视图。

### 地图测试覆盖

[tools/test_continuous_world.gd](tools/test_continuous_world.gd) 覆盖同种子一致性、四个种子共 56 个区域的六类轮廓与陆地比例、内部道路及屋内通路可通行性、8 次 BFS 连通检查、双向出入口和汇流返回、区域间隙阻挡，以及切图、相机、邻图预加载和缓存行为。小屋版本已通过 **69,457 个通路采样点**；56 个区域的采样水域约 **0–3.4%**、可通行比例约 **53.7–79.4%**。同种子、区域模板、地图硬校验（100/100）、内容、26 项箱庭状态保留、小地图模式和怪物四状态 AI 回归已在本机 Godot 4.6 通过。数据用于生成与兼容验证，不作为性能测量。

[tools/test_cottage_biomes.gd](tools/test_cottage_biomes.gd) 补充起始小屋和单群系验收：四个种子各两个布局变体的整张区域规格与区块确定性、完整区域矩形的群系身份、不同种子的小屋与群系分配多样性、墙壁和家具阻挡、屋门通路、12 张地图的四连通 BFS，以及运行时切图、相机和生命/装备/背包/炼金实例保留。脚本输出邻格地形变更率、地面/阻挡连通簇和单格阻挡碎片数量，便于评估大片地形；本轮已在 Godot 4.6 通过生成专项验收（约 314 万格、4,282 个区块）及 29 项带截图运行时检查，包含切图后释放怪物的感知队列清理；12 张地图出生连通块覆盖率为 99.85%–100%，地形邻格变更率约为 0.97%–2.75%。有图形界面时加 `-- --capture` 可保存 `.godot/cottage-preview.png` 与 `.godot/region-biome-preview.png`。

[地形过渡与材料验收](tools/test_transitions_materials.gd) 已在 Godot 4.6 通过：带截图 7,388 项检查、四个种子共 2,374 个材料点位，包含跨区块邻格、入口色调、确定性生成、实际 E 键拾取、返回不补刷、背包保留及投放区与坩埚反应。连续通路、26 项切图状态与小地图模式回归同时通过。

[协作者功能兼容验收](tools/test_inventory_material_compatibility.gd) 通过 235 项检查：保留原材料与配方，验证快捷栏整堆交换、同类分格、返还背包、shift+左键快捷移动、真实 GUI 拖拽的 E 键旋转和拾取隔离；四种子两变体的全部战斗/Boss 房均匹配现有怪物池，新增怪物群系自动纳入地图主题，独立采样与正式游戏一致。

```sh
godot --headless --path . --script res://tools/test_transitions_materials.gd
godot --headless --path . --script res://tools/test_inventory_material_compatibility.gd
godot --headless --path . --script res://tools/test_cottage_biomes.gd
godot --headless --path . --script res://tools/test_continuous_world.gd
godot --headless --path . --script res://tools/test_map_integration.gd
godot --headless --path . res://tests/test_minimap_modes.tscn
godot --headless --path . --script res://tests/test_weapons.gd
```

---

## 生物群系

保留 14 种群系与 16 种地形数据定义。**每张区域严格只有一个 `MapSpec.biome_id`**：其完整矩形内的所有格子，包括围合边缘、室内和池塘，`sample_biome()` 都返回这一群系。区域主题按世界种子打乱分配，初图固定为森林。正式游戏从现有怪物定义自动取可用群系，所有战斗与 Boss 区域都选择怪物池支持的主题；目前为稀树草原、草原、森林或热带雨林，并保留至少一个雨林战斗区域。其他房型保留多样主题，新增怪物配置后自动扩展战斗群系。下表说明数据定义中的主要地形对应关系；实际区域按主题配置可走地面、阻挡地形和边界。

| 群系 | 主要地形 | 群系 | 主要地形 |
|------|----------|------|----------|
| 深海 | 深水 | 沼泽 | 沼泽 |
| 海洋 | 浅水 / 浮冰 | 针叶林 | 针叶林 |
| 海岸 | 沙滩 | 苔原 | 苔原 |
| 沙漠 | 沙漠 | 雪原 | 雪原 |
| 稀树草原 | 稀树草原 | 山地 | 石地 / 山地 |
| 草原 | 草地 | 雪峰 | 雪峰 |
| 森林 | 森林 | 热带雨林 | 雨林 |

同一群系内部使用低空间频率噪声生成大簇同主题地面、连续森林与岩壁，减少高频点缀和单格碎片。地形的变化影响通行与外观，群系身份始终保持区域的固定值；池塘可以使用水地形，但不会把所在格子的群系改成海洋。

### 16 种地形

| 编号 | 地形 | 可通行 | 编号 | 地形 | 可通行 |
|------|------|--------|------|------|--------|
| 0 | 深水 | ❌ | 8 | 沼泽 | ✅ |
| 1 | 浅水 | ❌ | 9 | 稀树草原 | ✅ |
| 2 | 浮冰 | ✅ | 10 | 沙漠 | ✅ |
| 3 | 沙滩 | ✅ | 11 | 苔原 | ✅ |
| 4 | 草地 | ✅ | 12 | 石地 | ✅ |
| 5 | 森林 | ❌ | 13 | 山地 | ❌ |
| 6 | 针叶林 | ❌ | 14 | 雪原 | ✅ |
| 7 | 雨林 | ❌ | 15 | 雪峰 | ❌ |

地形编号同时就是图集里的行坐标，改顺序时必须同步改 [tools/generate_art.py](tools/generate_art.py) 的 `TERRAINS` 与 `ROADS` 列表。

---

## 主角移动

[scripts/player.gd](scripts/player.gd) 用 `move_toward` 做速度插值：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `max_speed` | 220 | 最大速度（像素/秒） |
| `acceleration` | 1400 | 按住方向键时每秒增加的速度 |
| `friction` | 1800 | 松开按键后每秒衰减的速度 |
| `collide_with_terrain` | true | 是否阻挡深水 / 浅水 / 森林 / 针叶林 / 雨林 / 山地 / 雪峰（道路格除外） |
| `max_health` | 10 | 新世界初始最大生命；切换箱庭保留当前生命 |
| `weapon_loadout` | 武器资源数组 | 按数组顺序循环装备，沿用现有武器参数与配置 |

按住方向键约 **0.16 秒**到达最大速度（每帧 +23.3），松开约 **0.12 秒**停下（每帧 −30）。位移按 X/Y 分轴推进，贴着海岸走不会卡住。

碰撞不查区块，而是直接问 `WorldGenerator` 这一格能不能站——生成函数是纯的，所以判定结果和画面永远一致，也不用等区块加载完。查询结果按格子缓存，一帧最多算两次。角色同时受当前箱庭矩形约束，道路和空地可走，不能越过山林边界或步行进入区域间隙。

切换箱庭不会回满血；只有重建新世界才恢复生命。训练靶保留在起始箱庭，离开后隐藏并暂停，返回时恢复，继续沿用原来的伤害、击退与重生行为。

---

## 操作

| 按键 | 功能 |
|------|------|
| W A S D / 方向键 | 移动主角 |
| 鼠标 / 左键 | 瞄准 / 挥剑，按住连续攻击 |
| Q | 循环切换长剑 / 长棍 |
| M | 展开全屏地图 / 返回右上角小地图 |
| R | 换个种子重开世界 |
| F3 | 开关右上角性能面板 |

左上角显示种子、格子与区块坐标、当前地形与群系、以及是否走在路上；右上角小地图保持常驻，按 M 可展开全屏地图查看自身位置与本局已探索区块。

---

## 快速开始

1. 用 **Godot 4.7+** 打开本目录（选择 `project.godot`）
2. 按 F5 运行，在主菜单点「开始游戏」
3. 或命令行运行：`godot --path .`

重新生成占位美术（可选，需要 Pillow）：

```
python tools/generate_art.py
```

`.godot/` 缓存、导出配置等已在 `.gitignore` 中忽略；`*.import` 与 `*.uid` 需要随资源一起提交。

---

## 林地怪物“给”

完整怪物架构、生成配置与扩展说明见 [docs/monsters.md](docs/monsters.md)。

箱庭切换使用通用 `MonsterSpawner`，按当前地图已加载区块生成怪物，在生成前排除邻图候选格，避免共享区块的生成名额被邻图占用；隐藏预加载邻图不会刷新可见怪物。HUD 显示房间类型，F3 面板显示本区域怪物数；森林/雨林主题的非战斗房间仍不刷怪。本局击杀按怪物类型与原始生成格记录，返回旧箱庭或重载区块时不会复活，也不会补刷替代怪物；只有新开世界才清空记录。怪物死亡掉落保存到所属箱庭，离开后隐藏并暂停，返回后恢复。

“给”只会随已加载区块生成在稀树草原、草原、森林、热带雨林群系的可通行格子中，同一种子与区块会得到稳定一致的随机位置。玩家进入 10 格范围后，怪物只有在视线无阻挡时才产生攻击意图：距离 6 至 10 格（包含两端）时拾取 1 格内的石子投掷，低于 6 格时弹跳到玩家面前并近战。手边没有石子时停止本次远程攻击，不会改用跳跃。两种攻击均造成 1 点伤害且攻击间隔均为 1 秒。“给”拥有 100 点生命，玩家每个新世界以 10 点生命开始。

击杀“给”必定在死亡位置掉落一件专属材料：70% 为给毛（ID 4），30% 为猴皮（ID 5），一次抽样二选一，不会空掉落或同时掉两件；普通伤害死亡和 K 击杀走同一流程，切图卸载不掉落。靠近后按 E 拾取进入现有背包。未拾取的掉落物按箱庭保存，返回时恢复；拾取后和怪物死亡记录一样不会补刷。两件材料不会加入自然散落材料生成池。

所有怪物应继承 `scripts/monsters/base_monster.gd`，AI 本体在 `scripts/monsters/ai/`：`EnemyBrain` 是通用四状态机（`Patrol` / `Chase` / `Attack` / `Search`），每只怪物各有一份黑板、感知、导航与攻击实现，共享 `EnemyAIConfig` 数据配置、`PerceptionManager` 与 `PathRequestScheduler` 两个自动加载服务以及 `EventBus`。丢失玩家视野超过 `lose_sight_grace` 后，怪物会把 `PatrolAnchor` 改写成自己当时所在的位置，并在原地附近继续巡逻，绝不回到出生点或原巡逻点，所以状态集合里没有 Return / GoHome / Flee。感知复用场景中的 `TargetRayCast`（`RayCast2D`）检测物理墙体，并逐格检查程序化地形的可通行性；寻路复用 `AStarGrid2D`，攻击由各怪物自己的 `EnemyAttack` 实现（“给”是 6~10 格投石、6 格内跳跃近战），正式地面石头（`GroundPickup`，ID 2）已实现投掷接口，仅取1格内可用石头；投石有飞行过程，命中扣1血，落地后仍可拾取，飞行期间不可再次取用。投石与跳跃都不能穿墙。子类通过 `has_player_aggro()` 查询是否处于 Chase / Attack，通过 `clear_player_aggro()` 立刻放弃目标并以当前位置为锚点回到巡逻。“给”只限制生成位置属于稀树草原、草原、森林或热带雨林群系，生成后可以追逐玩家进入其他群系。

通用生成器位于 `scripts/monsters/monster_spawner.gd`，生成配置类型位于 `monster_spawn_data.gd`。新增怪物时右键 `scenes/monsters/base_monster.tscn` 创建继承场景，再新建一份 `MonsterSpawnData` 资源并加入 `GameWorld/MonsterSpawner` 的 `spawn_definitions` 数组即可。生成器通过公开的 `monsters: Array[BaseMonster]` 保存存活怪物，怪物死亡时自动移除引用，并在区块卸载或更换世界时遍历释放。`resources/monsters/give_spawn_data.tres` 是“给”的首份配置示例。

统一道具基础层来自 `inventory` 分支：`scripts/items/item_data.gd`、`scripts/items/ingredients/ingredient_data.gd`、`ingredients_model.gd` 以及炼金/物理属性基类保持原路径和原 UID，供背包、合成和世界物品共同使用。

当前地图尚无正式石子，上传版本不生成临时石子，因此“给”在远程范围内找不到石子时会停止本次攻击。地图团队接入正式石子时，应继续使用同一套 `IngredientData` / `IngredientModel`，加入 `throwable_stones` 组并实现 `throw_at(target, damage)` 方法；怪物代码不依赖具体石子类型。

“给”的动作由场景内 `AnimationPlayer` 和 `AnimationTree` 管理，状态包括 `Idle`、`Move`、`Leap`、`Throw`、`Hurt`、`Death`。在编辑器打开 `scenes/monsters/give_monster.tscn`，选中 `AnimationTree` 可查看状态图，选中 `AnimationPlayer` 可编辑占位动作轨道。动画库为 `resources/monsters/give_animation_library.tres`，状态图为 `resources/monsters/monster_animation_state_machine.tres`；脚本通过通用模板的 `play_monster_animation()` 切换状态。投石和受击完成后自动返回待机，跳跃高度由动画轨道驱动，落点位移与伤害仍由物理逻辑处理。状态图只保留12条转换，以 `Idle` 为中心连接移动与动作；受击和死亡由脚本直接打断。`Death` 没有任何出边，脚本禁止从死亡切回其他状态。死亡状态会立即进入，当前击杀仍直接清理节点，不等待死亡动画播完。

通用模板默认提供受击击退和全身闪红。击退强度按加算叠加：`武器击退强度 + 模板基础击退速度`，方向沿用 `CombatHit.knockback` 的方向，不使用强度乘算。例如武器180、模板40，最终强度为220像素/秒；没有武器击退向量时按攻击来源位置确定方向，仅使用模板基础强度。模板基础速度默认40像素/秒，击退持续0.10秒并逐渐减速，基础位移约2像素；强度180的武器叠加后位移约11像素。`Hurt` 动作在0.10秒内快速左右抖动，初始幅度4像素，再逐渐归零，强化短促冲击感。全身鲜红闪烁持续0.06秒。连续受击会重置反馈时间，材质参数在每只怪物之间独立。击退通过身体碰撞与地形检查阻挡，不会穿过墙体；受击会打断跳跃，进入 `Hurt` 并归零视觉高度。可在根节点“受击反馈”分组调整参数。

外形统一放在 `Visual`（`CanvasGroup`）下面，闪红会作用于全部身体部件、眼睛和轮廓，名字与血条保持原色。“给”的占位绘制位于 `give_monster_visual.gd`。自定义 `_physics_process(delta)` 时先调用 `super._physics_process(delta)`，再在 `is_receiving_knockback()` 为真时跳过自己的移动与攻击，避免覆盖击退位移。

新增怪物的场景流程：

1. 在 Godot 文件系统中右键 `scenes/monsters/base_monster.tscn`，选择“新建继承场景”，保存为新的怪物场景。“给”已经按此方式继承。
2. 修改 `NameLabel.text`、`Health.max_health` 和碰撞形状；在 `Visual` 下隐藏 `Placeholder` 并添加自己的精灵。名字、血条、索敌射线、受击组件、动画节点与信号连接均自动继承。
3. 在 `AnimationPlayer` 的 Libraries 中为新怪物创建或复制独立动画库，保持 `Idle`、`Move`、`Attack`、`Hurt`、`Death` 这些状态对应的动画名；需要特殊技能时可使用 `Leap`、`Throw`。若要修改状态图，先将 `AnimationTree.tree_root` 设为独立资源，避免修改公共状态图影响其他怪物。
4. 为根节点绑定 `extends BaseMonster` 的专属脚本，并指定一份 `EnemyAIConfig`（`resources/monsters/give_ai_config.tres` 是示例）：巡逻半径、视野、攻击距离、搜索时长、LOD 等全部走配置，不需要复制 AI 代码；只有新的攻击方式才需要覆写 `_create_attack()` 返回自己的 `EnemyAttack`。覆盖 `_ready()` 或 `_physics_process(delta)` 时调用对应 `super` 方法。模板已提供生成器初始化、动画推进、寻路动作切换、血条更新与受击/死亡动画连接，无需重复编写。动画库默认使用 `base_animation_library.tres` 的占位动作。
5. 创建 `MonsterSpawnData` 资源，指定新场景和生成群系，再加入生成器的 `spawn_definitions` 数组。

回归测试：

```
godot --headless --path . res://tests/test_monster_hit_effects.tscn
godot --path . res://tests/test_hit_flash_render.tscn --rendering-method gl_compatibility
godot --headless --path . res://tests/test_monster_animations.tscn
godot --headless --path . res://tests/test_monster_persistence.tscn
godot --headless --path . --script res://tools/test_give_loot.gd
godot --headless --path . res://tests/test_monster_active_map.tscn
godot --headless --path . --script res://tools/test_monster_region_entry.gd
godot --headless --path . --script res://tools/test_give_ground_stone.gd
godot --headless --path . res://tests/test_enemy_ai.tscn
godot --headless --path . res://tests/test_give_monster.tscn
godot --headless --path . res://tests/test_rainforest_spawner.tscn
```

---

## 已知限制

- **地形碰撞用代码判定**，没有走 TileSet 物理层；两者视觉上等价，但物理层能直接配合 `move_and_slide`。
- **关卡内容待完善**：已有 8 层箱庭关卡图与出入口推进，但战斗 / 事件 / 宝箱 / 商店 / Boss 等内容尚未按关卡节点完整配置。

## 后续可做

- [ ] **为箱庭关卡配置肉鸽内容**（战斗 / 精英 / 宝箱 / 商店 / 营地 / Boss）
- [ ] 小地图上标出事件节点与已访问状态
- [ ] 一局的目标与推进：起始箱庭 → 主干 / 岔路 → 最终 Boss，抵达即结算
- [ ] 摄像机自由缩放 / 拖动
- [ ] 用正式角色美术替换 [player_placeholder.png](assets/player_placeholder.png)
