# 局内成长系统（Roguelike 升级）

一局游戏内独立的成长线：**击杀怪物**与**炼金装瓶**都给经验，攒满经验就升级，每升一级弹出一次**三选一**加成卡。所有加成**只在本局生效**，开新局（`GameState.start_new_world()`）时由 `RunProgress.reset()` 全部清零。

灵感系统与贤者之石都不参与这条线，两者互不影响。

## 经验与等级曲线

```text
升到下一级所需经验 = 8 + 4 × (当前等级 - 1)
```

1 级升 2 级要 8 点，2 级升 3 级要 12 点，依次递增；一局大约能升 11–12 级。经验超出当前门槛时会**连续结算多级**，每一级都排队一次三选一，面板会一张接一张地弹。

经验来源：

| 来源 | 结算 | 数值 |
| --- | --- | --- |
| 击杀怪物（主要） | `RunProgress.kill_experience()` | 怪物基础经验 × (1 + 0.12 × 楼层)，再乘“击杀经验”加成 |
| 炼金装瓶 | `RunProgress.alchemy_experience()` | 基础 6 点；本局首次合成该配方 +12；产物含 2 级以上属性 +8；再乘“炼金经验”加成 |

怪物基础经验写在 `resources/monsters/*_spawn_data.tres` 的 `experience_reward`（给 = 10，史 = 6，鳄 = 14），由 `MonsterSpawner` 在生成时写进怪物实例。

### 经验球

击杀后在怪物位置生成一颗经验球（`ExperienceOrb`），行为分两段：

1. **停顿 0.45 秒**，原地轻微起伏，不结算经验。停顿是有意为之：让玩家看清“这里死了东西”，也避免怪物贴脸时经验瞬间消失。
2. 停顿结束后**直接朝玩家加速飞入**（加速度 900，上限 620 像素/秒），接触即结算经验并消失。

玩家不在场（切图、死亡）时球会原地等待，等玩家回来再飞。球挂在 `MonsterSpawner` 下，和怪物、掉落同一个父节点，所以切图清理怪物时不会跨区域堆积。

## 三选一规则

- 每次升级从卡池抽 **3 张互不重复**的卡。
- 稀有度权重 60 / 30 / 10（普通 / 精良 / 稀有）。**连续 2 次没抽到稀有**后，下一次抽卡的第一张**必为稀有**（保底）。
- **没有重抽**：只能从这三张里选一张，选定即消耗这次待选。
- 每张卡有层数上限，达到上限后**不再出现在卡池里**。
- **武器卡只出当前装备的武器**：`UpgradeCard.weapon_id` 与玩家手上武器的 `id` 不符时直接不进候选池。
- **代价卡有生命门槛**：只有当前生命比例不低于 70% 时才会出现，避免濒死时被迫吃下自残卡。

## 加成生效链路

每张卡只描述“效果键 → 每层数值”，数值由 `RunProgress` 聚合，再由各系统主动读取。下表是每个效果键真正落到哪里：

| 效果键 | 读取点 |
| --- | --- |
| `max_health_add` | `PlayerCharacter.max_health` → `HealthComponent.max_health` |
| `defense_add` | `PlayerCharacter.defense` → `HealthComponent.defense`（固定减伤） |
| `damage_taken_mult` | `PlayerCharacter._incoming_damage()`（先乘倍率，再扣固定减伤） |
| `low_health_reduction` | `PlayerCharacter._incoming_damage()`（生命低于 30% 时再乘一次） |
| `move_speed_mult` | `PlayerCharacter._move_speed()` |
| `pickup_radius_add` | `PlayerCharacter.pickup_radius_tiles()` → `GameWorld._refresh_pickup()` |
| `damage_mult` | `PlayerCharacter.outgoing_damage_multiplier()` → `WeaponAttack._land_hit()` 与 `OrbitBall._deal_damage()` |
| `event_chance_mult` | `RunProgress.event_chance()` 统一缩放武器特效、暴击和炼金回响；武器概率通过 `build_weapon()` 写入副本 |
| `crit_chance_add` / `crit_multiplier_add` | `RunProgress.build_weapon()` 写进武器副本 |
| `knockback_mult` | `RunProgress.build_weapon()` |
| `attack_speed_mult` | `RunProgress.build_weapon()`：前摇 / 后摇 / 复用间隔一起除以倍率 |
| `combo_damage_per_stack` | `PlayerCharacter.register_hit()` 记层数，`outgoing_damage_multiplier()` 生效 |
| `lifesteal_on_kill` | `PlayerCharacter.on_monster_killed()`（由 `MonsterSpawner._award_kill()` 调用） |
| `chain_damage_mult` | `PlayerCharacter.on_monster_killed()` → `_chain_damage()` → `BaseMonster.apply_chain_damage()` |
| `loot_bonus` | `BaseMonster._drop_death_loot()` |
| `regen_per_second` | `PlayerCharacter._tick_progress()`（脱战 4 秒后开始） |
| `alchemy_power_mult` / `heal_mult` | `PlayerCharacter.heal()` 与药水效果 |
| `potion_range_mult` | `PotionData.right_use()` → `PlayerCharacter.potion_range_mult()` |
| `alchemy_echo_chance` | `Cauldon._grant_alchemy_rewards()` |
| `alchemy_exp_mult` | `RunProgress.alchemy_experience()` |
| `kill_exp_mult` | `RunProgress.kill_experience()` |
| `no_potion` | `PlayerCharacter.potions_blocked()` → `PotionData.left_use()` |

### 通用概率加成

“幸运”为通用普通卡，任何武器都能抽到。每层贡献 `event_chance_mult = 0.20`，层数相加，统一公式为 `clamp(基础概率 × (1 + 总加成), 0, 1)`。例如雷鸣 10% → 单层 12% → 五层 20%，蜂巢 15% → 18% → 30%。暴击先叠“锐眼”的百分点加成，再应用幸运；炼金回响必须先取得相应卡，基础概率为零时仍为零。

新增有利概率事件应调用 `RunProgress.event_chance(base_chance)`；武器特效读取已经由 `build_weapon()` 加成的 `WeaponDefinition.proc_chance`，不要再次加成。地图生成、怪物刷新等世界随机事件不受影响，蜂群冷却和数量限制也不变。开新局随 `cards_taken` 清空，当前攻击保持启动时的数值快照。

### 武器卡

武器卡**只作用在它所属的武器上**。`UpgradePool.weapon_card_stacks()` 会先按 `weapon_id` 过滤一遍，所以拿过溜溜球“环绕球”之后再换回长剑，长剑不会凭空长出环绕球。

改造统一走 `RunProgress.build_weapon()`：先 `duplicate(true)` 出一份武器副本，再叠暴击、击退与武器卡。**必须在副本上改**——直接改会写回 `.tres` 并跨局残留。改完由 `WeaponController.equip()` 校验，校验不过会退回基础武器（`PlayerCharacter.rebuild_weapon()`），避免“卡看起来生效其实没换装”。

### 已修掉的“卡看起来生效其实没有”的坑

这些地方原本会静默失效，现在都补上了：

| 坑 | 原因 | 处理 |
| --- | --- | --- |
| 长枪拿到溜溜球的环绕球 | 武器卡按 id 抽取，但叠加时不按 id 过滤，换武器后改造残留 | `weapon_card_stacks()` 先按 `weapon_id` 过滤再叠 |
| 迅捷对连刺无效 | 连刺把 `active_seconds` 写成绝对值，可能覆盖攻速除法 | 时间轴统一在 `apply_weapon_cards()` 里结算：先叠卡的绝对值，再整体除攻速 |
| 长绳 + 迅捷 组合出非法溜溜球 | 后摇被攻速除短后低于回收时间，校验不过 → 静默保留旧武器 | 回收时间不受攻速影响，`recovery >= return_seconds()` 的比较放在攻速之后 |
| 经验球跨区域堆积 | 经验球挂在 `GameWorld` 上，切图清理怪物时球留下来 | 改挂在 `MonsterSpawner` 下，和怪物、掉落同一个父节点 |

回归测试里对每一条都有对应断言（`tests/test_run_progression.gd` 会真的调 `WeaponController.equip()` 确认装得上，而不是只看数值）。

## 加成卡总表

共 40 张。层数上限列在卡名后的括号里。

### 普通（10 张）

| 卡 | 效果 | 上限 |
| --- | --- | --- |
| 体质 | 生命上限 +15 | 4 |
| 坚韧 | 受到伤害 -6% | 3 |
| 疾行 | 移动速度 +8% | 4 |
| 利刃 | 全武器伤害 +12% | 5 |
| 锐眼 | 暴击率 +3% | 5 |
| 幸运 | 已有武器特效、暴击与炼金回响概率相对提高 20% | 5 |
| 致命 | 暴击伤害 +0.3 倍 | 4 |
| 巨力 | 击退 +25% | 3 |
| 迅捷 | 攻击速度 +8% | 4 |
| 拾荒 | 拾取范围 +1 格 | 3 |

### 精良（5 张，炼金向）

| 卡 | 效果 | 上限 |
| --- | --- | --- |
| 药材学 | 药水效果强度 +25% | 3 |
| 投掷精通 | 药水投掷距离 +40% | 2 |
| 炼金回响 | 装瓶 20% 概率额外产出一瓶 | 2 |
| 材料学 | 炼金经验 +50% | 3 |
| 以血换知 | 治疗量 -30%，击杀经验 +25% | 1 |

### 稀有（25 张）

武器卡（15 张，只在握着对应武器时出现）：

新增 5 张溜溜球终极改造：雷鸣的“天罚契约 / 雷暴核心 / 风暴信标”和蜂巢的“蜂巢炸弹 / 迁徙蜂群”。每张最多 1 层，同武器共享 `exclusive_group`，每局只能选其中一种，两把武器各自独立。候选池与 `RunProgress.take_card()` 均校验互斥，旧选项不能绕过；新局重置。具体行为及代价见 [武器终极改造](weapons.md#溜溜球终极改造)。

| 卡 | 武器 | 效果 |
| --- | --- | --- |
| 裂风 | 长剑 | 横扫范围 +60 度，伤害 -15% |
| 重斩 | 长剑 | 伤害 +50%，前摇 +0.12 秒 |
| 回旋 | 长剑 | 命中后立刻缩短后摇，可以接下一刀 |
| 剑压 | 长剑 | 击退翻倍，命中时自身朝准心前冲 1 格 |
| 长驱 | 长枪 | 枪长与突刺距离 +35%，保持窄幅直刺 |
| 重刺 | 长枪 | 突刺伤害 +40%，前摇 +0.10 秒 |
| 连刺 | 长枪 | 沿出手方向连刺两次，每刺伤害 -20%，刺击阶段变为 0.30 秒 |
| 钉足 | 长枪 | 命中使敌人减速 40%，持续 1.5 秒 |
| 长绳 | 溜溜球 | 绳长 +60%（后摇自动跟着覆盖回收时间） |
| 环绕球 | 溜溜球 | **按住左键攻击期间**额外一颗球绕角色快速旋转 |

机制卡（7 张）：

| 卡 | 效果 | 上限 |
| --- | --- | --- |
| 嗜血 | 击杀回复 5 点生命 | 3 |
| 连锁 | 击杀对 2 格内敌人造成 50% 武器伤害 | 2 |
| 贪婪 | 材料掉落 +1 | 2 |
| 节奏 | 连续命中同一目标每层 +10% 伤害（最多 5 层） | 2 |
| 铁皮 | 固定减伤 +4 | 3 |
| 濒死 | 生命低于 30% 时受到伤害 -40% | 1 |
| 再生 | 脱战 4 秒后每秒回复 1 点生命 | 3 |

代价卡（3 张，需要当前生命 ≥ 70%）：

| 卡 | 效果 | 上限 |
| --- | --- | --- |
| 孤注 | 生命上限 -25，全武器伤害 +40% | 1 |
| 薄刃 | 伤害 +35%，受到伤害 +50% | 1 |
| 苦行 | 无法使用药水，全武器伤害 +45% | 1 |

### 长枪“连刺”与溜溜球“环绕球”

- **连刺**把每次出手改为沿同一方向连续两刺：`thrust_count = 2`、`active_seconds = 0.30`，每刺伤害降低 20%。每刺独立记录命中；多受击框不会重复扣血，低帧率跨过整段时也能命中两次。前摇、收枪、后摇无伤害，通用攻速缩短整个时间轴。长枪不再提供整圈横扫或反向挥击改造。
- **环绕球**（`OrbitBall`）挂在攻击实例下面，半径 40 像素、每 0.4 秒对同一目标结算一次、伤害为主武器的 60%。它是攻击实例的子节点，所以**只在按住左键、溜溜球还在外面时存在**，松手或攻击结束随父节点一起释放。它按武器类型生效，只有溜溜球会得到它。

## 生命刻度统一

以前玩家 10 点生命、怪物 100 点生命，两边刻度不同，百分比加成和固定值加成没法共用一套卡。现在统一成：

- 玩家生命上限 **100**（`PlayerCharacter.base_max_health`），走通用 `HealthComponent`，与怪物同一套组件。
- 怪物伤害 **×10**：鳄鱼咬 2 → 20、给怪攻击 1 → 10、史怪攻击 3.0 → 30.0、史怪粘液弹 0.5 → 5.0。

这样“生命上限 +15”“固定减伤 +4”“受到伤害 -6%”在一局里都有可感知的分量，也让“生命上限”类卡有存在意义。

## 文件与职责

| 文件 | 职责 |
| --- | --- |
| `scripts/progression/upgrade_card.gd` | 一张卡的数据：稀有度、范围、层数上限、效果键表 |
| `scripts/progression/upgrade_pool.gd` | 34 张卡的表、三选一抽取规则、效果聚合与武器改造应用 |
| `scripts/progression/run_progress.gd` | 自动加载单例：等级 / 经验 / 待选次数 / 已选卡 / 配方记录，以及武器重建 |
| `scripts/pickups/experience_orb.gd` | 经验球：停顿后飞向玩家 |
| `scripts/ui/upgrade/upgrade_panel.gd` | 三选一面板（程序化 UI，暂停游戏） |
| `scripts/ui/upgrade/upgrade_manager.gd` | 中介：监听升级事件、驱动面板、把选卡结果落到玩家 |
| `scenes/ui/upgrade/upgrade_panel.tscn` | 面板场景（一个 Control 根节点） |
| `scripts/weapons/orbit_ball.gd` | “环绕球”的攻击实例子节点 |

`RunProgress` 在 `project.godot` 里注册为自动加载；面板与中介挂在 `scenes/game/game_world.tscn` 的 `GameHUD` 下。HUD 左下角显示等级与经验条。

## 测试

```text
godot --headless --path . --script tests/test_run_progression.gd
godot --headless --path . --script tests/test_run_progression_runtime.gd
```

- `tests/test_run_progression.gd`（216 项）：经验曲线、卡池规则（武器过滤 / 代价门槛 / 层数上限 / 保底）、加成聚合是否真的落到玩家与生命组件上、武器卡改造与装备校验（含上面的“装不上”回归）、经验球停顿与飞入、击杀与炼金结算、怪物侧减速与连锁、环绕球的生成与伤害、升级面板的暂停与连升、HUD 经验条、开新局重置。
- `tests/test_run_progression_runtime.gd`（53 项）：**真实场景端到端**。加载 `game_world.tscn`、固定种子、走过真实出口进入战斗区域，击杀真怪物，检查经验球真的生成 / 停顿 / 飞入并结算经验，检查升级面板真的弹出并暂停游戏、每次升级恰好弹一次、武器卡真的匹配手上武器；再走真实的“选中即装备 → 叠卡重建”链路，确认连刺的两次刺击配置真的装上、环绕球只在按住左键时存在、松手就消失、开新局真的清零。

## 加一张新卡

在 `UpgradePool._build_catalog()` 里加一行 `_add()`：

```gdscript
_add(&"card_id", "卡名", "描述", rarity, scope, max_stacks, {KEY_DAMAGE_MULT: 0.1})
```

- 纯数值卡：复用已有的 `KEY_*`，`RunProgress` 会自动聚合，读取点已经接好。
- 武器卡：最后两个参数填 `weapon_id` 与生命门槛，`apply_weapon_cards()` 里按武器类型分支处理新键。
- 机制卡：新开一个 `KEY_*`，在对应系统里读同名键实现行为。
