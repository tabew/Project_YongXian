class_name AlchemyHitEffects
extends RefCounted

## 行为词条 → 战斗层可执行的命中效果（纯逻辑，不碰场景树）。
##
## 把炼金组合里的 9 条行为词条折算成一张扁平的效果表，战斗层只读这张表，
## 不需要认识词条系统；新增行为词条时只改这里 + trait_catalog。
## 数值全部来自 trait_catalog 的每级数值表，不在这里重复定义。

## 没有行为词条时的空效果表。
static func empty_profile() -> Dictionary:
	return {
		"explode": {},
		"chain": {},
		"whirl": {},
		"bounce": {},
		"summon": {},
		"transform": {},
		"pierce": 0,
		"spread_tiles": 0.0,
		# 骨 V「可召唤骷髅」：命中时解锁的召唤来源。
		"skeleton": false,
		# 灵魂：击杀时生成游魂（III 起自动索敌，V 可爆炸）。
		"soul_spawn": {},
		"has_any": false,
	}


## 组合 → 效果表。combo 为空时返回空表。
static func profile(combo: BrewCombo) -> Dictionary:
	var result: Dictionary = empty_profile()
	if combo == null:
		return result
	for trait_instance: TraitInstance in combo.traits:
		match trait_instance.id:
			&"explode":
				result["explode"] = {
					"chance": trait_instance.value_of(&"chance"),
					"radius_tiles": trait_instance.value_of(&"radius"),
					"damage": trait_instance.value_of(&"damage"),
					"chain": trait_instance.has_flag(&"chain"),
				}
			&"chain":
				result["chain"] = {
					"chance": trait_instance.value_of(&"chance"),
					"targets": int(trait_instance.value_of(&"targets")),
					"damage": trait_instance.value_of(&"damage"),
					"rebound": trait_instance.has_flag(&"rebound"),
				}
			&"whirl":
				result["whirl"] = {
					"chance": trait_instance.value_of(&"chance"),
					"damage": trait_instance.value_of(&"damage", 0.60),
					"double": trait_instance.has_flag(&"double"),
				}
			&"bounce":
				result["bounce"] = {
					"bounces": int(trait_instance.value_of(&"bounces")),
					"damage": trait_instance.value_of(&"damage"),
					"wall": trait_instance.has_flag(&"wall_bounce"),
				}
			&"summon":
				result["summon"] = {
					"chance": trait_instance.value_of(&"chance"),
					"count": int(trait_instance.value_of(&"count")),
					"duration": trait_instance.value_of(&"duration"),
					"explode": trait_instance.has_flag(&"explode"),
				}
			&"transform":
				result["transform"] = {
					"radius": trait_instance.value_of(&"radius"),
					"form_switch": trait_instance.has_flag(&"form_switch"),
					"element_infuse": trait_instance.has_flag(&"element_infuse"),
					"free_switch": trait_instance.has_flag(&"free_switch"),
				}
			&"pierce":
				result["pierce"] = int(trait_instance.value_of(&"pierce"))
			&"spread":
				result["spread_tiles"] = trait_instance.value_of(&"radius")
			&"bone":
				if trait_instance.has_flag(&"skeleton"):
					result["skeleton"] = true
			&"soul":
				result["soul_spawn"] = {
					"chance": trait_instance.value_of(&"spawn_chance"),
					"count": int(trait_instance.value_of(&"count", 1)),
					"homing": trait_instance.has_flag(&"homing"),
					"explode": trait_instance.has_flag(&"explode"),
				}
			_:
				pass
	result["has_any"] = has_any(result)
	return result


## 这张表里有没有任何会改变战斗行为的词条。
static func has_any(effects: Dictionary) -> bool:
	if int(effects.get("pierce", 0)) != 0:
		return true
	if float(effects.get("spread_tiles", 0.0)) > 0.0:
		return true
	for key: StringName in [&"explode", &"chain", &"whirl", &"bounce", &"summon", &"transform"]:
		var entry: Dictionary = effects.get(key, {})
		if not entry.is_empty():
			return true
	if bool(effects.get("skeleton", false)) or not (effects.get("soul_spawn", {}) as Dictionary).is_empty():
		return true
	return false


## 命中触发的召唤来源表：行为词条「召唤」+ 骨 V 骷髅。
## 每条 {chance, count, duration, explode, flavor}，战斗层按表逐条掷概率生成召唤物。
static func summon_specs(effects: Dictionary) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var summon: Dictionary = effects.get("summon", {})
	if not summon.is_empty():
		specs.append({
			"chance": float(summon.get("chance", 0.0)),
			"count": int(summon.get("count", 1)),
			"duration": float(summon.get("duration", 5.0)),
			"explode": bool(summon.get("explode", false)),
			"flavor": &"summon",
		})
	if bool(effects.get("skeleton", false)):
		specs.append({
			"chance": AlchemyRules.SKELETON_CHANCE,
			"count": 1,
			"duration": AlchemyRules.SKELETON_DURATION,
			"explode": false,
			"flavor": &"bone",
		})
	return specs


## 击杀触发的召唤来源表：灵魂词条击杀生成游魂。
static func kill_specs(effects: Dictionary) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var soul: Dictionary = effects.get("soul_spawn", {})
	if not soul.is_empty():
		specs.append({
			"chance": float(soul.get("chance", 0.0)),
			"count": int(soul.get("count", 1)),
			"duration": AlchemyRules.SOUL_BURST_DURATION,
			"explode": bool(soul.get("explode", false)),
			"flavor": &"soul",
		})
	return specs


## 召唤来源 → 外观颜色。
static func flavor_color(flavor: StringName) -> Color:
	match flavor:
		&"bone":
			return Color("e6e0c8")
		&"soul":
			return Color("a98cff")
		&"split":
			return Color("8fd14f")
	return Color("6fd8ff")


## 额外命中（爆炸 / 连锁）能覆盖的半径（格）：取两者较大的那个，再叠加扩散加成。
static func extra_hit_radius_tiles(effects: Dictionary) -> float:
	var radius: float = 0.0
	var explode: Dictionary = effects.get("explode", {})
	if not explode.is_empty():
		radius = maxf(radius, float(explode.get("radius_tiles", 0.0)))
	var chain: Dictionary = effects.get("chain", {})
	if not chain.is_empty():
		# 连锁本身不带范围数值，用一个固定搜索半径（2 格）找可跳目标。
		radius = maxf(radius, 2.0)
	return radius + float(effects.get("spread_tiles", 0.0))


## 穿透还能多打几个目标：-1 表示无限，0 表示没有穿透词条。
static func pierce_budget(effects: Dictionary) -> int:
	return int(effects.get("pierce", 0))
