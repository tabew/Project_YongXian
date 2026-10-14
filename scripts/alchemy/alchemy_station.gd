extends Node

class_name AlchemyStation

## 随身炼金台：把材料背包 / 素材槽 / 单一激活组合 / 热量 / 按 E 状态机编排成一个节点。
##
## 所有数值与规则都在 core/ 的纯逻辑里，本节点只负责：
## 1. 持有并连接各子系统；2. 把输入翻译成炼金动作；3. 对外转发信号供 UI 与战斗层订阅。
## 不依赖场景树结构，可以挂在主角下，也可以在测试里独立 new 出来。

signal bag_changed
signal slots_changed
signal preview_changed(preview: TraitPoolResult)
signal combo_activated(combo: BrewCombo)
signal combo_stacked(combo: BrewCombo, stacks: int)
signal combo_replaced(previous: BrewCombo, burst_power: float, reactions: Array)
signal combo_expired(combo: BrewCombo)
signal brew_rejected(reason: String)
signal self_damage(amount: float)
signal heat_changed(heat: float)
signal overloaded(report: Dictionary)
signal phase_changed(phase: int)
signal recipe_repeated
signal wheel_opened
signal wheel_closed
signal interrupted
signal compendium_changed
signal presets_changed
signal experiments_changed
signal progression_changed
signal forge_changed
signal curses_changed
signal split_ready(count: int)
signal weapon_slots_changed

@export var bag_capacity: int = AlchemyBag.DEFAULT_CAPACITY
@export var material_slot_count: int = AlchemyRules.DEFAULT_MATERIAL_SLOTS
## 词条池上限：正式玩法 8~10（取 10），最小可玩原型可用 POOL_LIMIT_PROTOTYPE(6)。
@export var pool_limit: int = AlchemyRules.POOL_LIMIT_FULL
## 快速预设格数：基础 1，升级「快速预设 +1」最多加到 4。
@export var preset_slots: int = BrewPresets.BASE_SLOT_COUNT
## 慢动作倍率；遗物「慢动作芯片」会把它降到 0.15。
@export var slow_motion_scale: float = AlchemyRules.SLOW_MOTION_SCALE

var bag: AlchemyBag
var slots: MaterialSlots
var session: BrewSession
var input_state: AlchemyInputState
## 词条图鉴：炼金成功时登记材料 / 词条 / 反应 / 冲突。
var compendium: AlchemyCompendium
## 快速预设：保存 / 复原素材槽布局。
var presets: BrewPresets
## 实验系统：未解锁配方显示「？？？」，做实验可能出事故或解锁图鉴。
var experiments: AlchemyExperiments
## 升级与遗物：聚合出素材槽 / 背包 / 预设 / 吸附 / 爆发 / 热量等派生修正。
var progression: AlchemyProgression
## 非战斗合金 / 重铸。
var forge: AlchemyForge
## 诅咒炼金：手动选一条，或由「诅咒」词条随机附带。
var curses: AlchemyCurses
## 活体武器分裂：击杀累积到阈值就分裂出临时分身。
var living_split: AlchemyLivingSplit
## 武器炼金槽：临时槽 1~2 个，永久槽只能靠非战斗合金开出。
var weapon_slots: AlchemyWeaponSlots

## 战斗层每帧写入：是否处于战斗。非战斗时倒计时冻结、按 E 打开完整炼金台。
var in_combat: bool = false
## 战斗层每帧写入：本帧击杀数，用于加速热量冷却。
var kills_this_frame: int = 0

var _ready_done: bool = false
## 过载时「随机损失一半材料」用的随机源。
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 上一次的热量预警档位，用于只在跨档时提醒一次。
var _heat_warning_level: int = 0


func _ready() -> void:
	setup()


## 幂等初始化；测试可以手动调用，不必进场景树。
func setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	progression = AlchemyProgression.new()
	bag = AlchemyBag.new(bag_capacity + progression.bag_plus())
	slots = MaterialSlots.new(material_slot_count + progression.slot_plus())
	session = BrewSession.new(pool_limit)
	input_state = AlchemyInputState.new()
	compendium = AlchemyCompendium.new()
	presets = BrewPresets.new(preset_slots + progression.preset_plus())
	experiments = AlchemyExperiments.new()
	forge = AlchemyForge.new()
	curses = AlchemyCurses.new()
	living_split = AlchemyLivingSplit.new()
	weapon_slots = AlchemyWeaponSlots.new()
	_rng.randomize()
	_connect_signals()
	_connect_audio()
	_apply_progression()
	_emit_preview()


func _connect_signals() -> void:
	bag.changed.connect(_on_bag_changed)
	slots.changed.connect(_on_slots_changed)
	session.combo_activated.connect(func(combo: BrewCombo) -> void: combo_activated.emit(combo))
	session.combo_stacked.connect(func(combo: BrewCombo, stacks: int) -> void: combo_stacked.emit(combo, stacks))
	session.combo_replaced.connect(func(previous: BrewCombo, burst_power: float, reactions: Array) -> void: combo_replaced.emit(previous, burst_power, reactions))
	session.combo_expired.connect(func(combo: BrewCombo) -> void: combo_expired.emit(combo))
	session.brew_rejected.connect(func(reason: String) -> void: brew_rejected.emit(reason))
	session.self_damage.connect(func(amount: float) -> void: self_damage.emit(amount))
	session.heat.heat_changed.connect(func(value: float) -> void: heat_changed.emit(value))
	session.heat.overloaded.connect(_on_overload)
	input_state.phase_changed.connect(func(phase: int) -> void: phase_changed.emit(phase))
	input_state.recipe_repeated.connect(_on_recipe_repeated)
	input_state.wheel_opened.connect(func() -> void: wheel_opened.emit())
	input_state.wheel_closed.connect(func() -> void: wheel_closed.emit())
	input_state.interrupted.connect(_on_interrupted)
	presets.changed.connect(func() -> void: presets_changed.emit())
	experiments.unlocked_changed.connect(func() -> void: experiments_changed.emit())
	progression.changed.connect(_on_progression_changed)
	weapon_slots.changed.connect(func() -> void: weapon_slots_changed.emit())


## 音频管理器是自动加载单例：用运行期查找而不是全局标识符，
## 这样本脚本仍能作为 --script 单元测试的编译依赖被加载（与 player.gd 的 EventBus 一致）。
func _play_sfx(id: StringName, position: Vector2 = Vector2.INF) -> void:
	var manager: Node = get_node_or_null("/root/AudioManager")
	if manager != null:
		manager.call("play_sfx", id, position)


## 炼金音效全部挂在已有信号上，不改动炼金逻辑本身。
func _connect_audio() -> void:
	combo_activated.connect(func(_combo: BrewCombo) -> void: _play_sfx(&"brew_activate"))
	combo_stacked.connect(func(_combo: BrewCombo, _stacks: int) -> void: _play_sfx(&"brew_stack"))
	combo_replaced.connect(func(_previous: BrewCombo, _burst: float, _reactions: Array) -> void: _play_sfx(&"brew_burst"))
	combo_expired.connect(func(_combo: BrewCombo) -> void: _play_sfx(&"brew_expire"))
	brew_rejected.connect(func(_reason: String) -> void: _play_sfx(&"brew_reject"))
	overloaded.connect(func(_report: Dictionary) -> void: _play_sfx(&"brew_overload"))
	wheel_opened.connect(func() -> void: _play_sfx(&"wheel_open"))
	wheel_closed.connect(func() -> void: _play_sfx(&"wheel_close"))
	heat_changed.connect(_on_heat_changed_audio)
	phase_changed.connect(_on_phase_changed_audio)


## 热量跨过预警档位时提醒一次；回落到低档位后可以再次提醒。
func _on_heat_changed_audio(_value: float) -> void:
	var level: int = warning_level()
	if level > _heat_warning_level and level > 0:
		_play_sfx(&"heat_warning")
	_heat_warning_level = level


## 非战斗按 E 打开完整炼金台时给一个开启音；轮盘有独立音效。
func _on_phase_changed_audio(phase: int) -> void:
	if phase == AlchemyInputState.Phase.MENU:
		_play_sfx(&"brew_open")


func _process(delta: float) -> void:
	tick(delta)


## 供战斗层或测试显式推进；_process 只是转调这里。
func tick(delta: float) -> void:
	if not _ready_done:
		return
	input_state.in_combat = in_combat
	input_state.tick(delta)
	# 非战斗与慢动作中暂停倒计时。
	var paused: bool = not in_combat or input_state.is_slow_motion()
	session.tick(delta, paused, in_combat, kills_this_frame)
	kills_this_frame = 0


## ── 输入 ────────────────────────────────────────────────────────────────

func press_brew() -> void:
	input_state.in_combat = in_combat
	input_state.press()


func release_brew() -> void:
	input_state.release()


func cancel() -> bool:
	var closed: bool = input_state.close()
	if closed:
		_play_sfx(&"ui_back")
	return closed


func is_menu_open() -> bool:
	return input_state.is_menu_open()


func is_wheel_open() -> bool:
	return input_state.is_wheel_open()


func is_slow_motion() -> bool:
	return input_state.is_slow_motion()


func is_weapon_disabled() -> bool:
	return session.weapon_disabled()

## 受击打断：关轮盘 / 取消蓄力，材料不丢，进入 1 秒冷却并加热量。
## 「炼金不打断」升级 / 遗物生效时直接忽略，返回 false 表示没有被打断。
func interrupt() -> bool:
	if progression != null and progression.uninterruptible():
		return false
	return input_state.interrupt()

## ── 炼金 ────────────────────────────────────────────────────────────────

## 用当前素材槽炼金；材料不足或过热锁定会返回 null 并发出 brew_rejected。
func brew_from_slots() -> BrewCombo:
	var materials: Array[AlchemyMaterial] = _slot_materials()
	if materials.is_empty():
		brew_rejected.emit("素材槽里没有材料")
		return null
	return _brew(materials)


## 战斗中短按 E：直接复用上次配方，材料从背包里扣。
func repeat_last_recipe() -> BrewCombo:
	var recipe: Array[int] = session.last_recipe
	if recipe.is_empty():
		brew_rejected.emit("还没有可复用的配方")
		return null
	var materials: Array[AlchemyMaterial] = []
	for material_id: int in recipe:
		if bag.count(material_id) <= 0:
			brew_rejected.emit("材料不足，无法复用配方")
			return null
		var material: AlchemyMaterial = MaterialCatalog.create(material_id, 1)
		if material != null:
			materials.append(material)
	if materials.is_empty():
		brew_rejected.emit("还没有可复用的配方")
		return null
	return _brew(materials)


## 统一炼金入口：先按升级 / 遗物提升元素词条等级，再注入诅咒修正，最后交给会话。
func _brew(materials: Array[AlchemyMaterial]) -> BrewCombo:
	var combo: BrewCombo = BrewPipeline.evaluate(_boost_materials(materials), pool_limit)
	if combo.is_empty():
		brew_rejected.emit("素材槽里没有可用词条")
		return null
	_apply_brew_modifiers(combo)
	var result: BrewCombo = session.brew_with(combo, materials)
	if result != null:
		_consume(materials, curses.material_cost() if curses != null else 0)
		_record_discovery(materials, result)
		weapon_slots.install_temporary(result)
	return result


## 元素亲和 / 元素遗物：把材料里的元素词条等级抬高，其余流程不变。
func _boost_materials(materials: Array[AlchemyMaterial]) -> Array[AlchemyMaterial]:
	if progression == null:
		return materials
	var boosted: Array[AlchemyMaterial] = []
	for material: AlchemyMaterial in materials:
		var copy: AlchemyMaterial = material.duplicate_material()
		for entry: Dictionary in copy.trait_entries:
			var trait_id: StringName = StringName(entry.get("id", &""))
			if TraitCatalog.definition_of(trait_id).get("category", -1) != TraitCategory.Kind.ELEMENT:
				continue
			var bonus: int = progression.element_level_plus(trait_id)
			if bonus > 0:
				entry["level"] = AlchemyRules.clamp_level(int(entry.get("level", 1)) + bonus)
		boosted.append(copy)
	return boosted


## 诅咒与升级 / 遗物对最终组合的修正：强度、时长、自伤、额外热量。
func _apply_brew_modifiers(combo: BrewCombo) -> void:
	if curses != null:
		curses.roll_for_combo(combo, _rng)
		if curses.is_active():
			combo.power *= 1.0 + curses.power_bonus()
			combo.self_damage += curses.self_damage()
			combo.base_duration *= maxf(1.0 + curses.duration_bonus(), AlchemyRules.MIN_DURATION_FACTOR)
			combo.overload_heat_bonus += curses.heat_bonus()
	if progression == null:
		return
	# 稳定护符减免副作用；世界树苗让活体完全不伤己。
	var reduction: float = 1.0 if progression.living_safe() else progression.side_effect_reduction()
	combo.self_damage *= 1.0 - clampf(reduction, 0.0, 1.0)
	# 毒不伤己：毒血一类毒系反应带来的自伤直接免掉。
	if progression.poison_safe():
		combo.self_damage = maxf(combo.self_damage - _poison_self_damage(combo), 0.0)
	# 反应大师：只要这次炼金出了反应就整体增伤。
	if not combo.reactions.is_empty():
		combo.power *= 1.0 + progression.reaction_bonus()
	# 湮灭之种：光 + 暗反应额外增伤。
	for reaction: Dictionary in combo.reactions:
		if StringName(reaction.get("id", &"")) == &"annihilation":
			combo.power *= 1.0 + progression.annihilation_bonus()
			break
	# 自动稳定剂：直接抬高时长公式里的「稳定」项。
	var stability: float = progression.stability_bonus()
	if stability > 0.0:
		combo.base_duration *= 1.0 + stability
	# 火炼金必爆：火系组合强制带上爆炸行为。
	if progression.fire_guaranteed() and _has_trait(combo, &"fire"):
		_ensure_trait(combo, &"explode")
	# 随机变异：额外塞一条随机词条。
	if progression.random_mutation():
		_add_random_trait(combo)
	# 混沌石：随机把组合里的一条词条抬 1 级。
	if progression.chaos_random():
		_level_up_random_trait(combo)


## 组合里是否已有该词条。
static func _has_trait(combo: BrewCombo, trait_id: StringName) -> bool:
	for trait_instance: TraitInstance in combo.traits:
		if trait_instance.id == trait_id:
			return true
	return false


## 毒系反应（例如毒血「吸血变自伤」）贡献的每秒自伤，供「毒不伤己」减免。
static func _poison_self_damage(combo: BrewCombo) -> float:
	var total: float = 0.0
	for reaction: Dictionary in combo.reactions:
		var amount: float = float(reaction.get("self_damage", 0.0))
		if amount <= 0.0:
			continue
		if StringName(reaction.get("a", &"")) == &"poison" or StringName(reaction.get("b", &"")) == &"poison":
			total += amount
	return total


## 保证组合带上指定词条；已有则保持原样，缺失时按 I 级加入。
static func _ensure_trait(combo: BrewCombo, trait_id: StringName) -> void:
	if _has_trait(combo, trait_id):
		return
	var instance: TraitInstance = TraitCatalog.create(trait_id, 1, 1)
	if instance != null:
		combo.traits.append(instance)


## 随机变异：从配置表里挑一条组合还没有的词条，按 I 级加入。
func _add_random_trait(combo: BrewCombo) -> void:
	var candidates: Array[StringName] = []
	for trait_id: StringName in TraitCatalog.all_ids():
		if not _has_trait(combo, trait_id):
			candidates.append(trait_id)
	if candidates.is_empty():
		return
	_ensure_trait(combo, candidates[_rng.randi_range(0, candidates.size() - 1)])


## 混沌石：随机把组合里的一条词条抬 1 级（封顶 V）。
func _level_up_random_trait(combo: BrewCombo) -> void:
	if combo.traits.is_empty():
		return
	var picked: TraitInstance = combo.traits[_rng.randi_range(0, combo.traits.size() - 1)]
	picked.level = AlchemyRules.clamp_level(picked.level + 1)


## ── 背包与素材槽 ────────────────────────────────────────────────────────

## 吸附：世界材料 id 经桥接表映射成炼金材料后进背包；返回实际收下的数量。
func absorb_world_material(world_id: int, amount: int) -> int:
	var material_id: int = MaterialCatalog.material_id_for_world(world_id)
	if material_id < 0:
		return 0
	return absorb_material(material_id, amount)


func absorb_material(material_id: int, amount: int) -> int:
	var added: int = bag.add(material_id, amount)
	if added > 0:
		auto_fill_slots()
	return added


## 把背包里的材料按顺序填进空素材槽，方便一键开炼。
func auto_fill_slots() -> void:
	if slots == null:
		return
	for material_id: int in bag.material_ids():
		if not slots.has_free_slot():
			return
		if slots.material_ids().has(material_id):
			continue
		slots.place_first_free(material_id)


func set_slot(index: int, material_id: int) -> bool:
	var placed: bool = slots.place(index, material_id)
	if placed:
		_play_sfx(&"absorb_material")
	return placed

## 把一个材料放进第一个空素材槽；不指定时按背包顺序自动放。返回放入的槽位，失败返回 -1。
func fill_first_free_slot(material_id: int = -1) -> int:
	if material_id >= 0:
		if bag.count(material_id) <= 0:
			return -1
		var direct: int = slots.place_first_free(material_id)
		if direct >= 0:
			_play_sfx(&"absorb_material")
		return direct
	for candidate: int in bag.material_ids():
		if slots.material_ids().has(candidate):
			continue
		var placed: int = slots.place_first_free(candidate)
		if placed >= 0:
			_play_sfx(&"absorb_material")
			return placed
	return -1

func clear_slot(index: int) -> void:
	slots.clear_slot(index)


func clear_slots() -> void:
	slots.clear_all()


## ── 升级与遗物 ──────────────────────────────────────────────────────────

## 获得 / 升级一条升级项；返回新的层数。数值修正立即生效。
func add_upgrade(upgrade_id: StringName, levels: int = 1) -> int:
	if progression == null:
		return 0
	return progression.add_upgrade(upgrade_id, levels)


## 获得一件遗物；重复获得返回 false。数值修正立即生效。
func add_relic(relic_id: StringName) -> bool:
	if progression == null:
		return false
	return progression.add_relic(relic_id)


## 当前长按 E 轮盘的慢动作倍率（升级 / 遗物可降到 15%）。
func current_slow_motion_scale() -> float:
	return progression.slow_motion_scale() if progression != null else slow_motion_scale


## 炼金无敌时长（秒）：升级「炼金无敌」给炼金瞬间 0.3 秒无敌。
func invuln_seconds() -> float:
	return progression.invuln_seconds() if progression != null else 0.0


## 暴击率加成：遗物「暴击之眼」等；战斗层把它注入武器。
func crit_bonus() -> float:
	return progression.crit_bonus() if progression != null else 0.0


## 把升级 / 遗物的派生修正写回各子系统：扩格、慢动作、爆发强度、热量与过载。
## 幂等，setup 与每次获得升级 / 遗物后都会调用。
func _apply_progression() -> void:
	if progression == null:
		return
	_sync_capacity(bag_capacity + progression.bag_plus(), material_slot_count + progression.slot_plus(),
		preset_slots + progression.preset_plus())
	slow_motion_scale = progression.slow_motion_scale()
	bag.stack_multiplier = progression.stack_multiplier()
	weapon_slots.set_temporary_limit(AlchemyWeaponSlots.TEMPORARY_BASE + progression.weapon_slot_plus())
	session.burst_ratio = progression.burst_ratio()
	session.duration_bonus = progression.duration_bonus()
	# 时之沙：炼金不消耗时间；快速之手：短按 E 无硬直。
	session.freeze_duration = progression.no_time_cost()
	input_state.stun_enabled = not progression.no_stun()
	session.heat.gain_multiplier = progression.heat_gain_multiplier()
	session.heat.cooldown_multiplier = progression.heat_cooldown_multiplier()
	session.heat.overload_duration_multiplier = progression.overload_duration_multiplier()


## 把背包 / 素材槽 / 预设扩到目标容量；只增不减，超出上限时按各自上限截断。
func _sync_capacity(bag_target: int, slot_target: int, preset_target: int) -> void:
	if bag != null and bag_target > bag.capacity:
		bag.expand_by(bag_target - bag.capacity)
	if slots != null and slot_target > slots.slot_count():
		slots.expand_by(slot_target - slots.slot_count())
	if presets != null and preset_target > presets.slot_count:
		presets.set_slot_count(preset_target)


func _on_progression_changed() -> void:
	_apply_progression()
	progression_changed.emit()
	bag_changed.emit()
	slots_changed.emit()
	presets_changed.emit()


## ── 非战斗合金 / 重铸 ──────────────────────────────────────────────────

## 选 / 取消一种合金原料（最多两种）。
func toggle_alloy_material(material_id: int) -> bool:
	if forge == null or not forge.toggle_alloy_material(material_id):
		return false
	forge_changed.emit()
	return true


func clear_alloy_selection() -> void:
	if forge == null:
		return
	forge.clear_alloy_selection()
	forge_changed.emit()


func alloy_ready() -> bool:
	return forge != null and forge.alloy_ready()


func reforge_ready() -> bool:
	return forge != null and forge.reforge_ready()


func set_reforge_material(material_id: int) -> bool:
	if forge == null or not forge.set_reforge_material(material_id):
		return false
	forge_changed.emit()
	return true


## 执行合金：消耗两种原料各 1 个，产出品质 +1 的材料。返回产物 id，失败返回 -1。
func alloy_now() -> int:
	if forge == null or not forge.alloy_ready():
		brew_rejected.emit("合金需要两种同品质材料")
		return -1
	var a: int = forge.alloy_selection[0]
	var b: int = forge.alloy_selection[1]
	if bag.count(a) < AlchemyForge.ALLOY_COST_PER_MATERIAL or bag.count(b) < AlchemyForge.ALLOY_COST_PER_MATERIAL:
		brew_rejected.emit("合金材料不足")
		return -1
	var product: int = AlchemyForge.alloy(a, b, _rng)
	if product < 0:
		brew_rejected.emit("这两种材料无法合金")
		return -1
	bag.remove(a, AlchemyForge.ALLOY_COST_PER_MATERIAL)
	bag.remove(b, AlchemyForge.ALLOY_COST_PER_MATERIAL)
	bag.add(product, 1)
	forge.clear_alloy_selection()
	forge_changed.emit()
	bag_changed.emit()
	return product


## 执行重铸：消耗 1 个材料，换成同品质的另一种材料。返回产物 id，失败返回 -1。
func reforge_now() -> int:
	if forge == null or not forge.reforge_ready():
		brew_rejected.emit("重铸需要选中一件材料")
		return -1
	var source: int = forge.reforge_selection
	if bag.count(source) < AlchemyForge.REFORGE_COST:
		brew_rejected.emit("重铸材料不足")
		return -1
	var product: int = AlchemyForge.reforge(source, _rng)
	if product < 0:
		brew_rejected.emit("这件材料无法重铸")
		return -1
	bag.remove(source, AlchemyForge.REFORGE_COST)
	bag.add(product, 1)
	forge_changed.emit()
	bag_changed.emit()
	return product


## ── 诅咒炼金 ────────────────────────────────────────────────────────────

## 手动选一条诅咒（空 StringName 取消）；下一次炼金生效。
func select_curse(curse_id: StringName) -> bool:
	if curses == null or not curses.select(curse_id):
		return false
	curses_changed.emit()
	return true


func active_curses() -> Array[StringName]:
	return curses.active_curses() if curses != null else []


## ── 活体武器分裂 ────────────────────────────────────────────────────────

## 击杀结算：活体词条到 V 级后累积到阈值就分裂。返回本次要生成的分身数。
func register_kill() -> int:
	# 击杀加速热量冷却：tick 会读走这一帧的击杀数。
	kills_this_frame += 1
	if living_split == null:
		return 0
	var count: int = living_split.note_kill(session.active_combo)
	if count > 0:
		split_ready.emit(count)
	return count


## 击杀触发的召唤来源表（灵魂词条生成游魂）；战斗层按表掷概率生成召唤物。
func kill_summons() -> Array[Dictionary]:
	return AlchemyHitEffects.kill_specs(hit_effects())


## 命中触发的召唤来源表（召唤词条 / 骨 V 骷髅）。
func hit_summons() -> Array[Dictionary]:
	return AlchemyHitEffects.summon_specs(hit_effects())


func living_split_count() -> int:
	return AlchemyLivingSplit.split_count(session.active_combo)


func living_split_duration() -> float:
	return AlchemyLivingSplit.split_duration(session.active_combo)


func living_split_damage_ratio() -> float:
	return AlchemyLivingSplit.split_damage_ratio(session.active_combo)


## ── 实验 ────────────────────────────────────────────────────────────────

## 做一次实验：消耗素材槽材料，按概率解锁图鉴或出事故（自伤 + 额外热量）。
## 没有命中任何配方时不消耗材料，只发出 brew_rejected。
func run_experiment() -> Dictionary:
	if experiments == null or slots == null:
		return {}
	var materials: Array[AlchemyMaterial] = _slot_materials()
	if materials.is_empty():
		brew_rejected.emit("素材槽里没有材料")
		return {}
	var result: Dictionary = experiments.resolve(slots.material_ids(), _rng)
	var status: String = String(result.get("status", "nothing"))
	if status == "nothing":
		brew_rejected.emit("这个组合没有可实验的配方")
		return result
	_consume(materials)
	session.heat.add_heat(float(result.get("heat", 0.0)))
	var damage: float = float(result.get("self_damage", 0.0))
	if damage > 0.0:
		self_damage.emit(damage)
	if status == "unlocked":
		_record_experiment(result)
	return result


## 实验成功：把对应反应登记进图鉴（材料 / 词条仍由炼金流程登记）。
func _record_experiment(result: Dictionary) -> void:
	var reaction_id: StringName = StringName(result.get("reaction", &""))
	if compendium != null and reaction_id != &"" and compendium.discover_reaction(reaction_id):
		compendium_changed.emit()


## ── 快速预设 ────────────────────────────────────────────────────────────

## 把当前素材槽布局存进第 index 个预设。
func save_preset(index: int) -> bool:
	if presets == null:
		return false
	return presets.store(index, slots.material_ids())

## 用第 index 个预设复原素材槽；材料不足时不改动素材槽并发出 brew_rejected。
func apply_preset(index: int) -> bool:
	if presets == null:
		return false
	var material_ids: Array[int] = presets.preset_at(index)
	if material_ids.is_empty():
		brew_rejected.emit("预设是空的")
		return false
	if not presets.can_apply(index, _bag_counts()):
		brew_rejected.emit("预设材料不足")
		return false
	slots.clear_all()
	for material_id: int in material_ids:
		slots.place_first_free(material_id)
	return true

func clear_preset(index: int) -> bool:
	if presets == null:
		return false
	return presets.clear(index)

## 第 index 个预设是否可用（非空且材料充足）。
func preset_ready(index: int) -> bool:
	if presets == null:
		return false
	return presets.can_apply(index, _bag_counts())


## ── 查询 ────────────────────────────────────────────────────────────────

## 当前素材槽的词条池预览（不消耗材料）。
func preview() -> TraitPoolResult:
	return TraitPool.build(_slot_materials(), pool_limit)


func combo_power() -> float:
	return session.combo_power() + permanent_slot_bonus()


## 永久炼金槽带来的常驻伤害加成（不随时间衰减）。
func permanent_slot_bonus() -> float:
	return weapon_slots.permanent_bonus() if weapon_slots != null else 0.0


## 当前激活组合的行为词条效果表，供战斗层（武器攻击）读取。
func hit_effects() -> Dictionary:
	return AlchemyHitEffects.profile(session.active_combo if session != null else null)


## ── 武器炼金槽 ──────────────────────────────────────────────────────────

## 武器上还能不能再装一个临时槽。
func weapon_slot_free() -> bool:
	return weapon_slots != null and weapon_slots.has_free_temporary()


## 非战斗合金：把当前素材槽的组合熔成永久槽。战斗中拒绝（永久槽仅非战斗合金）。
## 成功返回装进永久槽的组合，失败返回 null。
func alloy_permanent_slot() -> BrewCombo:
	if weapon_slots == null or forge == null:
		return null
	if in_combat:
		brew_rejected.emit("永久槽只能在非战斗合金")
		return null
	var materials: Array[AlchemyMaterial] = _slot_materials()
	if materials.is_empty():
		brew_rejected.emit("素材槽里没有材料")
		return null
	var combo: BrewCombo = BrewPipeline.evaluate(_boost_materials(materials), pool_limit)
	if combo.is_empty():
		brew_rejected.emit("素材槽里没有可用词条")
		return null
	if not weapon_slots.add_permanent(combo):
		return null
	_consume(materials)
	_record_discovery(materials, combo)
	_play_sfx(&"brew_activate")
	return combo


func active_combo() -> BrewCombo:
	return session.active_combo


func heat() -> float:
	return session.heat.heat


func warning_level() -> int:
	return session.heat.warning_level()


## 当前吸附半径（格）：基础值 + 升级 / 遗物的吸附加成 + 生效组合的「磁」词条等级。
func adsorb_radius_tiles() -> float:
	var radius: float = AlchemyRules.BASE_ADSORB_RADIUS_TILES
	if progression != null:
		radius += progression.adsorb_tiles_plus()
	var combo: BrewCombo = session.active_combo
	if combo == null:
		return radius
	for trait_instance: TraitInstance in combo.traits:
		if trait_instance.id == &"magnet":
			radius += float(trait_instance.level)
	return radius


## 当前吸附半径（像素），供世界层判定「靠近即收」。
func adsorb_radius_pixels() -> float:
	return adsorb_radius_tiles() * float(WorldGenerator.TILE_SIZE)


## 效果倒计时剩余比例，供倒计时环使用。
func duration_ratio() -> float:
	return session.duration.ratio()


func duration_remaining() -> float:
	return session.duration.remaining


## ── 内部 ────────────────────────────────────────────────────────────────

func _slot_materials() -> Array[AlchemyMaterial]:
	var materials: Array[AlchemyMaterial] = []
	if slots == null:
		return materials
	for material_id: int in slots.material_ids():
		var material: AlchemyMaterial = MaterialCatalog.create(material_id, 1)
		if material != null:
			materials.append(material)
	return materials


## 背包现有材料：id → 数量。
func _bag_counts() -> Dictionary:
	var counts: Dictionary = {}
	for material_id: int in bag.material_ids():
		counts[material_id] = bag.count(material_id)
	return counts


## 炼金成功才扣材料；extra 是「魂税」等诅咒要求的额外消耗。
## 背包里没有的槽位不动，锁定格也不会被扣。
func _consume(materials: Array[AlchemyMaterial], extra: int = 0) -> void:
	for material: AlchemyMaterial in materials:
		bag.remove(material.id, 1)
	if extra > 0 and not materials.is_empty():
		for index: int in range(extra):
			bag.remove(materials[index % materials.size()].id, 1)
	for index: int in range(slots.slot_count()):
		var material_id: int = slots.material_at(index)
		if material_id != MaterialSlots.EMPTY and bag.count(material_id) <= 0:
			slots.clear_slot(index)


func _on_bag_changed() -> void:
	bag_changed.emit()
	_emit_preview()


func _on_slots_changed() -> void:
	slots_changed.emit()
	_emit_preview()


func _emit_preview() -> void:
	if slots == null:
		return
	preview_changed.emit(preview())


func _on_recipe_repeated() -> void:
	if repeat_last_recipe() != null:
		recipe_repeated.emit()


func _on_interrupted() -> void:
	# 受击打断：材料不丢；「替身草人」遗物免疫额外热量。
	if progression != null and progression.interrupt_no_heat():
		session.heat.add_heat(0.0)
	else:
		session.notify_interrupt()
	interrupted.emit()


## 过载：随机一种材料损失一半，并把损失写进 report 供战斗层 / 表现层使用。
func _on_overload(report: Dictionary) -> void:
	# 「过热保护」升级：过载不再损失材料。
	if bag != null and not (progression != null and progression.overload_material_safe()):
		var loss: Dictionary = bag.lose_half_of_random_material(_rng)
		if not loss.is_empty():
			report["material_loss"] = loss
	if progression != null and progression.overload_no_weapon_disable():
		report["weapon_disable"] = 0.0
		session.heat.weapon_disabled_remaining = 0.0
	# 过载让当前效果立即结束：临时槽清空，永久槽不受影响。
	if weapon_slots != null:
		weapon_slots.clear_temporary()
	overloaded.emit(report)


## 炼金成功即登记图鉴；有新发现才发信号，避免每帧刷 UI。
func _record_discovery(materials: Array[AlchemyMaterial], combo: BrewCombo) -> void:
	if compendium == null:
		return
	if compendium.discover_combo(combo, materials):
		compendium_changed.emit()
