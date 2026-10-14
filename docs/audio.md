# 音效与音乐

音频走一条**数据驱动 + 单一入口**的链路：素材按 id 命名放进目录，参数写在配置表里，代码只在事件发生的地方调一次 `AudioManager.play_sfx()`。换正式素材时覆盖同名文件即可，不需要改脚本。

当前素材是**程序化生成的占位音频**（`tools/generate_sfx.py`），用来先把播放链路跑通；音色本身是临时的。

---

## 1. 模块拆分

```
autoloads/
└── audio_manager.gd          # 自动加载单例 AudioManager：素材扫描 / 播放器池 / 总线音量 / 音乐切换

resources/audio/
└── sfx_spec.gd               # 音效参数表 SfxSpec：音量、音高抖动、最小间隔、同时发声上限、总线

assets/audio/
├── sfx/*.wav                 # 40 个音效，44.1kHz 单声道；文件名 = 音效 id
└── music/*.wav               # 2 段循环音乐，22.05kHz 单声道

default_bus_layout.tres       # 总线布局：Master → Music / SFX / UI

tools/generate_sfx.py         # 重新生成上面全部占位素材（python tools/generate_sfx.py）
tests/test_audio.gd           # 音频系统单元测试
```

---

## 2. 总线布局

```
Master
├── Music   # 背景音乐
├── SFX     # 世界音效（战斗、材料、炼金）
└── UI      # 界面音效
```

四条总线都在 `default_bus_layout.tres` 里，默认 0 dB。音效自身的响度由 `SfxSpec` 的 `volume_db` 决定，总线只负责整体分组调节。

---

## 3. 素材与 id 约定

**文件名（去掉扩展名）就是音效 id。** `assets/audio/sfx/hit_flesh.wav` → id `&"hit_flesh"`。

`AudioManager` 启动时扫描这两个目录，所以：

- 新增音效 = 放文件 + 在 `SfxSpec` 里补一行参数。不补也能响（走默认参数），但会少了针对性调音。
- 删除音效 = 删文件。代码里的调用会因为找不到素材而安静跳过，不会报错。
- 缺素材不崩：`play_sfx()` 找不到 id 时直接返回。

命名分组：

| 前缀 | 用途 |
| --- | --- |
| `swing_*` | 挥砍，按武器 id 命名（`swing_longsword`），缺专属素材时退回 `swing_generic` |
| `inspiration_*` / `sage_stone` | 灵感系统与贤者之石结算的提示音 |
| `hit_*` | 命中，按受击材质区分（`hit_flesh` / `hit_wood` / `hit_stone` / `hit_critical`） |
| `monster_*` / `player_*` | 怪物与主角的受伤、死亡 |
| `brew_*` / `heat_*` / `wheel_*` | 炼金：激活、叠加、爆发、过期、拒绝、过载、热量预警、轮盘 |
| `ui_*` | 界面点击、悬停、返回、开关 |
| `pickup_*` / `absorb_*` | 材料拾取与注入素材槽 |
| `world_*` / `gate_*` / `stone_*` | 世界就绪、箱庭切换、投石 |
| `music_*` | 音乐 |

---

## 4. 参数表（SfxSpec）

`resources/audio/sfx_spec.gd` 是音效调音的唯一真源。表里只写需要偏离默认值的项，其余走 `DEFAULT`。

| 参数 | 含义 |
| --- | --- |
| `volume_db` | 相对总线的衰减，越小越轻 |
| `pitch_variation` | 每次播放的音高抖动幅度（±比例），避免连播听感发木 |
| `min_interval` | 两次播放的最小间隔（秒），压制连击刷屏 |
| `max_voices` | 同时允许的发声数，超出直接丢弃本次播放 |
| `bus` | `&"SFX"` 或 `&"UI"` |

三档限流是刻意分层的：挥砍靠 `pitch_variation` 求变化，命中靠 `min_interval` 求干脆，过载 / 死亡这类一次性演出用 `max_voices = 1` 保证不被叠掉。

---

## 5. 代码里的挂载点

音效都挂在**已有的信号或事件**上，没有为了音效新增游戏逻辑：

| 位置 | 音效 |
| --- | --- |
| `weapon_controller.try_attack()` | 按武器 id 选挥砍声，2D 定位在角色身上 |
| `base_monster._on_monster_damaged()` | 命中音（按暴击分支）+ 怪物受伤 |
| `base_monster._on_monster_died()` | 怪物死亡（调试用的全灭指令不出声） |
| `training_dummy._on_damaged()` | 木桩命中音，验证材质区分 |
| `player.take_damage()` | 主角受伤 / 生命归零 |
| `ground_pickup.collect()` / `throw_at()` / `_finish_throw()` | 拾取、投石出手、石头落地 |
| `alchemy_station._connect_audio()` | 激活 / 叠加 / 替换爆发 / 过期 / 拒绝 / 过载 / 轮盘 / 热量预警 / 打开面板 |
| `alchemy_station.set_slot()` / `fill_first_free_slot()` | 材料注入素材槽 |
| `main_menu` / `hud` | 按钮点击、地图与性能面板开关 |
| `game_world.build_world()` / 出入口推进 | 探索音乐、箱庭切换音 |
| `EventBus.world_ready`（AudioManager 内部订阅） | 世界就绪 |

炼金那一组全部写在 `_connect_audio()` 里，和 `_connect_signals()` 并列，方便一眼看清"哪些事件有声音"。

---

## 6. 播放与音量 API

```gdscript
# 非定位音效（界面、玩家自身动作）
AudioManager.play_sfx(&"brew_activate")

# 2D 定位音效：按距离衰减，衰减参数见 SPATIAL_MAX_DISTANCE / SPATIAL_ATTENUATION
AudioManager.play_sfx(&"hit_flesh", hit.position)

# 音乐：同一首正在播放时不会重播；切换自动交叉淡入淡出
AudioManager.play_music(&"music_wilds")
AudioManager.stop_music()

# 音量（0~1 线性）与静音，都会写进 user://audio_settings.cfg
AudioManager.set_bus_volume(&"Music", 0.6)
AudioManager.toggle_muted()
```

> 战斗与炼金脚本内部用的是本地 `_play_sfx()` 包装：它在运行期查找 `/root/AudioManager` 再转调，这样脚本仍能作为 `--script` 单元测试的编译依赖被加载。行为与直接调用完全一致，找不到管理器时安静跳过。

播放器池：SFX 16 个、2D 定位 12 个、UI 6 个、音乐 2 个。池子满了会**抢最早的一个**，而不是丢弃新声音，保证突发战斗不会突然静音。

音乐循环不依赖导入选项：`play_music()` 发现 WAV 没开循环时会按 `get_length()` 自动补上 `loop_mode` 与 `loop_end`，所以直接丢一个普通 wav 进去也能循环。

---

## 7. 占位素材的合成要点（踩过的坑）

`tools/generate_sfx.py` 生成后会自动自检，下面三条是已经踩过并修掉的：

1. **波形必须显式给出长度。** `sine(freq, rate, n)` 的 `n` 不能省：`np.cumsum` 对标量频率只返回 1 个元素，波形会退化成常量，也就是"直流 + 包络"——听起来是隆隆声而不是乐音。这是音乐"只有持续噪音"的根因，也让 16 个音效带上 0.15~0.36 的直流偏移。
2. **直流偏移要主动阻断。** 衰减正弦的首个正半周占主导，短促音效尤其明显。`write_wav()` 统一过一遍 25 Hz 二阶高通；更短的素材（如 140 ms 的轻叮）在 `build_*` 里用更高的截止频率再压一次。
3. **音乐不要加常驻噪声床。** 用低通白噪声做"空气感"会让整轨永远不安静，听感就是持续的沙沙底噪。需要风声时应做成会回到静音的阵风。

自检会在生成结束后打印问题并以非 0 退出码结束：直流偏移 > 0.005、音乐最安静处频谱平坦度 > 0.15、音乐动态范围 < 8 dB 都算失败。

---

## 8. 换成正式素材

1. 把文件按同名放进 `assets/audio/sfx/`（或 `music/`），保持文件名不变即可直接生效。
2. 新增音效：放文件 → 在 `SfxSpec.SPECS` 补一行 → 在事件处调一次 `play_sfx()`。
3. 音效建议 44.1kHz 单声道、峰值留 3 dB 余量；音乐建议先自己做好无缝循环，导入设置里勾上循环。
4. 重新生成全部占位素材：`python tools/generate_sfx.py`（需要 numpy）。

---

## 9. 测试

```
godot --headless --path . --script res://tests/test_audio.gd
```

覆盖：总线布局、参数表默认值与总线归属、**参数表与素材文件双向一致**（登记的音效都有文件、文件都登记过）、素材加载、**导入设置**（音效与音乐都必须是无压缩 PCM，音乐必须标记循环）、最小间隔与发声上限、线性音量与分贝换算、静音、音乐切换、缺失素材的静默降级。

> 素材没被编辑器导入过时（新克隆的仓库），依赖素材的断言会跳过并给出提示——先在 Godot 里打开一次工程再跑测试。