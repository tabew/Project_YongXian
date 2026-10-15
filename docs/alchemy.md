# 随身炼金台（词条堆叠炼金系统）

战斗核心是 **近战武器 + 随身炼金台**。旧的武器附魔 / 配方 / 主辅料系统（坩埚、炼金属性 `AlchemicalData`、`PotionData`、投放区、炼金界面）已整体删除，替换为本文描述的词条堆叠炼金。

战斗循环：**击杀 / 破坏 → 吸附材料 → 按 E 展开 → 快速注入 → 武器变异 → 继续打**。

---

## 1. 模块拆分与依赖

```
scripts/alchemy/
├── core/                       # 纯逻辑（RefCounted，不依赖场景树，可单元测试）
│   ├── trait_category.gd       # 词条类别与裁剪优先级
│   ├── alchemy_rules.gd        # 唯一数值真源：倍率表、基础时长、热量常量、核心公式
│   ├── trait_instance.gd       # 词条实例：等级 / 层数 / 合并 / 数值读取
│   ├── alchemy_material.gd     # 材料实例：品质 / 词条列表 / 标签 / 堆叠
│   ├── trait_pool_result.gd    # 词条池输出 + 修正聚合查询
│   ├── trait_pool.gd           # 收集 → 叠加 → 反应 → 冲突 → 裁剪 → 效果标签
│   ├── brew_combo.gd           # 单一激活组合快照（签名 / 匹配 / 爆发）
│   ├── brew_pipeline.gd        # 材料 → 词条池 → 组合（伤害 / 时长公式入口）
│   ├── duration_tracker.gd     # 倒计时 / 暂停 / 叠加
│   ├── heat_system.gd          # 热量积累 / 冷却 / 过载
│   ├── alchemy_bag.gd          # 格子制材料背包（堆叠 / 锁定 / 过载损失）
│   ├── material_slots.gd       # 素材槽（默认 2 格，可扩到 4）
│   ├── alchemy_input_state.gd  # 按 E 状态机（菜单 / 短按 / 长按轮盘 / 冷却）
│   ├── alchemy_compendium.gd   # 词条图鉴：发现记录 / 完成度 / 存档
│   ├── brew_presets.gd         # 快速预设：素材槽布局存取与可用性判定
│   ├── alchemy_experiments.gd  # 实验系统：配方匹配 / 未解锁遮蔽 / 成功与事故
│   ├── alchemy_progression.gd  # 升级与遗物：修正聚合与派生数值（扩格 / 爆发 / 热量 / 元素等级）
│   ├── alchemy_forge.gd        # 非战斗合金 / 重铸：材料转换与候选加权
│   ├── alchemy_curses.gd       # 诅咒炼金：手动选择 + 诅咒词条随机附带与结算
│   ├── alchemy_living_split.gd # 活体武器分裂：击杀累积 → 分身数量 / 时长 / 伤害比例
│   ├── alchemy_weapon_slots.gd # 武器炼金槽：临时槽 1~2 个（可被挤出）+ 非战斗合金的永久槽
│   ├── alchemy_hit_effects.gd  # 行为词条 → 命中效果表（爆炸 / 连锁 / 回旋 / 弹射 / 穿透 / 扩散）
│   └── alchemy_status_ring.gd  # 武器旁状态环：主导元素取色 + 倒计时弧度
├── alchemy_station.gd          # 编排节点：连接输入、背包、素材槽、组合与战斗层
├── alchemy_vfx.gd              # 表现层：替换爆发 / 反应粒子 / 过载爆炸（代码生成图形）
└── alchemy_hud.gd              # 表现层：常驻状态环 + 完整面板（背包/图鉴/预设/实验/合金）+ 战斗轮盘

scripts/items/alchemy_material_items.gd  # 把炼金材料注册进物品注册表（代码生成品质边框图标）
resources/weapons/weapon_catalog.gd      # 武器扩展表：斧 / 锤 / 矛 / 匕首 / 镰刀 / 拳套 / 鞭 / 盾 / 巨剑（剑沿用 longsword.tres）

resources/alchemy/              # 配置表（唯一真源，新增内容只改这里）
├── trait_catalog.gd            # 38 条词条（元素 13 / 行为 9 / 触发 8 / 修饰 8）
├── material_catalog.gd         # 材料表（含 Boss 材料）+ 世界材料桥接表
├── material_sources.gd         # 群系 / 房间 → 正式炼金材料产地表
├── reaction_catalog.gd         # 32 条反应 + 4 条冲突
└── progression_catalog.gd      # 19 条升级 + 30 件遗物配置

scenes/ui/alchemy/alchemy_hud.tscn   # 炼金界面场景（挂在 GameHUD 下）
```

依赖方向单向向下：`UI / 战斗层 → AlchemyStation → core + 配置表`。core 与配置表之间只有「读配置」，core 不反向引用节点或 UI。

---

## 2. 数据结构

### 词条（Trait）

| 字段 | 说明 |
|------|------|
| `id` | `StringName`，如 `&"fire"` |
| `category` | 元素 / 行为 / 触发 / 修饰 |
| `level` | I~V，倍率 `1.0 / 1.3 / 1.6 / 2.0 / 2.5` |
| `stacks` | 同词条层数，叠加倍率 `1 / 1.5 / 1.75 / 1.85 / 1.9`（≥5 层不再增加） |
| `levels` | 各等级的具体数值数组（伤害 / 时长 / 概率…） |

### 材料（Material）

| 字段 | 说明 |
|------|------|
| `id` | 炼金材料 id，从 `1000` 起（避开物品注册表 1~4 与 300+ 药水段） |
| `quality` | 普通 / 稀有 / 史诗 / 传说，品质修正 `1.0 / 1.15 / 1.3 / 1.5` |
| `trait_entries` | `[{id, level}]`，放入素材槽后所有词条进入词条池 |
| `tags` | 材料标签（metal / machine / oil / wood / water / phase…），可参与反应配对 |
| `max_stack` | 堆叠上限（普通 99、稀有 20、史诗 10、传说 5） |

### 炼金组合（BrewCombo）

一次炼金的最终快照：`effect_tags`（判定相同 / 不同组合）、`traits`、`reactions`、`conflicts`、`quality`、`power`、`base_duration`、`self_damage`、`overload_heat_bonus`、`curse_multiplier`。

### 热量（HeatSystem）

`heat 0~100`、`consecutive_stacks`、`overload_count`、`lock_remaining`、`weapon_disabled_remaining`。

### 背包（AlchemyBag）与素材槽（MaterialSlots）

背包为固定格数（默认 12，可扩），每格 `{material_id, amount, locked}`；素材槽每格只放 1 种材料 id（默认 2 格，可扩到 4）。

### 图鉴（AlchemyCompendium）

`discovered_traits`（id → 已见最高等级）、`discovered_reactions`、`discovered_conflicts`、`discovered_materials`。
完成度 = 已发现条目 / (全部词条 38 + 全部反应 32)。未发现的条目 `name` 为「？？？」、`effect` 为空。
`describe_level(definition, level)` 把某等级数值表渲染成一行可读文本（伤害 / 点燃 / 时长…），
`to_dict` / `from_dict` 支持存档往返。炼金成功时由 `AlchemyStation._record_discovery` 自动登记。

### 预设（BrewPresets）

基础 1 格，升级「快速预设 +1」最多到 4 格（`BASE_SLOT_COUNT=1`、`MAX_SLOT_COUNT=4`）。
每格存一组材料 id（去重保序，最多 4 种）。`requirements` / `can_apply` 判断背包是否够用；
`AlchemyStation.save_preset` / `apply_preset` 负责与素材槽、背包对接，材料不足时给出 `brew_rejected` 且不改动素材槽。

---

## 3. 核心算法

### 3.1 词条池计算（`TraitPool.build`）

```
build(materials, limit):
    merged = {}
    tags = []
    for material in materials:
        quality = max(quality, material.quality)
        tags += material.tags
        for entry in material.trait_entries:
            if entry.id in merged:
                merged[entry.id].level = max(...)      # 等级取最高
                merged[entry.id].stacks += 1           # 层数相加
            else:
                merged[entry.id] = TraitInstance(entry)
    identifiers = [元素词条 id] + tags
    for (a, b) in 无序对(identifiers):
        if 反应表命中(a, b):  记录反应，等级按配置的 a/b 与 level_mode 求
        if 冲突表命中(a, b):  记录反噬
    ordered = sort(merged, 类别优先级 → 等级 → 层数 → id)
    traits = ordered[:limit]            # 超出记入 dropped
    effect_tags = sort(元素词条 id + 反应 id)   # 去重
```

### 3.2 效果生成（`BrewPipeline.from_pool`）

```
combo.power = final_damage(1.0, 最高等级, 最高层数, 持续修正, 反应倍率, 品质) × (1 + 强度修正)
combo.base_duration = final_duration(持续, 稳定, 活体, 诅咒, 品质)
combo.self_damage = 每秒自伤 × (1 - 稳定减免)
```

### 3.3 单一激活组合（`BrewSession.brew`）

```
if 新组合.signature == 当前组合.signature:
    倒计时.extend(新时长); 连续叠层 +1; 热量 +20+5×层数
else:
    if 当前组合 != null:
        旧组合以 50% 强度爆发一次（带旧反应）; 连续叠层清零
    倒计时.start(新时长); 激活新组合
```

### 3.4 持续时间（`DurationTracker`）

```
tick(delta, paused):
    if paused: return false          # 非战斗 / 慢动作中冻结
    remaining -= delta
    return remaining <= 0            # 结束
```

### 3.5 热量（`HeatSystem`）

```
add_brew():   heat += 20 + 连续叠层×5 + 过载词条加成×诅咒倍率
add_interrupt(): heat += 10
tick(delta, in_combat, kills):
    rate = 战斗中 3/秒 : 非战斗 12/秒;  rate += kills × 8
    heat = max(heat - rate×delta, 0)
    if heat >= 100: 过载（结束效果 / 武器失效 8s / 3s 锁定 / 自伤 15 / 材料损失一半）
```

---

## 4. 数值公式

```
最终伤害 = 武器基础伤害 × 等级倍率 × 叠加倍率 × 持续时间修正 × 反应倍率 × 品质修正
最终时长 = 12s × (1+持续) × (1+稳定) × (1+活体) × (1+诅咒) × 品质修正
热量增加 = 20 + 连续叠加次数×5 + 过载词条加成 × 诅咒倍率
```

常量集中在 [alchemy_rules.gd](../scripts/alchemy/core/alchemy_rules.gd)，公式均为静态纯函数，测试直接断言结果。

---

## 5. 操作与状态机

| 输入 | 行为 |
|------|------|
| 非战斗按 E | 打开完整炼金台（`Phase.MENU`），并**完全暂停游戏世界**（`get_tree().paused = true`） |
| 战斗中短按 E | 复用上次配方（`recipe_repeated`）；随后 0.12s 动作硬直，遗物「快速之手」免除 |
| 战斗中长按 E（≥0.35s） | 25% 慢动作轮盘（`Phase.WHEEL`） |
| 受击打断 | 关轮盘 / 取消蓄力，材料不丢，热量 +10，1 秒冷却 |
| Esc | 关闭炼金台 / 轮盘，不消耗材料；暂停中由炼金 HUD 兜底处理 |
| 左键 | 选择 / 确认（炼金台内放入材料、点「炼金」） |
| 右键 | 取消 / 移除材料 |
| Tab | 切换完整炼金台的背包 / 图鉴 / 预设 / 实验 / 合金五页签 |

输入动作：`alchemy_brew`(E)、`alchemy_cancel`(Esc)、`alchemy_cycle`(Tab)，定义在 `project.godot`。

暂停实现：`AlchemyHud` 自身 `process_mode = PROCESS_MODE_ALWAYS`，所以世界暂停时仍能渲染面板、响应鼠标点击与 Esc；
玩家节点在暂停中不再收输入，因此 Esc 关闭由 HUD 的 `_unhandled_input` 兜底。轮盘只改 `Engine.time_scale`（取
`AlchemyStation.slow_motion_scale`，遗物「慢动作芯片」把它降到 0.15），不暂停世界。

---

## 6. 世界材料桥接

地面掉落现在**按群系刷正式炼金材料**（id ≥ 1000）：[ground_materials.gd](../resources/world/ground_materials.gd) 读取 [material_sources.gd](../resources/alchemy/material_sources.gd) 的 `BIOME_TABLE`，按当前群系（12 种）取材料池采样，并保留石头 / 木棍等基础材料。

- 产地表：`AlchemyMaterialSources.pool_for(biome, room_kind)` → 材料 id 池；`ROOM_TABLE` 让 Boss 房额外产出传说级材料。
- 材料注册：`AlchemyMaterialItems.register_into(ItemListGlobal)` 把每条炼金材料注册成物品模板（品质边框图标由代码生成），id ≥ 1000 的模板即炼金材料。
- id 映射：`MaterialCatalog.material_id_for_world()` 对 id ≥ 1000 做恒等映射；仅旧的 1~5 号世界材料（石头 / 木棍 / 给毛 / 猴皮等）走 `WORLD_MATERIAL_BRIDGE` 兼容映射。

> 本次同时修正了仓库里的 id 错位：`stick.tres` 由 1 改为 3、`monkey_hide.tres` 由 3 改为 5，与 `GroundMaterials.STICK_ID` 及「猴皮 ID 5」的既有契约一致。

---

## 7. 扩展指南（只改配置）

- **新增词条**：在 `trait_catalog.gd` 的 `TRAITS` 加一条（id / 类别 / 名称 / 各级数值 / 标志位），其余系统自动识别。
- **新增材料**：在 `material_catalog.gd` 的 `MATERIALS` 加一条（id ≥ 1000 / 品质 / 堆叠 / 词条 / 标签）。
- **新增反应 / 冲突**：在 `reaction_catalog.gd` 加一条（a / b 可为元素词条或材料标签，`level_mode` 决定等级）。

---

## 8. 测试

全部为 `--headless` 断言（`test_weapons` / `test_combat_integration` / `test_alchemy_summon` 含真实物理帧验证）：

```sh
godot --headless --path . --script res://tests/test_alchemy_traits.gd    # 241 项
godot --headless --path . --script res://tests/test_alchemy_spec_values.gd # 410 项（逐级比对目标文档数值）
godot --headless --path . --script res://tests/test_alchemy_pool.gd      # 38 项
godot --headless --path . --script res://tests/test_alchemy_brew.gd      # 38 项
godot --headless --path . --script res://tests/test_alchemy_heat.gd      # 35 项
godot --headless --path . --script res://tests/test_alchemy_bag.gd       # 46 项
godot --headless --path . --script res://tests/test_alchemy_input.gd     # 44 项
godot --headless --path . --script res://tests/test_alchemy_station.gd   # 52 项（含最小可玩原型默认值）
godot --headless --path . --script res://tests/test_alchemy_pause.gd     # 11 项
godot --headless --path . --script res://tests/test_alchemy_compendium.gd # 93 项
godot --headless --path . --script res://tests/test_alchemy_presets.gd   # 38 项
godot --headless --path . --script res://tests/test_alchemy_hud.gd       # 69 项（五页签 + 合金页 + 诅咒行 + 轮盘预览 / 当前生效）
godot --headless --path . --script res://tests/test_alchemy_overload.gd  # 17 项
godot --headless --path . --script res://tests/test_alchemy_vfx.gd       # 15 项
godot --headless --path . --script res://tests/test_alchemy_materials.gd # 175 项（含 Boss 档与灵感结算桥接）
godot --headless --path . --script res://tests/test_alchemy_experiments.gd # 40 项
godot --headless --path . --script res://tests/test_alchemy_reactions.gd  # 178 项（全部反应 / 冲突可达性）
godot --headless --path . --script res://tests/test_alchemy_progression.gd # 130 项
godot --headless --path . --script res://tests/test_alchemy_forge.gd      # 71 项
godot --headless --path . --script res://tests/test_alchemy_curses.gd     # 58 项
godot --headless --path . --script res://tests/test_alchemy_living_split.gd # 34 项
godot --headless --path . --script res://tests/test_alchemy_weapon_slots.gd # 59 项（武器炼金槽）
godot --headless --path . --script res://tests/test_alchemy_hit_effects.gd  # 90 项（行为词条 → 命中效果表 / 召唤来源表）
godot --headless --path . --script res://tests/test_alchemy_summon.gd       # 85 项（真实物理帧：召唤物索敌 / 出手 / 自爆 / 击杀接线）
godot --headless --path . --script res://tests/test_alchemy_status_ring.gd   # 46 项（状态环取色与倒计时弧度）
godot --headless --path . --script res://tests/test_weapons.gd            # 252 项（含暴击率注入与行为词条真实物理命中）
godot --headless --path . --script res://tests/test_weapon_catalog.gd     # 123 项（武器扩展）
godot --headless --path . --script res://tests/test_combat_integration.gd # 62 项（真实物理帧，含无敌 / 暴击接线）
```

新增 `class_name` 脚本后需先让编辑器扫描一次注册全局类：

```sh
godot --headless --path . --editor --import --quit
```

---

## 9. 实现状态

- **P0（已完成）**：词条 / 材料数据结构、词条池计算、单一激活组合（叠加 / 替换 / 替换爆发）、持续时间、热量与过载、按 E 状态机（非战斗完全暂停 / 短按复用 / 长按慢动作轮盘）、受击打断、格子制背包、基础 UI（非战斗完整界面 / 战斗轮盘 / 武器旁常驻）、武器伤害倍率注入与过载失效。
- **P1（已完成）**：词条图鉴、预设系统（Tab 四页签：背包 / 图鉴 / 预设 / 实验）、替换爆发触发词条反应的表现（`AlchemyVfx`）、过热警告表现（分级抖动 / 警告音 / 红闪 / 耳鸣）、按群系刷新正式炼金材料、短按 E 失败反馈（Toast）、实验系统（未解锁显示「？？？」，成功解锁图鉴 / 失败事故自伤 + 额外热量）。
- **P2（已完成）**：武器扩展（`WeaponCatalog`：斧 / 锤 / 矛 / 匕首 / 镰刀 / 拳套 / 鞭 / 盾 / 巨剑，复用 `SwingWeaponDefinition`，刀身贴图代码生成，`PlayerCharacter` 启动时并入武器轮换）；史诗 / 传说 / Boss 材料（Boss 档品质 4，修正 1.7，4 种 Boss 材料 + 专属标签，并桥接灵感结算的 `boss_material_count`）；全部 32 条反应 + 4 条冲突均验证可由现有材料触发；升级与遗物（`ProgressionCatalog` 19 条升级 + 30 件遗物，`AlchemyProgression` 聚合后写回扩格 / 慢动作 / 爆发 / 热量 / 元素等级）；非战斗合金 / 重铸（`AlchemyForge` + HUD 合金页）；诅咒炼金（`AlchemyCurses` 8 条诅咒 + 背包页诅咒行）；活体武器分裂（`AlchemyLivingSplit`，活体 V 击杀累积出分身）。
- **P2 数值接线**：升级 / 遗物的修正全部落到玩法上 —— 堆叠上限倍率写进 `AlchemyBag.stack_multiplier`；`brew_uninterruptible` 让受击不再打断；`auto_stabilizer` 抬高时长公式的稳定项；`fire_guaranteed` 给火系组合补上爆炸词条；`random_mutation` / `chaos_stone` 追加随机词条或抬 1 级；`crit_eye` 经 `WeaponController.critical_chance_bonus` 注入每次攻击；`brew_invuln` 在炼金瞬间给 `PlayerCharacter` 无敌；`poison_safe` 免掉毒系反应的自伤。反应「毒血」（毒 + 血）按配置的 `self_damage` 把吸血变成每秒自伤。行为词条经 `AlchemyHitEffects.profile()` 折算成扁平效果表，由 `WeaponController` 注入每次攻击，在真实物理查询里打到多个目标（爆炸 / 连锁 / 回旋 / 弹射 / 穿透 / 扩散 / 召唤 / 变形）。
- **战斗接线**：`AlchemyHitEffects.summon_specs()` / `kill_specs()` 把「召唤」词条、骨 V 骷髅、灵魂游魂折算成两张召唤来源表；命中触发由 `WeaponAttack._spawn_summons()` 落地，击杀触发由 `PlayerCharacter.on_monster_killed()` 落地（`GameWorld._on_monster_killed()` 在灵感结算之前调用）。召唤物是真实节点 `AlchemySummon`：自动索敌、按间隔出手、寿命到期消散，召唤 V / 灵魂 V 的召唤物消散时自爆 60% 范围伤害，伤害 = 武器基础伤害 × 组合强度 × 比例（召唤 30%、活体分身 60%）。`AlchemyStation.register_kill()` 同时累加本帧击杀数，用于击杀加速热量冷却。
- **已知简化**：行为词条的范围伤害走真实物理查询（`hit_mask` 内的其它目标）；召唤 / 骷髅 / 游魂 / 活体分身已有真实战斗单位，但**形态切换**仍只有配置：变形 III~V 的 `form_switch` / `element_infuse` / `free_switch` 只透出数值（目标文档也没给出切换操作键）。以下词条目前只做到「配置表 + 图鉴命名」，没有独立的场地 / 状态表现：元素的状态附加（点燃 / 叠毒 / 减速冻结 / 感电 / 破甲 / 吸附拉拽 / 致盲 / 吸血 / 对光暗增伤 / 击杀回血与护盾）、攻速与击退修正（风 / 沉重 / 过载 / 锐利）、场地标志（`ground` / `cloud` / `pool` / `spikes` / `dust_storm` / `earthquake` / `metal_collide` / `shatter` / `corrode_weapon` / `shatter_bounce` / `reassemble`）。武器黑烟用 CPUParticles2D 表现；局内升级 / 遗物的获取来源（掉落 / 商店）尚未接入，接口为 `AlchemyStation.add_upgrade()` / `add_relic()`（局外永久升级已由工坊 `Inspiration.apply_to_alchemy_station()` 接入）；`no_stun`（快速之手）与 `no_time_cost`（时之沙）已接线：短按 E 无硬直、炼金效果倒计时冻结。

---

## 10. 需求对照表（目标文档 → 实现 → 验证）

| 需求 | 实现位置 | 验证 |
|------|----------|------|
| 删除旧附魔 / 配方 / 主辅料 | 旧 `scripts/alchemy/cauldon` / `alchemy_menu` / `item_drop_zone`、`scripts/alchemical_attribute/*`、`resources/alchemical_attribute/*`、`scenes/alchemy/*` 已删除 | `git status` 中为 `D` |
| 保留移动 / 近战 / 敌人 / 掉落 / 背包框架 | `scripts/player.gd`、`scripts/weapons/*`、`scripts/monsters/*`、`resources/inventory/*` 未改语义 | `test_weapons` 222、`test_combat_integration` 62 |
| 随身炼金台 | `scripts/alchemy/alchemy_station.gd`（挂在 `player.tscn` 的 `AlchemyStation` 节点） | `test_alchemy_station` 52 |
| 词条池 / 单一激活组合 / 热量 | `core/trait_pool.gd`、`core/brew_session.gd`、`core/heat_system.gd` | `test_alchemy_pool` 38、`test_alchemy_brew` 38、`test_alchemy_heat` 35 |
| 击杀→吸附→E 展开→注入→武器变异 | `absorb_world_material` + `GroundMaterials` + `AlchemyHud` + `WeaponController.damage_multiplier` | `test_alchemy_materials` 175、`test_alchemy_station` 52 |
| 非战斗 E 完全暂停 | `input_state` `Phase.MENU` + `AlchemyHud._set_world_paused` | `test_alchemy_pause` 11 |
| 战斗中短按 E 复用配方 | `AlchemyStation.repeat_last_recipe()` | `test_alchemy_station` 52 |
| 战斗中长按 E 25%（遗物 15%）慢动作 | `LONG_PRESS_SECONDS` + `slow_motion_scale` | `test_alchemy_input` 44、`test_alchemy_progression` 130 |
| 受击打断：关轮盘 / 不丢材料 / +10 热量 / 1s 冷却 | `AlchemyInputState.interrupt()` + `session.notify_interrupt()` | `test_alchemy_input` 44、`test_alchemy_heat` 35 |
| Esc 关闭不消耗材料 | `AlchemyInputState.close()` | `test_alchemy_input` 44、`test_alchemy_pause` 11 |
| 左键选择 / 确认，右键取消 / 移除 | HUD 槽位 / 背包 / 合金页 `gui_input` | `test_alchemy_hud` 69 |
| Tab 切换页签 | `TAB_NAMES` 五页签 + `cycle_tab()` | `test_alchemy_hud` 69 |
| 素材槽默认 2、可扩到 3~4 | `DEFAULT_MATERIAL_SLOTS=2` / `MAX_MATERIAL_SLOTS=4` | `test_alchemy_station` 52、`test_alchemy_progression` 130 |
| 词条等级倍率 1.0/1.3/1.6/2.0/2.5 | `AlchemyRules.LEVEL_MULTIPLIERS` | `test_alchemy_traits` 241 |
| 同词条叠加 1/1.5/1.75/1.85/1.9 | `AlchemyRules.STACK_MULTIPLIERS` | `test_alchemy_traits` 241 |
| 词条池上限 8~10（原型 6） | `POOL_LIMIT_FULL=10` / `POOL_LIMIT_PROTOTYPE=6` | `test_alchemy_station` 52 |
| 异词条反应 + 冲突反噬 | `resources/alchemy/reaction_catalog.gd` | `test_alchemy_reactions` 178 |
| 相同叠加 / 不同替换 / 替换 50% 爆发 | `BrewSession.brew_with()` | `test_alchemy_brew` 38 |
| 基础时长 12s + 持续 / 稳定 / 挥发 / 活体 / 诅咒修正 | `AlchemyRules.final_duration()` | `test_alchemy_traits` 241 |
| 热量 0~100、每次 +20、连叠 +5、冷却分级 | `core/heat_system.gd` | `test_alchemy_heat` 35 |
| 过载：效果结束 / 武器失效 8s / 3 格 30 伤自伤 15 / 材料减半 / 3s 锁定 / 红闪耳鸣黑烟 | `HeatSystem` + `AlchemyStation._on_overload` + `PlayerCharacter` | `test_alchemy_overload` 17、`test_combat_integration` 62 |
| 13 元素 / 9 行为 / 8 触发 / 8 修饰逐级数值 | `resources/alchemy/trait_catalog.gd`（38 条） | `test_alchemy_traits` 241、`test_alchemy_spec_values` 410（逐级比对目标文档） |
| 普通 / 稀有 / 史诗 / 传说 / Boss 材料 | `resources/alchemy/material_catalog.gd` | `test_alchemy_materials` 175 |
| 材料来源按群系 | `resources/alchemy/material_sources.gd` | `test_alchemy_materials` 175 |
| 全部 30+ 反应 | `reaction_catalog.gd` 32 条 | `test_alchemy_reactions` 178 |
| 武器基底 10 种（剑 / 斧 / 锤 / 矛 / 匕首 / 镰刀 / 拳套 / 鞭 / 盾 / 巨剑） | `longsword.tres` + `weapon_catalog.gd`（9 种） | `test_weapon_catalog` 123 |
| 武器炼金槽：1 临时槽 → 最大 2，永久槽仅非战斗合金 | `core/alchemy_weapon_slots.gd` + `alloy_permanent_slot()` | `test_alchemy_weapon_slots` 59 |
| 非战斗完整界面 / 战斗轮盘 / 武器旁常驻 | `scripts/alchemy/alchemy_hud.gd` | `test_alchemy_hud` 69 |
| 非战斗界面操作按钮：实验 / 确认（炼金）/ 拆解（合金·重铸）/ 图鉴 / 预设 | `AlchemyHud` 页签 + 面板按钮 | `test_alchemy_hud` 69、`test_alchemy_forge` 71 |
| 战斗轮盘：素材槽 / 词条池 / 预览（叠加·替换提示）/ 当前生效 / 热量条 | `AlchemyHud._wheel_preview_label` / `_wheel_active_label` | `test_alchemy_hud` 69 |
| 武器旁常驻：效果图标色 + 倒计时环 + 热量条 | `core/alchemy_status_ring.gd` + `AlchemyHud.StatusRing` | `test_alchemy_status_ring` 46 |
| 词条图鉴（元素 / 行为 / 触发 / 修饰 / 反应 + 完成度） | `core/alchemy_compendium.gd` | `test_alchemy_compendium` 93 |
| 过热警告 50/75/90/100 四档表现 | `AlchemyHud._update_feedback()` | `test_alchemy_hud` 69 |
| 升级 19 条 + 遗物 30 件（含 13 元素遗物） | `resources/alchemy/progression_catalog.gd` | `test_alchemy_progression` 130 |
| 预设系统 | `core/brew_presets.gd` | `test_alchemy_presets` 38 |
| 实验系统（未解锁「？？？」/ 事故） | `core/alchemy_experiments.gd` | `test_alchemy_experiments` 40 |
| 非战斗合金 / 重铸 | `core/alchemy_forge.gd` | `test_alchemy_forge` 71 |
| 诅咒炼金 | `core/alchemy_curses.gd` | `test_alchemy_curses` 58 |
| 活体武器分裂 | `core/alchemy_living_split.gd` | `test_alchemy_living_split` 34、`test_alchemy_summon` 85（真实物理帧） |
| 行为词条 → 战斗命中（爆炸 / 连锁 / 回旋 / 弹射 / 穿透 / 扩散） | `core/alchemy_hit_effects.gd` + `WeaponAttack._apply_extra_hits()` | `test_alchemy_hit_effects` 90、`test_weapons` 252（真实物理多目标） |
| 召唤词条 / 骨 V 骷髅 / 灵魂游魂落地成战斗单位 | `alchemy_summon.gd` + `WeaponAttack._spawn_summons()` + `PlayerCharacter.on_monster_killed()` | `test_alchemy_summon` 85（真实物理帧：索敌 / 出手 / 自爆） |
| 击杀加速热量冷却 | `AlchemyStation.register_kill()` + `kills_this_frame` | `test_alchemy_summon` 85、`test_alchemy_heat` 35 |
| 数据驱动：新增内容只改配置 | 5 张配置表 + `WeaponCatalog` | `docs/alchemy.md` §7 |
| 核心纯逻辑、可单测 | `core/` 全部 `RefCounted`，不引用场景树 | 25 个 `test_alchemy_*.gd` |

### 验证目标（试玩检查项）

目标文档的 6 条验证目标是手感问题，不是代码断言，落地后用试玩确认：

1. 2 格素材是否够产生有趣组合 —— 原型 12 词条 × 2 格即可凑出反应，见 §6 的材料池。
2. 「叠相同 vs 换新」是否让人纠结 —— 相同叠加走 `STACK_MULTIPLIERS`（1→1.5→1.75…），换新走 50% 爆发。
3. 替换爆发是否是战术选择 —— 爆发强度 = 旧组合强度 × `burst_ratio`，可被「爆发强化 / 大师 / 符文」抬到 125%/150%。
4. 过热惩罚是否足够重 —— 8s 武器失效 + 3s 锁定 + 材料减半 + 自伤 15。
5. 短按 E 是否爽 —— 短按 0.12s 硬直（「快速之手」可免），复用配方不暂停。
6. 预览是否够快 —— 轮盘常驻素材槽 / 词条池 / 预览 / 当前生效 / 热量，`preview()` 每帧只做纯计算。
