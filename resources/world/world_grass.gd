class_name WorldGrass
extends RefCounted

## 地图草丛（星露谷式牧草）的纯数据层。
##
## 规则：
## - **一簇就是一丛草**：5~8 片叶子从同一个根部向外散开，比角色高，能盖住人和怪；
## - 长在各群系的**自然地面**上：草地最密，沼泽 / 稀树草原 / 苔原 / 雪原 / 石地 / 沙地
##   依次变稀，水面与阻挡地形不长；配色按脚下地面走，雪地是顶雪的草、沙漠是枯草；
## - 位置在格内自由分布，不对齐格子，一格至多两簇；
## - 同一种子下同一格永远得到同一簇，工作线程与重复生成结果一致；
## - 本类只回答"哪格长草、长成什么样"，实例化、绘制、切割与持久化由 GrassView
##   与 GameWorld 负责。

const SALT: int = 0x47524153        ## "GRAS"
const PATCH_SALT: int = 0x50415448  ## "PATH"

## 密度扰动的大块尺寸（格）：同一片地方要么茂密要么稀疏，块间平滑过渡。
const PATCH_TILES: int = 9
const PATCH_MIN: float = 0.30
const PATCH_MAX: float = 1.35

## 每格至多几簇。
const MAX_PER_TILE: int = 2
## 同格再长一簇的概率。
const DOUBLE_CHANCE: float = 0.14
## 簇心距格边的最小横向比例。
const MARGIN_X: float = 0.18
## 簇根在所站格内的纵向范围：偏下，叶子向上铺到上一格。
const BASE_TOP: float = 0.52
const BASE_BOTTOM: float = 0.94

## 索引 = Terrain.Kind；数值是"每格长出一簇"的基础概率，0 表示这一面不长草。
const DENSITY: PackedFloat32Array = [
	0.0,   ## 深水
	0.0,   ## 浅水
	0.0,   ## 浮冰
	0.22,  ## 沙滩：干草
	0.55,  ## 草地
	0.0,   ## 森林（阻挡）
	0.0,   ## 针叶林（阻挡）
	0.0,   ## 雨林（阻挡）
	0.50,  ## 沼泽：芦草
	0.46,  ## 稀树草原：干黄草
	0.18,  ## 沙漠：稀疏枯草
	0.34,  ## 苔原：矮草
	0.20,  ## 石地：石缝草
	0.0,   ## 山地（阻挡）
	0.26,  ## 雪原：顶雪草
	0.0,   ## 雪峰（阻挡）
]

## 索引 = Terrain.Kind；配色索引，见 Palette。
const PALETTE: PackedByteArray = [
	0, 0, 0,
	4, 0, 0, 0, 0,
	2, 1, 4, 3, 5, 0, 6, 0,
]

## 配色：0 根部暗色，1 叶身，2 受光叶尖。
enum Palette { GREEN = 0, DRY = 1, REED = 2, PALE = 3, STRAW = 4, ROCK = 5, FROST = 6 }


## 这一格上的草丛；返回 0-2 簇，每簇含世界坐标根部与外观参数。
## 纯函数：不读全局状态，不分配随机数发生器，同输入必然同输出。
static func tufts_at(
	world_seed: int, variant_index: int, terrain: int, tile: Vector2i
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if terrain < 0 or terrain >= DENSITY.size():
		return result
	var base_density: float = DENSITY[terrain]
	if base_density <= 0.0:
		return result
	var state: int = MapRng.mix(
		world_seed ^ SALT,
		tile.x * 73856093 + tile.y * 19349663 + variant_index * 40503
	)
	if unit(state) >= minf(base_density * patch_bias(world_seed, tile), 1.0):
		return result
	result.append(_make_clump(next_state(state), tile, terrain, 0))
	state = next_state(state)
	if result.size() < MAX_PER_TILE and unit(state) < DOUBLE_CHANCE:
		result.append(_make_clump(next_state(state), tile, terrain, 1))
	return result


## 一簇草的外观与位置：格内自由取点，形状、朝向、色调与叶片种子各占一位随机。
static func _make_clump(state: int, tile: Vector2i, terrain: int, index: int) -> Dictionary:
	var span: float = 1.0 - MARGIN_X * 2.0
	var x: float = MARGIN_X + unit(next_state(state)) * span
	var y: float = lerpf(BASE_TOP, BASE_BOTTOM, unit(next_state(state)))
	var scale: float = lerpf(0.78, 1.28, unit(next_state(state)))
	var shape: int = mini(int(unit(next_state(state)) * 4.0), 3)
	var flip: int = 1 if unit(next_state(state)) < 0.5 else 0
	var tint: float = unit(next_state(state))
	var seed_value: int = next_state(state)
	return {
		"position": Vector2(
			(float(tile.x) + x) * float(WorldGenerator.TILE_SIZE),
			(float(tile.y) + y) * float(WorldGenerator.TILE_SIZE)
		),
		"scale": scale,
		"shape": shape,
		"flip": flip,
		"tint": tint,
		"palette": int(PALETTE[terrain]),
		"blade_seed": seed_value,
		# 清除记录用：格坐标加格内序号，跨箱庭也不会撞键。
		"key": Vector2i(tile.x * MAX_PER_TILE + index, tile.y),
	}


## 一簇有几片叶子。
static func blade_count(shape: int) -> int:
	return 5 + clampi(shape, 0, 3)


## 大块密度扰动：茂密与稀疏之间用双线性插值平滑过渡，不留方块感。
static func patch_bias(world_seed: int, tile: Vector2i) -> float:
	var x: float = float(tile.x) / float(PATCH_TILES)
	var y: float = float(tile.y) / float(PATCH_TILES)
	var x0: int = floori(x)
	var y0: int = floori(y)
	var fx: float = _smooth(x - float(x0))
	var fy: float = _smooth(y - float(y0))
	var top: float = lerpf(
		_patch_value(world_seed, x0, y0), _patch_value(world_seed, x0 + 1, y0), fx
	)
	var bottom: float = lerpf(
		_patch_value(world_seed, x0, y0 + 1), _patch_value(world_seed, x0 + 1, y0 + 1), fx
	)
	return lerpf(PATCH_MIN, PATCH_MAX, lerpf(top, bottom, fy))


static func _patch_value(world_seed: int, patch_x: int, patch_y: int) -> float:
	return unit(MapRng.mix(world_seed ^ PATCH_SALT, patch_x * 73856093 + patch_y * 19349663))


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## xorshift64 单步；把一格/一簇的状态推进到下一次抽样。
static func next_state(state: int) -> int:
	state ^= state << 13
	state ^= state >> 7
	state ^= state << 17
	return state


## 取中间 24 位映射到 [0, 1)；先移位再掩码，负数状态同样稳定。
static func unit(state: int) -> float:
	return float((state >> 40) & 0xFFFFFF) / 16777216.0
