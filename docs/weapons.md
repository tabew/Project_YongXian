# 近战武器系统

## 溜溜球终极改造

五张卡均为稀有、单层、对应武器专属。雷鸣三选一，蜂巢二选一；每把武器每局独立拥有一个终极改造名额，选后其余同组卡退出候选池，直接领取接口也会拒绝。普通升级仍能叠加，开新局清空。

| 改造 | 行为与代价 |
| --- | --- |
| 天罚契约 | 落雷概率固定 100%；球体伤害降低 60%，接触命中间隔改为 0.65 秒。落雷基础伤害仍为 18，不随球体减伤一起降低。幸运仍提升暴击等事件，但不能将固定概率提升至 100% 以上。 |
| 雷暴核心 | 落雷伤害提高 150%（基础 45），半径提高 50%（60 像素）；原地预警 0.6 秒后结算，触发后冷却 2 秒。保留基础概率与幸运加成。 |
| 风暴信标 | 触发后锁定地面雷区，首次延迟 0.5 秒，之后每 0.7 秒再落雷，共 3 次；同一武器最多同时存在 2 个雷区。预警外圈与伤害半径一致，保留概率触发。 |
| 蜂巢炸弹 | 不再命中生蜂；球体飞行满 1 秒后主动松手，在开始回收的位置释放 8 只蜜蜂，散射后追踪。球周金色圆弧表示装填进度；短按、取消或自动超时不触发。 |
| 迁徙蜂群 | 蜜蜂存活 5 秒，命中不消失，每只每 0.4 秒可撕咬一次，目标死亡后重新寻敌；球体伤害降低 40%，蜂群生成间隔提高到 1.2 秒。单次撕咬基础伤害仍为 6.5。 |

已触发的延迟落雷、雷区和炸弹/迁徙蜜蜂在收球后继续存在，不阻止下一次攻击。跨攻击实例共同限制蜜蜂数量（最多 9 只）、雷区数量和触发冷却，不能靠反复收放绕过。切换武器时清理持续效果。持续效果保留攻击启动时的伤害快照，附加命中不再次触发改造。

改造数据经 `UpgradePool.apply_weapon_cards()` 调用 `SwarmYoyoDefinition.apply_ultimate()` 写入武器副本，`ultimate` 随资源深复制进入攻击快照。专项测试：`godot --headless --path . --script res://tests/test_yoyo_ultimates.gd`；有图形界面时加 `-- --capture` 可保存预警及蜂群截图。

## 雷鸣与蜂巢溜溜球

两者沿用普通溜溜球的指针跟随、84 像素绳长、0.33 秒独立命中冷却、松手回收和单次攻击最长 4 秒有效期。开局背包各提供一把，拖到快捷栏选中即可装备，不增加玩家或控制器的武器 ID 分支。

| 武器 | 物品 ID / 武器 ID | 球体伤害 | 附加攻击 |
| --- | --- | --- | --- |
| 雷鸣 | `203` / `thunder_yoyo` | 12 | 每次有效命中有 10% 概率在目标处落雷，对半径 40 像素内的敌人各造成一次 150% 球体伤害（基础 18），包含触发目标 |
| 蜂巢 | `204` / `hive_yoyo` | 10 | 每次符合冷却和数量限制的有效命中有 15% 概率喷出 3 只蜜蜂；爆发间隔 0.6 秒、同时最多 9 只，每只命中造成 65% 球体伤害（基础 6.5）后消失 |

雷鸣为单次圆形范围伤害，不再蓄电或连锁。垂直闪电劈向命中点，同时显示地面闪光和固定外圈，持续 0.35 秒淡出。地面圆盘、外圈与物理查询均使用同一个 `effect_range`（40 像素）；受击框与圆盘相交即在范围内，多受击框共用 HealthComponent 时只结算一次。残留特效不重复造成伤害。

蜂巢参考蜂巢手雷的蜂群释放方式：每次触发沿不同方向喷出一组蜜蜂，先以 120 像素/秒向外散射 0.3 秒，期间不能伤害敌人；随后平滑转向，追踪 96 像素搜索范围内最近的可攻击目标。蜜蜂有放大的像素外观、振翅和短尾迹，寿命 2.4 秒；没有目标时沿当前方向飞行直至过期。飞行按小步推进并检测移动线段，低帧率也不会跳过散射阶段或直接穿过目标。

配置位于 `resources/weapons/thunder_yoyo.tres` 与 `hive_yoyo.tres`，使用 `SwarmYoyoDefinition` 和 `scenes/weapons/swarm_yoyo_attack.tscn`。Inspector 可调整 `proc_chance`（0～1）、范围、附加伤害比例，以及蜂群数量、上限、间隔、速度、散射时长与寿命。基础触发率分别为 10% / 15%；通用升级卡“幸运”每层相对提高 20%，最多 5 层，满层为 20% / 30%。`proc_chance` 统一定义在 `WeaponDefinition`，由 `RunProgress.build_weapon()` 写入升级后的武器副本，后续新武器可以直接复用。概率使用 `MapRng.Stream.COMBAT`；0 永不触发，1 在符合触发条件时必定触发。运行状态仅保存在攻击实例中，资源仍按攻击开始时取快照。

附加攻击通过 `WeaponAttack._land_hit(hurtbox, damage_scale)` 复用暴击、防御、升级效果和命中信号，保留原武器 ID；不会再次掷骰生成落雷或蜂群。完全被防御抵消的球体攻击不触发特效。查询过滤友军、自己、死亡目标和不匹配碰撞层的目标，并分批处理拥挤场景。无终极改造时，松手或有效期结束立即清除蜜蜂；炸弹/迁徙蜂群及延迟雷区按上面的终极改造规则继续结算。切换武器清理全部特效。

对应物品已加入 `autoloads/item_list.gd`，独立掉落场景在 `scenes/items/weapons/`。像素素材可用 `python tools/generate_yoyo_art.py` 重新生成，不覆盖原有武器素材。攻击与受击音效沿用现有音频系统的通用回退。

专项验证：`godot --headless --path . --script res://tests/test_yoyo_variants.gd`。覆盖概率 0/1、落雷范围内外/中心目标/去重/阵营/碰撞层、特效过期、防御阻挡、蜂群散射无伤害/转向追踪/冷却/上限/寿命，以及松手和取消清理。图形验证可运行 `godot --path . --rendering-method gl_compatibility --script res://tests/test_yoyo_variants.gd -- --capture`，截图输出到 `.godot/thunder_yoyo-preview.png` 和 `.godot/hive_yoyo-preview.png`。


当前世界是俯视角，保留 WASD 移动。长剑参考泰拉瑞亚的挥砍节奏：鼠标决定本次攻击方向，左键挥剑，按住左键自动重复。攻击中仍能移动，但本次挥砍方向锁定；下一次攻击重新读取鼠标方向。

开局不再自带武器，玩家空手出生；装备只能从物品栏来（见下一条）。出生点附近有一个训练靶，显示血条、伤害数字和暴击标记，击倒后 2 秒重生。`GameWorld.spawn_training_dummy` 可以关闭训练靶。R 重建世界时会取消正在进行的攻击并重建训练靶。

## 武器只能从物品栏装备

Q 循环切换、`starting_weapon` 自动装备、`player.equip_next_weapon()` 三个入口都已移除：玩家侧没有任何直接装备武器的路径，避免绕过物品栏。装备链路只有一条：

```text
快捷栏选中装武器的格子 → handy_selection_changed → WeaponData.weapon
  → WeaponController.equip(weapon)
```

开局 `resources/inventory/inventory.tres` 在快捷栏第 1 格放长剑（id 200）、第 2 格放长棍（id 201），并把 `handy_selected` 设为 0，进游戏就已经握着长剑。`WeaponController.equip()` 的校验（数据合法性 + 攻击场景类型）仍然生效，失败时保留原武器。`WeaponController` 本身仍是通用组件，AI 和测试可以直接调 `equip()`，只是玩家不再有别的入口。

实际实现是"选中即装备"：`PlayerCharacter.handy_item_changed()` 监听 `Inventory.handy_selection_changed`，选中 id 在 200–299 之间的 WeaponData 格子就直接 `equip()`，选中其它格子则 `equip(null)` 卸下武器；所以不用按左键，切到武器格就已经拿在手上。武器物品的 `use()` 返回 0，不会被消耗。

左键按下去会先调用 `Inventory.use_handy_slot()` 使用选中格，再把这一下交给 `WeaponController` 起手攻击（当前没有"必须选中武器才挥"的判断）。

长棍朝鼠标选定方向做 40° 小扇形挥舞，同时从远处较短、较暗的姿态过渡到近处较长、较亮的姿态，并带短弧形拖尾。攻击开始后锁定本次方向，按住左键可连续挥击。切换会取消当前攻击，松开并重新按左键即可使用新武器。

## 文件与职责

| 文件 | 职责 |
| --- | --- |
| `resources/weapons/weapon_definition.gd` | 通用武器数据、数值校验、攻击场景引用 |
| `resources/weapons/swing_weapon_definition.gd` | 挥砍类数据：长度、宽度、角度、握点、拖尾 |
| `resources/weapons/depth_strike_weapon_definition.gd` | 纵深挥舞类数据：棍身尺寸、小扇形角度、俯仰与透视 |
| `resources/weapons/yoyo_weapon_definition.gd` | 溜溜球类数据：绳长、球径、甩出与收回速度、重复命中冷却 |
| `resources/weapons/longsword.tres` | 第一把长剑的完整数值配置 |
| `resources/weapons/long_staff.tres` | 当前长棍的数值、定向挥击范围与外观配置 |
| `resources/weapons/yoyo.tres` | 当前溜溜球的数值、飞行手感与外观配置 |
| `resources/weapons/templates/swing_weapon_template.tres` | 可直接复制的长剑类通用模板 |
| `resources/weapons/templates/staff_weapon_template.tres` | 可直接复制的长棍类通用模板 |
| `resources/weapons/templates/yoyo_weapon_template.tres` | 可直接复制的溜溜球类通用模板 |
| `scripts/weapons/weapon_controller.gd` | 装备、输入状态、攻速限制、攻击实例生命周期 |
| `scripts/weapons/weapon_attack.gd` | 攻击行为基类、数据快照、命中去重、暴击和击退数据 |
| `scripts/weapons/swing_attack.gd` | 挥砍动画与连续扫掠判定 |
| `scripts/weapons/depth_strike_attack.gd` | 长棍的小扇形挥舞、远近过渡与连续判定 |
| `scripts/weapons/yoyo_attack.gd` | 溜溜球的指针跟随、绳长边界、收回与重复命中判定 |
| `scenes/weapons/swing_attack.tscn` | 所有挥砍类武器共用的攻击场景 |
| `scenes/weapons/depth_strike_attack.tscn` | 纵深挥击类武器的独立攻击场景 |
| `scenes/weapons/yoyo_attack.tscn` | 溜溜球类武器的独立攻击场景 |
| `scripts/combat/combat_hit.gd` | 单次命中的来源、武器 ID、伤害、暴击、位置、击退 |
| `scripts/combat/health_component.gd` | 血量、防御、受伤和死亡信号 |
| `scripts/combat/combat_hurtbox.gd` | 受击区域、阵营和 HealthComponent 引用 |
| `scenes/combat/training_dummy.tscn` | 通用受伤接口的可运行示例 |

武器资源不保存计时器、命中名单或节点引用。每次攻击深复制配置作为快照，多名角色可共用同一资源，调参不会影响已经挥出的这一剑。角色脚本只负责向控制器提交方向和按键状态，不知道具体武器类型。

## 调整长剑数值

在 Godot 文件系统选中 `resources/weapons/longsword.tres`，直接在 Inspector 修改以下属性并保存。长度单位为世界像素，时间为秒，角度为度，暴击率为 0 到 1。

| 属性 | 长剑默认值 | 作用 |
| --- | --- | --- |
| `damage` | 18 | 单次命中基础伤害 |
| `critical_chance` | 0.04 | 每个目标独立掷骰，4% 暴击率 |
| `critical_multiplier` | 2 | 暴击伤害倍率 |
| `knockback` | 110 | 击退速度冲量，目标决定抗性和移动方式 |
| `windup_seconds` | 0.08 | 前摇，不造成伤害 |
| `active_seconds` | 0.18 | 挥砍有效期 |
| `recovery_seconds` | 0.20 | 后摇，不造成伤害 |
| `reuse_delay` | 0.04 | 后摇结束后的额外间隔 |
| `auto_repeat` | true | 按住是否自动重复；false 时每次需重新按下 |
| `hand_distance` | 9 | 角色中心到握点的距离 |
| `blade_length` | 38 | 握点到剑尖的长度，同时缩放贴图 |
| `blade_width` | 7 | 伤害判定宽度，可独立微调手感 |
| `blade_inset` | 6 | 握点前方不造成伤害的剑柄长度 |
| `arc_degrees` | 150 | 围绕瞄准方向的挥砍范围 |
| `aim_offset_degrees` | 0 | 相对瞄准方向的角度偏移 |
| `texture` / `texture_grip` | 长剑贴图 / (6, 7) | 贴图及其握点 |
| `trail_color` / `trail_degrees` | 淡青 / 42 | 拖尾颜色与长度，不参与伤害判定 |
| `hit_mask` | 4 | 查询第 3 个物理层 EnemyHurtbox |

完整攻击周期 = 前摇 + 有效期 + 后摇 + 额外间隔。默认 0.50 秒，即理论每秒 2 次；实际攻击开始时刻受物理帧量化影响。`attacks_per_second()` 供 HUD 或道具说明使用。

伤害公式：`max(0, 基础伤害 × 暴击倍率 - 目标防御)`，非暴击倍率为 1。实际扣血最多为目标剩余血量。完全被防御抵消时不发送受伤反馈或击退。每个攻击实例对同一个 HealthComponent 最多尝试命中一次；被防御抵消也算本次已经判定。

## 长棍配置

长棍使用 `long_staff.tres`，类型为 `DepthStrikeWeaponDefinition`，攻击场景为 `depth_strike_attack.tscn`。长剑使用 150° 横扫；长棍在瞄准方向两侧各 20° 的范围内挥舞，同时由远到近过渡。朝左时横向挥动自动镜像。动画和命中判定使用相同的旋转、俯仰与透视投影，棍身实际经过哪里就判定哪里。

| 属性 | 长棍默认值 |
| --- | --- |
| 伤害 / 暴击率 / 暴击倍率 | 20 / 4% / 2 |
| 击退冲量 | 180 像素/秒 |
| 前摇 / 有效期 / 后摇 / 间隔 | 0.12 / 0.18 / 0.24 / 0.10 秒 |
| `shaft_length` / `hand_distance` | 握点至前端 24 像素 / 握点离角色 8 像素 |
| `forward_travel` | 出手时握点最多前移 4 像素 |
| `hit_width` / `grip_inset` | 判定宽 4 像素 / 握点前无伤害段 3 像素 |
| `arc_degrees` | 40°，即瞄准方向两侧各 20°；可调范围 0..90° |
| `near_pitch_degrees` / `far_pitch_degrees` | +15° 近处姿态 / -35° 远处姿态 |
| `reverse_strike` | false，默认由远到近；true 切换为由近到远 |
| `perspective_strength` | 0.28，控制近大远小的投影变化 |
| 贴图 / 握点 | 32×5 像素 / (8, 2.5)，实绘棍身厚 3 像素 |

棍身未投影时总长 32 世界像素（此前为 76），约为当前占位角色身高的 1.6 倍；实际显示随俯仰和透视变化。最大前端距离约 36 像素，完整周期为 0.64 秒。默认动画中棍身逐渐伸展并变亮，同时沿小扇形旋转。`arc_degrees` 决定横向挥舞范围，`hit_width` 是每一时刻棍身的判定宽度；目标受击框自身的大小也影响能否接触到棍身。

复制 `templates/staff_weapon_template.tres` 即可添加同类武器；挥舞角度用 `arc_degrees`，远近过渡方向用 `reverse_strike`，尺寸用 `shaft_length` 与贴图，命中宽度用 `hit_width`。握点后方的棍尾仅作显示，不造成背后伤害。纵深俯仰角限制在 -80° 到 +80°，避免贴图翻转与投影退化。

玩家侧的 `weapon_loadout` 数组与 `equip_next_weapon()` 都已删除，`WeaponController.starting_weapon` 也已删除，玩家不再自带或自行切换武器。装备从物品栏来：`resources/items/weapons/*.tres` 是 `WeaponData`，其 `weapon` 字段指向对应武器资源，选中该格子时 `PlayerCharacter.handy_item_changed()` 就把它 `equip()` 上去。要把某把武器放进开局快捷栏，在 `resources/inventory/inventory.tres` 的 `handy_items_pos` / `handy_items` 里加一格。

## 溜溜球配置

溜溜球使用 `yoyo.tres`，类型为 `YoyoWeaponDefinition`，攻击场景为 `yoyo_attack.tscn`。攻击方式参考泰拉瑞亚：球停在指针所在的位置，指针超出绳长时贴在绳长边界上；按住左键维持并持续命中，松手立刻收回。指针换边时球以 `follow_speed` 贴着边界扫过去，因此朝左、朝上等方向都能自然跟随。绳子和球都是运行时绘制，贴图只提供球的外观。

| 属性 | 溜溜球默认值 |
| --- | --- |
| 伤害 / 暴击率 / 暴击倍率 | 12 / 4% / 2 |
| 击退冲量 | 40 像素/秒 |
| 前摇 / 有效期 / 后摇 / 间隔 | 0.06 / 4.0 / 0.30 / 0.06 秒 |
| `max_range` / `hand_distance` | 绳长上限 84 像素 / 球收回后的停靠距离 8 像素 |
| `head_radius` | 球的判定半径 6 像素，同时决定贴图缩放 |
| `follow_speed` / `return_speed` | 追向指针 900 像素/秒 / 收回 900 像素/秒 |
| `hit_interval` | 0.33 秒，同一个目标两次受伤之间的最短间隔 |
| `spin_degrees_per_second` / `string_color` / `string_width` | 900°/秒自旋 / 绳子颜色 / 绳子粗细 |
| 贴图 | 14×14 像素，整张宽度缩放到球的直径 |

球的位置由指针决定：指针在攻击范围内时球停在指针处，超出绳长则贴在绳长边界上（`target_offset()`）。球以 `follow_speed` 追向该位置，所以指针换边时球会贴着边界扫过去，而不是瞬移。整段飞行都做判定，同一个目标按 `hit_interval` 重复受伤，而不是一次攻击只结算一次；按住左键维持，松手立刻收回，攻击在球回到手上时结束。没有按下过的攻击（AI 或测试直接 `try_attack`）会滞空到有效期结束再自己回来。

收回需要 `return_seconds()` = 0.08 秒；HUD 显示的每秒攻击次数由 `attacks_per_second()` 覆写为“甩到边界后立刻收回”的最短循环，不受按住时长影响。

复制 `templates/yoyo_weapon_template.tres` 即可添加同类武器；绳长用 `max_range`，球的大小用 `head_radius` 与贴图，跟随手感用 `follow_speed` 与 `return_speed`，输出节奏用 `hit_interval`。`recovery_seconds` 必须覆盖收回过程，否则装备时校验失败。

溜溜球同样按本文件的 "武器只能从物品栏装备" 一节接入：物品模板 `resources/items/weapons/yoyo.tres` 是 `WeaponData`，其 `weapon` 字段指向 `resources/weapons/yoyo.tres`；要让开局就能选到，再把它的 id 加进 `resources/inventory/inventory.tres` 的快捷栏格子。

## 新增同类武器

三份模板都已配置好贴图、攻击场景和全部可调参数，复制后即可装备，不需要新建脚本或场景。

| 类型 | 复制入口 | 资源类型 / 攻击场景 | 默认动作 |
| --- | --- | --- | --- |
| 长剑类 | [swing_weapon_template.tres](../resources/weapons/templates/swing_weapon_template.tres) | `SwingWeaponDefinition` / `swing_attack.tscn` | 150° 扇形横扫 |
| 长棍类 | [staff_weapon_template.tres](../resources/weapons/templates/staff_weapon_template.tres) | `DepthStrikeWeaponDefinition` / `depth_strike_attack.tscn` | 40° 小扇形 + 由远到近过渡 |
| 溜溜球类 | [yoyo_weapon_template.tres](../resources/weapons/templates/yoyo_weapon_template.tres) | `YoyoWeaponDefinition` / `yoyo_attack.tscn` | 球跟随指针，超出绳长贴在边界 |

1. 将对应模板复制到 `resources/weapons/`，例如 `iron_longsword.tres` 或 `iron_staff.tres`。每把新武器使用独立文件。
2. 在 Inspector 修改 `resource_name`（编辑器名称）、唯一的 `id`、`display_name`（游戏名称）、伤害、暴击、击退和各阶段时间。模板 ID 是占位值，需要替换，例如 `iron_longsword` 或 `iron_staff`。
3. 修改该类型的长度、宽度、角度等专属参数，需要换外观时同时配置 `icon`、`texture`、`texture_grip`。保留模板原有的脚本与 `attack_scene` 配对。
4. 建一个物品模板 `resources/items/weapons/<名称>.tres`（脚本用 `WeaponData`，材料 id 别和现有的撞，武器占 200 段），填 `id`、`name`、`texture`、`max_stack = 1`，并把 `weapon` 指向第 1–3 步的武器资源。玩家只能通过物品栏装备武器，所以这一步是必须的；要让开局就能选到，再把它的 id 放进 `resources/inventory/inventory.tres` 的快捷栏格子里。

`WeaponController.equip(new_weapon)` 仍是公开接口，AI 和测试可以直接调；但玩家侧没有暴露任何调用它的快捷路径，装备统一走物品栏里的武器物品。

两类贴图均使用透明背景，攻击端朝右（+X），`texture_grip` 从贴图左上角测量。长剑按 `blade_length / (贴图宽度 - 握点 X)` 等比缩放，默认贴图 44×14、握点 (6, 7)；长棍按 `shaft_length / (贴图宽度 - 握点 X)` 缩放后再应用远近投影，默认贴图 32×5、握点 (8, 2.5)。更换贴图时尽量裁掉攻击端多余的透明留白，避免视觉长度与判定不符。

装备时校验数据与攻击场景类型。无效装备返回 false 并保留原武器；`equip(null)` 卸下装备。切换或卸下会取消攻击、清除按住状态和冷却，新武器需重新按下。运行中修改配置建议复制资源、修改后重新 `equip`，以重新校验并刷新 HUD。

## 新增不同类型武器

以突刺长枪为例：

1. 创建 `ThrustWeaponDefinition extends WeaponDefinition`，仅增加突刺距离等该类型专属属性；覆写 `validation_errors()` 并保留 `super.validation_errors()`。
2. 创建 `ThrustAttack extends WeaponAttack` 和对应 Node2D 场景。
3. 覆写 `accepts_definition(data)`，确认资源是 `ThrustWeaponDefinition`。
4. 在 `_on_started()` 初始化显示节点。在 `_advance(previous, current)` 实现突刺轨迹，使用 Godot 物理查询获取 `CombatHurtbox` 后调用 `_try_hit(hurtbox)`。
5. 新建该类型的 `.tres`，将 `attack_scene` 指向突刺场景，即可通过同一个控制器装备。

`_advance` 接收整个物理帧的时间区间，`current` 可能超过攻击总时长，子类应裁剪伤害有效区间和显示进度。不要只判断当前帧是否落在有效期内，否则高攻速或低帧率会漏判。自定义行为无需自行结束计时，基类在 `_advance` 返回后处理完成。取消攻击时不触发 `finished`，由控制器清理；自然完成才发出该信号。

控制器公开 `set_aim`、`set_trigger_pressed` 和 `try_attack`，AI 也能复用。监听 `weapon_changed`、`attack_started`、`attack_finished`、`hit_landed` 可接音效、状态或其他反馈；控制器不依赖全局事件总线，也没有按武器 ID 分支的逻辑。

## 为敌人接入受伤

推荐场景结构：

```text
Enemy (Node2D / CharacterBody2D)
  Sprite2D
  Health (Node + HealthComponent)
  Hurtbox (Area2D + CombatHurtbox)
	CollisionShape2D
```

将 Hurtbox 的 `health` 拖到 Health 节点，`team` 设为 2，`collision_layer` 勾选 EnemyHurtbox，`collision_mask` 清空。Hurtbox 保持 `monitorable = true`，不需要主动 monitoring。玩家控制器默认 team 为 1，相同阵营不互相伤害，武器持有者自身的子节点也会被排除。

一个敌人的多个受击框共用一个 HealthComponent，避免一剑重复扣血。监听 `Health.damaged(hit, actual_damage)` 处理击退和受伤动画，监听 `Health.died(hit)` 处理死亡。`hit.knockback` 是速度向量，目标负责乘抗性、叠加速度并遵守自己的地形碰撞；HealthComponent 不直接移动角色。训练靶给出了血条、飘字、受伤变色、击退与重生的示例。

如果未来为玩家增加受击框，使用 PlayerHurtbox 层（第 2 层，掩码值 2）、team 1；敌方武器的 `hit_mask` 相应设为 2。

## 判定与边界

- 每次攻击锁定方向和数值，位移仍跟随持有者。
- 使用 Godot `intersect_shape` 对相邻剑身姿态的凸包做扫掠，角度间隔不超过 5 度，并包含角色在两帧间的平移，避免高速穿透。
- 长棍按有效阶段细分采样小扇形与远近过渡曲线，涵盖两侧轨迹和中途伸展到最远处的时刻；一帧跨完整段挥舞也能命中扫过的目标。其后摇收回和残留拖尾不造成伤害。
- 前摇和后摇均不伤害，后摇起点不会再次检测已经结束的有效期。
- 溜溜球按球心圆采样两帧之间的路径，球实际经过哪里就判定哪里；同一个目标按 `hit_interval` 重复受伤，而不是一次攻击只结算一次。球的位置由指针决定，指针超出绳长时贴在边界。
- 命中名单按 HealthComponent 去重（溜溜球改用受击冷却），不影响同时击中其他目标；查询按批次取尽，超过 32 个受击框也不会丢目标。
- 松开按键停止后续连击；已经开始的攻击正常完成。失去应用焦点或重建世界会立即取消攻击。场景树暂停时物理更新与计时一起暂停。
- UI 消耗的左键按下事件不会触发攻击；松开事件即使被 UI 消耗，也会清除按住状态。
- 当前地形没有物理墙体，剑默认不会被地形格阻挡。后续需要墙体遮挡时，应在命中接口前增加地形或物理射线判断。
- 当前提供长剑、长棍、溜溜球、武器切换和训练靶；背包、拾取、敌人 AI、音效与联网不属于这一层。

## 验证与美术再生成

项目要求 Godot 4.7+。首次在命令行测试前先打开一次编辑器完成导入，或运行：

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_weapons.gd
godot --headless --path . --script res://tests/test_combat_integration.gd
godot --headless --path . --script res://tools/test_handy_selection_and_use.gd
```

测试覆盖三类模板的复制、独立调参、装备、正确动作类型、命中伤害和来源 ID，以及攻击阶段、方向、范围、阵营、碰撞层、多受击框去重、多目标、高速攻击、位移扫掠、数据快照、暴击、防御、击退、死亡重生、自动重复、快速点按、冷却、装备取消和不同攻击行为的扩展接口。溜溜球另外覆盖指针内定位、绳长边界、松手收回、重复命中冷却、跟随速度限制与无人按住的自动回收。集成测试另外验证开局空手、通过快捷栏格子上装武器、模板副本做成物品后同样能装备、HUD 更新，以及玩家输入、世界重建和场景衔接。物品栏验收另外验证选中不触发使用、`use()` 返回值决定扣数、武器物品装备后不消耗、滚轮可以停在空格上。

重新生成本次加入的原创像素占位素材（需要 Pillow）：

```powershell
python tools/generate_combat_art.py
```

该脚本只生成长剑、长棍、溜溜球和训练靶，不会覆盖地形和玩家素材。
