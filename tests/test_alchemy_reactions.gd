extends SceneTree

## 反应与冲突可达性：全部 32 条反应 + 4 条冲突都能由现有材料两两组合真实触发。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## 提供某标识符（元素词条 id 或材料标签）的全部材料 id。
func _materials_with(identifier: StringName) -> Array[int]:
	var result: Array[int] = []
	for material_id: int in MaterialCatalog.all_ids():
		var definition: Dictionary = MaterialCatalog.definition_of(material_id)
		var found: bool = false
		for entry: Variant in definition.get("traits", []):
			if entry is Dictionary and StringName((entry as Dictionary).get("id", &"")) == identifier:
				found = true
				break
		if not found:
			for tag: StringName in definition.get("tags", []):
				if tag == identifier:
					found = true
					break
		if found:
			result.append(material_id)
	return result


## 找出能提供 a、b 两个标识符的两件不同材料。
func _pair_for(a: StringName, b: StringName) -> Array[int]:
	for left: int in _materials_with(a):
		for right: int in _materials_with(b):
			if left != right:
				return [left, right]
	return []


func _pool_of(material_ids: Array[int]) -> TraitPoolResult:
	var materials: Array[AlchemyMaterial] = []
	for material_id: int in material_ids:
		var material: AlchemyMaterial = MaterialCatalog.create(material_id, 1)
		if material != null:
			materials.append(material)
	return TraitPool.build(materials, AlchemyRules.POOL_LIMIT_FULL)


func _run() -> void:
	# ── 反应表规模 ──────────────────────────────────────────────────────
	var reactions: Array[Dictionary] = ReactionCatalog.all_reactions()
	_check(reactions.size() >= 30, "反应表至少 30 条（实际 %d）" % reactions.size())
	_check(ReactionCatalog.all_conflicts().size() >= 4, "冲突表至少 4 条")

	# ── 每条反应都能由两件现有材料触发 ──────────────────────────────────
	for entry: Dictionary in reactions:
		var reaction_id: StringName = entry["id"]
		var a: StringName = entry["a"]
		var b: StringName = entry["b"]
		_check(not _materials_with(a).is_empty(), "标识符 %s 有材料提供" % a)
		_check(not _materials_with(b).is_empty(), "标识符 %s 有材料提供" % b)
		var pair: Array[int] = _pair_for(a, b)
		_check(pair.size() == 2, "反应 %s（%s + %s）能找到材料组合" % [reaction_id, a, b])
		if pair.size() != 2:
			continue
		var pool: TraitPoolResult = _pool_of(pair)
		var matched: bool = false
		for hit: Dictionary in pool.reactions:
			if StringName(hit.get("id", &"")) == reaction_id:
				matched = true
				break
		_check(matched, "材料 %d + %d 真的触发反应 %s" % [pair[0], pair[1], reaction_id])
		_check(pool.effect_tags.has(reaction_id), "反应 %s 进入效果标签" % reaction_id)

	# ── 每条冲突都能触发 ────────────────────────────────────────────────
	for entry: Dictionary in ReactionCatalog.all_conflicts():
		var a: StringName = entry["a"]
		var b: StringName = entry["b"]
		var pair: Array[int] = _pair_for(a, b)
		_check(pair.size() == 2, "冲突 %s + %s 能找到材料组合" % [a, b])
		if pair.size() != 2:
			continue
		var pool: TraitPoolResult = _pool_of(pair)
		_check(not pool.conflicts.is_empty(), "材料 %d + %d 触发冲突 %s" % [pair[0], pair[1], entry["name"]])

	# ── 原型的 5 条反应依然可达 ─────────────────────────────────────────
	for reaction_id: StringName in ReactionCatalog.PROTOTYPE_REACTION_IDS:
		var reachable: bool = false
		for entry: Dictionary in reactions:
			if entry["id"] == reaction_id and _pair_for(entry["a"], entry["b"]).size() == 2:
				reachable = true
				break
		_check(reachable, "原型反应 %s 可达" % reaction_id)

	# ── Boss 材料能开出高等级反应 ───────────────────────────────────────
	var boss_pool: TraitPoolResult = _pool_of([1071, 1005])
	_check(not boss_pool.reactions.is_empty(), "熔火之心 + 冰晶 触发反应")
	for hit: Dictionary in boss_pool.reactions:
		if StringName(hit.get("id", &"")) == &"steam_burst":
			_check(int(hit.get("level", 1)) == 5, "V 级火与 I 级冰取最高等级 V")
	_check(boss_pool.quality == AlchemyMaterial.Quality.BOSS, "含 Boss 材料时品质取 Boss")

	print("ALCHEMY REACTIONS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
