
class_name Haste
extends AlchemicalData

## 急速：附魔专用。附到武器上后，武器的出手速度直接提高（不走 buff）。

##0 级加的攻速
@export var attack_speed_bonus: float = 0.20
##每级追加的攻速
@export var attack_speed_bonus_per_level: float = 0.08


##直接加在武器上的攻速，由 WeaponDefinition.enchant_attack_speed() 读取
func weapon_attack_speed_bonus() -> float:
	return attack_speed_bonus + attack_speed_bonus_per_level * float(maxi(level, 0))


##没有炼药反应配方

