class_name WeaponDefinition
extends Resource

## Shared item data. Runtime attacks take a snapshot; never store combat state here.
@export_group("Identity")
@export var id: StringName = &"weapon"
@export var display_name: String = "Weapon"
@export var icon: Texture2D
@export var attack_scene: PackedScene

@export_group("Damage")
@export_range(0.0, 10000.0, 0.5) var damage: float = 18.0
@export_range(0.0, 1.0, 0.01) var critical_chance: float = 0.04
@export_range(0.0, 1.0, 0.01) var proc_chance: float = 0.0
@export_range(1.0, 10.0, 0.1) var critical_multiplier: float = 2.0
## Velocity impulse, in pixels per second. The target applies its own resistance.
@export_range(0.0, 2000.0, 1.0) var knockback: float = 110.0
@export_flags_2d_physics var hit_mask: int = 4

@export_group("Timing (seconds)")
@export_range(0.0, 5.0, 0.01) var windup_seconds: float = 0.08
@export_range(0.01, 5.0, 0.01) var active_seconds: float = 0.18
@export_range(0.0, 5.0, 0.01) var recovery_seconds: float = 0.20
## Extra delay AFTER the attack has finished.
@export_range(0.0, 5.0, 0.01) var reuse_delay: float = 0.04
@export var auto_repeat: bool = true

@export_group("Upgrade cards")
## 命中后缩短当次后摇的窗口（秒），0 表示无。对应“回旋”。
@export_range(0.0, 2.0, 0.01) var combo_window: float = 0.0
## 命中时自身朝准心位移的格数，0 表示无。对应“剑压”。
@export_range(0.0, 4.0, 0.5) var lunge_tiles: float = 0.0
## 命中时使目标减速的比例，0 表示无。对应“定身”。
@export_range(0.0, 0.9, 0.05) var slow_ratio: float = 0.0
@export_range(0.0, 10.0, 0.1) var slow_seconds: float = 0.0
## 攻击期间额外环绕自身的溜溜球数量。对应“环绕球”。
@export_range(0, 4, 1) var orbit_balls: int = 0


func attack_duration() -> float:
	return windup_seconds + active_seconds + recovery_seconds


func attacks_per_second() -> float:
	return 1.0 / maxf(attack_duration() + reuse_delay, 0.01)


func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if not is_finite(proc_chance) or proc_chance < 0.0 or proc_chance > 1.0:
		errors.append("Proc chance must be between zero and one.")
	if id.is_empty():
		errors.append("Weapon id cannot be empty.")
	if attack_scene == null:
		errors.append("An attack scene is required.")
	if damage < 0.0 or knockback < 0.0:
		errors.append("Damage and knockback must be nonnegative.")
	if critical_chance < 0.0 or critical_chance > 1.0 or critical_multiplier < 1.0:
		errors.append("Critical chance must be 0..1 and multiplier must be >= 1.")
	if windup_seconds < 0.0 or active_seconds <= 0.0 or recovery_seconds < 0.0 or reuse_delay < 0.0:
		errors.append("Active time must be positive; other timings must be nonnegative.")
	if hit_mask == 0:
		errors.append("Select at least one hurtbox collision layer.")
	return errors


@export_group("Enchant")
## 附魔属性：命中时逐个 use_effect 到目标/命中点。不同 attribute_id 可以叠加；
## 同一个 attribute_id 只保留最高级（见 add_enchant）。
## 只有 AlchemicalData.can_be_weapon_enchant 为 true 的属性上得了武器。
@export var enchant_attributes: Array[AlchemicalData] = []


## 这条属性能不能附到本武器上：属性自己得先允许武器附魔
## (AlchemicalData.can_be_weapon_enchant，炼药专属属性默认 false)，
## 再看有没有同类属性、同类是否等级更高。
## 等级相同或更低时整条忽略，也就是低级药水不会让武器回退。
func can_enchant_with(attribute: AlchemicalData) -> bool:
	if attribute == null:
		return false
	if not attribute.can_be_weapon_enchant:
		return false
	for existing: AlchemicalData in enchant_attributes:
		if existing != null and existing.attribute_id == attribute.attribute_id:
			return attribute.level > existing.level
	return true


## 附上一条属性（复制一份，不跟药水实例共用同一个对象）。
## 同 attribute_id 时只有更高等级会顶替原条；否则返回 false 且不做任何改动。
func add_enchant(attribute: AlchemicalData) -> bool:
	if not can_enchant_with(attribute):
		return false
	var copy: AlchemicalData = attribute.duplicate() as AlchemicalData
	copy.level = attribute.level
	for index: int in enchant_attributes.size():
		var existing: AlchemicalData = enchant_attributes[index]
		if existing != null and existing.attribute_id == copy.attribute_id:
			enchant_attributes[index] = copy
			return true
	enchant_attributes.append(copy)
	return true


## 附魔直接加在武器上的伤害（锋利这类）：结算时加在武器基础伤害上。
func enchant_damage() -> float:
	var total: float = 0.0

	for attribute: AlchemicalData in enchant_attributes:
		if attribute != null and attribute.has_method("weapon_damage_bonus"):
			total += maxf(float(attribute.call("weapon_damage_bonus")), 0.0)
	return total


## 附魔直接加在武器上的攻速（急速这类）：和持有者的攻速加成相加。
func enchant_attack_speed() -> float:
	var total: float = 0.0

	for attribute: AlchemicalData in enchant_attributes:
		if attribute != null and attribute.has_method("weapon_attack_speed_bonus"):
			total += maxf(float(attribute.call("weapon_attack_speed_bonus")), 0.0)
	return total
