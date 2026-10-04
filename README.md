# Project YongXian

使用 **Godot 4.7** 开发的 2D 游戏项目。目前包含主菜单、随机地图生成，以及一个可用 WASD 控制、带加速度的占位主角。

---

## 目录结构

```
Project_YongXian/
├── project.godot                 # 项目配置（自动加载、输入映射、主场景）
│
├── autoloads/                    # 全局单例
│   ├── event_bus.gd              # 跨场景信号总线
│   ├── game_state.gd             # 本局状态（地图种子、尺寸）
│   └── scene_manager.tscn/.gd    # 场景切换（黑幕淡入淡出）
│
├── resources/
│   ├── data/
│   │   ├── map_data.gd           # 地图数据 Resource（地形格子、出生点）
│   │   └── map_generator.gd      # 随机地图生成器
│   └── terrain_tileset.tres      # 地形 TileSet（竖排 6 格图集）
│
├── scenes/
│   ├── menus/main_menu.tscn/.gd  # 主菜单
│   ├── game/
│   │   ├── game_world.tscn/.gd   # 游戏世界（生成并铺地图、放主角）
│   │   └── player.tscn           # 主角（占位图 + 摄像机）
│   └── ui/hud.tscn/.gd           # 游戏内 HUD
│
├── scripts/player.gd             # 主角移动逻辑
│
├── assets/                       # 美术资源
│   ├── terrain_tiles.png         # 16x96 地形图集
│   └── player_placeholder.png    # 主角占位图
│
└── tools/generate_art.py         # 生成上面两张占位图的脚本
```

---

## 系统说明

### 自动加载层级

| 单例 | 职责 |
|------|------|
| `EventBus` | 全局信号总线（`map_ready` / `notification`），避免场景之间互相持有引用 |
| `GameState` | 本局地图种子与尺寸，跨场景保留 |
| `SceneManager` | 统一场景切换，附带淡入淡出 |

场景流转：`main_menu` → 点「开始游戏」→ `GameState.start_new_game()` 定下种子 → 淡出 → `game_world` 用该种子生成地图。

### 随机地图生成

`MapGenerator.generate(width, height, seed_value)` 全部是静态方法，传 `0` 表示随机取种。流程：

1. **噪声地形** —— 地势与湿度各用一套 `FastNoiseLite` 单纯形噪声，两两组合决定地形
2. **岛屿衰减** —— 越靠地图边缘地势越低，四周自然沉入水里，形成一块完整大陆
3. **河流** —— 从随机边缘向对侧开凿，带随机摆动与偶发加宽
4. **平滑** —— 多数投票抹掉噪声产生的孤立单格
5. **出生区** —— 地图中心清出一块平地，再由中心螺旋搜索最近的可行走格子

地形编号同时就是图集里的行坐标：

| 编号 | 地形 | 可通行 |
|------|------|--------|
| 0 | 草地 | ✅ |
| 1 | 水域 | ❌ |
| 2 | 山地 | ❌ |
| 3 | 森林 | ✅ |
| 4 | 沙滩 | ✅ |
| 5 | 雪地 | ❌ |

实测占比（64×64、5 个种子平均）：草地 34.9%、森林 25.3%、水域 23.9%、沙滩 7.1%、山地 7.0%、雪地 1.8%，可通行约 67%。

### 主角移动

`scripts/player.gd` 用 `move_toward` 做速度插值，所以起步和收手都是渐变的：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `max_speed` | 220 | 最大速度（像素/秒） |
| `acceleration` | 1400 | 按住方向键时每秒增加的速度 |
| `friction` | 1800 | 松开按键后每秒衰减的速度 |
| `collide_with_terrain` | true | 是否阻挡水域 / 山地 / 雪地 |

按实测：按住方向键约 **0.16 秒**到达最大速度（每帧 +23.3），松开约 **0.12 秒**停下（每帧 −30）。位移按 X/Y 分轴推进，贴着水岸走不会卡住。

---

## 操作

| 按键 | 功能 |
|------|------|
| W A S D / 方向键 | 移动主角 |
| R | 换一个种子重新生成地图 |
| 鼠标 | 主菜单里点按钮 |

---

## 快速开始

1. 用 **Godot 4.7+** 打开本目录（选择 `project.godot`）
2. 按 F5 运行，在主菜单点「开始游戏」
3. 或命令行运行：`godot --path .`

想重新生成占位美术（可选，需要 Pillow）：

```
python tools/generate_art.py
```

`.godot/` 缓存、导出配置等已在 `.gitignore` 中忽略；`*.import` 与 `*.uid` 需要随资源一起提交。

---

## 后续可做

- [ ] 地形碰撞改用 TileSet 物理层，替代 `player.gd` 里手写的格子判定
- [ ] 地块连通性检查，避免出生点周围被水隔断
- [ ] 摄像机自由缩放 / 拖动
- [ ] 设置界面、存档读档
- [ ] 用正式角色美术替换 [player_placeholder.png](assets/player_placeholder.png)
