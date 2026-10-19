
class_name Sharpness
extends AlchemicalData

## 锋利：附魔专用。附到武器上后，武器的伤害直接提高（不走 buff）。

##0 级加的伤害
@export var damage_bonus: float = 3.0
##每级追加的伤害
@export var damage_bonus_per_level: float = 1.5


##直接加在武器上的伤害，由 WeaponDefinition.enchant_damage() 读取
func weapon_damage_bonus() -> float:
	return damage_bonus + damage_bonus_per_level * float(maxi(level, 0))


##没有炼药反应配方

