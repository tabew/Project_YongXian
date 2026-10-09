# 近战武器系统

当前世界是俯视角，保留 WASD 移动。长剑参考泰拉瑞亚的挥砍节奏：鼠标决定本次攻击方向，左键挥剑，按住左键自动重复。攻击中仍能移动，但本次挥砍方向锁定；下一次攻击重新读取鼠标方向。

开局自动装备长剑，出生点附近有一个训练靶，显示血条、伤害数字和暴击标记，击倒后 2 秒重生。`GameWorld.spawn_training_dummy` 可以关闭训练靶。R 重建世界时会取消正在进行的攻击并重建训练靶。

按 Q 在长剑与长棍之间切换。长棍朝鼠标选定方向做 40° 小扇形挥舞，同时从远处较短、较暗的姿态过渡到近处较长、较亮的姿态，并带短弧形拖尾。攻击开始后锁定本次方向，按住左键可连续挥击。切换会取消当前攻击，松开并重新按左键即可使用新武器。

## 文件与职责

| 文件 | 职责 |
| --- | --- |
| `resources/weapons/weapon_definition.gd` | 通用武器数据、数值校验、攻击场景引用 |
| `resources/weapons/swing_weapon_definition.gd` | 挥砍类数据：长度、宽度、角度、握点、拖尾 |
| `resources/weapons/depth_strike_weapon_definition.gd` | 纵深挥舞类数据：棍身尺寸、小扇形角度、俯仰与透视 |
| `resources/weapons/longsword.tres` | 第一把长剑的完整数值配置 |
| `resources/weapons/long_staff.tres` | 当前长棍的数值、定向挥击范围与外观配置 |
| `resources/weapons/templates/swing_weapon_template.tres` | 可直接复制的长剑类通用模板 |
| `resources/weapons/templates/staff_weapon_template.tres` | 可直接复制的长棍类通用模板 |
| `scripts/weapons/weapon_controller.gd` | 装备、输入状态、攻速限制、攻击实例生命周期 |
| `scripts/weapons/weapon_attack.gd` | 攻击行为基类、数据快照、命中去重、暴击和击退数据 |
| `scripts/weapons/swing_attack.gd` | 挥砍动画与连续扫掠判定 |
| `scripts/weapons/depth_strike_attack.gd` | 长棍的小扇形挥舞、远近过渡与连续判定 |
| `scenes/weapons/swing_attack.tscn` | 所有挥砍类武器共用的攻击场景 |
| `scenes/weapons/depth_strike_attack.tscn` | 纵深挥击类武器的独立攻击场景 |
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

玩家场景的 `weapon_loadout` 数组决定 Q 的切换顺序，默认包含长剑和长棍。向数组追加资源即可加入更多武器，起始装备仍由 `WeaponController.starting_weapon` 决定。空项和当前武器会被跳过，空列表不改变装备。

## 新增同类武器

两份模板都已配置好贴图、攻击场景和全部可调参数，复制后即可装备，不需要新建脚本或场景。

| 类型 | 复制入口 | 资源类型 / 攻击场景 | 默认动作 |
| --- | --- | --- | --- |
| 长剑类 | [swing_weapon_template.tres](../resources/weapons/templates/swing_weapon_template.tres) | `SwingWeaponDefinition` / `swing_attack.tscn` | 150° 扇形横扫 |
| 长棍类 | [staff_weapon_template.tres](../resources/weapons/templates/staff_weapon_template.tres) | `DepthStrikeWeaponDefinition` / `depth_strike_attack.tscn` | 40° 小扇形 + 由远到近过渡 |

1. 将对应模板复制到 `resources/weapons/`，例如 `iron_longsword.tres` 或 `iron_staff.tres`。每把新武器使用独立文件。
2. 在 Inspector 修改 `resource_name`（编辑器名称）、唯一的 `id`、`display_name`（游戏名称）、伤害、暴击、击退和各阶段时间。模板 ID 是占位值，需要替换，例如 `iron_longsword` 或 `iron_staff`。
3. 修改该类型的长度、宽度、角度等专属参数，需要换外观时同时配置 `icon`、`texture`、`texture_grip`。保留模板原有的脚本与 `attack_scene` 配对。
4. 打开 `scenes/game/player.tscn`，选中 Player，将新 `.tres` 加入 `weapon_loadout` 数组。运行后按 Q 即可切换到新武器。若希望开局使用它，将同一资源设为子节点 `WeaponController.starting_weapon`。

也可直接调用 `player.weapon_controller.equip(new_weapon)`。模板用于复制成独立武器；修改副本的数值不会改变模板或其他武器，运行状态由各自的攻击实例管理。两类武器都无需改玩家、控制器或伤害组件。刀、斧等采用弧形横扫的武器也可以复用长剑类模板。

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
- 命中名单按 HealthComponent 去重，不影响同时击中其他目标；查询按批次取尽，超过 32 个受击框也不会丢目标。
- 松开按键停止后续连击；已经开始的攻击正常完成。失去应用焦点或重建世界会立即取消攻击。场景树暂停时物理更新与计时一起暂停。
- UI 消耗的左键按下事件不会触发攻击；松开事件即使被 UI 消耗，也会清除按住状态。
- 当前地形没有物理墙体，剑默认不会被地形格阻挡。后续需要墙体遮挡时，应在命中接口前增加地形或物理射线判断。
- 当前提供长剑、长棍、武器切换和训练靶；背包、拾取、敌人 AI、音效与联网不属于这一层。

## 验证与美术再生成

项目要求 Godot 4.7+。首次在命令行测试前先打开一次编辑器完成导入，或运行：

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_weapons.gd
godot --headless --path . --script res://tests/test_combat_integration.gd
```

测试覆盖两类模板的复制、独立调参、装备、正确动作类型、命中伤害和来源 ID，以及攻击阶段、方向、范围、阵营、碰撞层、多受击框去重、多目标、高速攻击、位移扫掠、数据快照、暴击、防御、击退、死亡重生、自动重复、快速点按、冷却、装备取消和不同攻击行为的扩展接口。集成测试另外验证模板副本加入武器列表后的 Q 切换、HUD 更新，以及玩家输入、世界重建和场景衔接。

重新生成本次加入的原创像素占位素材（需要 Pillow）：

```powershell
python tools/generate_combat_art.py
```

该脚本只生成长剑、长棍和训练靶，不会覆盖地形和玩家素材。
