class_name InspirationRules
extends RefCounted

## 灵感系统数值真源（纯逻辑）：掉落表、死亡留存、贤者之石转化与结算公式。
## 全部是静态纯函数，不依赖场景树，单元测试可直接断言。

## 灵感来源类型。
enum Source {
	NORMAL = 0,            ## 小怪
	ELITE = 1,             ## 精英怪
	REGION_BOSS = 2,       ## 区域 Boss
	FINAL_BOSS = 3,        ## 最终 Boss
	SPECIAL = 4,           ## 特殊怪
	BREAKABLE = 5,         ## 场景破坏
	EVENT = 6,             ## 事件
	CODEX = 7,             ## 图鉴新发现
	FLAWLESS_ROOM = 8,     ## 无伤清房
	REPLACEMENT_BURST = 9, ## 替换爆发击杀
}

const COUNT: int = 10

const NAMES: Array[String] = [
	"小怪", "精英", "区域 Boss", "最终 Boss", "特殊怪",
	"场景破坏", "事件", "图鉴发现", "无伤清房", "替换爆发击杀",
]

## 掉落表：概率 + 数量范围。100% 的来源也走同一条判定，方便统一表现。
const DROPS: Dictionary = {
	Source.NORMAL: {"chance": 0.15, "min": 1, "max": 3},
	Source.ELITE: {"chance": 0.80, "min": 15, "max": 30},
	Source.REGION_BOSS: {"chance": 1.00, "min": 50, "max": 80},
	Source.FINAL_BOSS: {"chance": 1.00, "min": 150, "max": 200},
	Source.SPECIAL: {"chance": 0.50, "min": 5, "max": 10},
	Source.BREAKABLE: {"chance": 0.05, "min": 1, "max": 1},
	Source.EVENT: {"chance": 1.00, "min": 10, "max": 40},
	Source.CODEX: {"chance": 1.00, "min": 5, "max": 5},
	Source.FLAWLESS_ROOM: {"chance": 1.00, "min": 5, "max": 5},
	Source.REPLACEMENT_BURST: {"chance": 1.00, "min": 3, "max": 3},
}

## 贤者之石结算基础值。
const SAGE_STONE_BASE: int = 100

## 材料品质（普通/稀有/史诗/传说）的转化值。
const MATERIAL_VALUES: Array[int] = [2, 8, 25, 80]
## Boss 材料单独一档。
const BOSS_MATERIAL_VALUE: int = 200

## 难度倍率：学徒 / 炼金师 / 大师。
const DIFFICULTY_MULTIPLIERS: Array[float] = [1.0, 1.2, 1.5]

## 灵感留存 I~V 的保留比例，上限 25%。
const RETENTION_RATIOS: Array[float] = [0.05, 0.10, 0.15, 0.20, 0.25]

## 图鉴完成度加成：阈值 → 灵感加成比例。
const CODEX_BONUS_STEPS: Array[Dictionary] = [
	{"threshold": 0.25, "bonus": 0.05},
	{"threshold": 0.50, "bonus": 0.10},
	{"threshold": 0.75, "bonus": 0.20},
	{"threshold": 1.00, "bonus": 0.30},
]


static func name_of(source: int) -> String:
	if source < 0 or source >= COUNT:
		return "未知来源"
	return NAMES[source]


static func chance_of(source: int) -> float:
	return float(DROPS.get(source, {}).get("chance", 0.0))


static func amount_range(source: int) -> Vector2i:
	var entry: Dictionary = DROPS.get(source, {})
	return Vector2i(int(entry.get("min", 0)), int(entry.get("max", 0)))


## 判定一次掉落：返回灵感数量，0 表示没掉。
static func roll(source: int, rng: RandomNumberGenerator) -> int:
	var entry: Dictionary = DROPS.get(source, {})
	if entry.is_empty():
		return 0
	if rng.randf() > float(entry["chance"]):
		return 0
	return rng.randi_range(int(entry["min"]), int(entry["max"]))


## 材料转化：counts 是 {quality: 数量}，boss_count 单独统计。
static func material_conversion(counts: Dictionary, boss_count: int = 0) -> int:
	var total: int = 0
	for quality: int in counts:
		var index: int = clampi(quality, 0, MATERIAL_VALUES.size() - 1)
		total += MATERIAL_VALUES[index] * int(counts[quality])
	total += BOSS_MATERIAL_VALUE * maxi(boss_count, 0)
	return total


## 单个材料的转化值（供 UI 逐件展示）。
static func material_value(quality: int, is_boss_material: bool = false) -> int:
	if is_boss_material:
		return BOSS_MATERIAL_VALUE
	return MATERIAL_VALUES[clampi(quality, 0, MATERIAL_VALUES.size() - 1)]


## 死亡留存比例：level 为 0~5（0 表示还没买过留存升级）。
static func retention_ratio(level: int) -> float:
	if level <= 0:
		return 0.0
	return RETENTION_RATIOS[clampi(level - 1, 0, RETENTION_RATIOS.size() - 1)]


static func difficulty_multiplier(tier: int) -> float:
	return DIFFICULTY_MULTIPLIERS[clampi(tier, 0, DIFFICULTY_MULTIPLIERS.size() - 1)]


## 图鉴完成度对应的灵感加成比例。
static func codex_bonus(completion: float) -> float:
	var bonus: float = 0.0
	for step: Dictionary in CODEX_BONUS_STEPS:
		if completion >= float(step["threshold"]):
			bonus = float(step["bonus"])
	return bonus


## 通关结算：最终灵感 = round((局内已获得 + 贤者之石基础 + 材料转化 + 表现加成) × 难度倍率 × (1 + 图鉴加成))。
## 规格里的"难度倍率/图鉴加成"按乘区处理，便于保持线性可读。
static func settlement(run_inspiration: int, material_counts: Dictionary, difficulty_tier: int, performance_bonus: int = 0, codex_completion: float = 0.0, boss_material_count: int = 0) -> Dictionary:
	var converted: int = material_conversion(material_counts, boss_material_count)
	var base: int = run_inspiration + SAGE_STONE_BASE + converted + performance_bonus
	var difficulty: float = difficulty_multiplier(difficulty_tier)
	var codex: float = codex_bonus(codex_completion)
	var final_value: int = int(round(float(base) * difficulty * (1.0 + codex)))
	return {
		"run": run_inspiration,
		"sage_stone": SAGE_STONE_BASE,
		"materials": converted,
		"performance": performance_bonus,
		"base": base,
		"difficulty": difficulty,
		"codex_bonus": codex,
		"final": final_value,
	}


## 死亡结算：返回 {lost, kept}。
static func death_split(run_inspiration: int, retention_level: int) -> Dictionary:
	var kept: int = int(round(float(maxi(run_inspiration, 0)) * retention_ratio(retention_level)))
	return {"lost": maxi(run_inspiration, 0) - kept, "kept": kept}
