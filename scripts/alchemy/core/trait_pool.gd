class_name TraitPool
extends RefCounted

## 词条池计算：收集 → 叠加 → 反应 → 冲突 → 上限裁剪 → 输出。
## 纯函数，不碰场景树；素材槽里有几种材料就吃几种材料。

## 材料标签在反应配对里按基础等级 I 参与计算。
const TAG_LEVEL: int = 1

static func build(materials: Array[AlchemyMaterial], limit: int = AlchemyRules.POOL_LIMIT_FULL) -> TraitPoolResult:
	var result: TraitPoolResult = TraitPoolResult.new()
	result.pool_limit = maxi(limit, 1)

	var merged: Dictionary = {}
	var tag_set: Array[StringName] = []
	var quality: int = 0

	# 1. 收集：每格材料的每个词条进入词条池。
	for material: AlchemyMaterial in materials:
		if material == null:
			continue
		quality = maxi(quality, material.quality)
		for tag: StringName in material.tags:
			if not tag_set.has(tag):
				tag_set.append(tag)
		for entry: Dictionary in material.trait_entries:
			var trait_id: StringName = entry.get("id", &"")
			var definition: Dictionary = TraitCatalog.definition_of(trait_id)
			if definition.is_empty():
				continue
			var incoming: TraitInstance = TraitInstance.create(definition, int(entry.get("level", 1)), 1)
			if merged.has(trait_id):
				# 2. 叠加：等级取最高，层数相加。
				(merged[trait_id] as TraitInstance).merge(incoming)
			else:
				merged[trait_id] = incoming

	result.quality = quality
	result.tags = tag_set

	# 3. 反应 / 4. 冲突：遍历标识符的无序对。
	var identifiers: Array[StringName] = []
	for trait_id: StringName in merged:
		if (merged[trait_id] as TraitInstance).category == TraitCategory.Kind.ELEMENT:
			identifiers.append(trait_id)
	identifiers.append_array(tag_set)

	for i: int in range(identifiers.size()):
		for j: int in range(i + 1, identifiers.size()):
			var id_a: StringName = identifiers[i]
			var id_b: StringName = identifiers[j]
			var level_a: int = _level_of(merged, tag_set, id_a)
			var level_b: int = _level_of(merged, tag_set, id_b)
			var reaction: Dictionary = ReactionCatalog.reaction_of(id_a, id_b)
			if not reaction.is_empty():
				# 等级按配置自己的 a / b 取，不受遍历顺序影响。
				var entry_a: StringName = reaction.get("a", id_a)
				var entry_b: StringName = reaction.get("b", id_b)
				result.reactions.append({
					"id": reaction.get("id", &""),
					"name": String(reaction.get("name", "")),
					"level": ReactionCatalog.reaction_level(
						reaction.get("level_mode", &"average"),
						_level_of(merged, tag_set, entry_a),
						_level_of(merged, tag_set, entry_b)),
					"a": entry_a,
					"b": entry_b,
					"mode": reaction.get("level_mode", &"average"),
					"self_damage": float(reaction.get("self_damage", 0.0)),
				})
			var conflict: Dictionary = ReactionCatalog.conflict_of(id_a, id_b)
			if not conflict.is_empty():
				result.conflicts.append({
					"name": String(conflict.get("name", "")),
					"a": id_a,
					"b": id_b,
					"severity": float(conflict.get("severity", 1.0)),
				})

	# 5. 上限裁剪：保留优先级高者，其余记入 dropped。
	var ordered: Array[TraitInstance] = []
	for trait_id: StringName in merged:
		ordered.append(merged[trait_id])
	ordered.sort_custom(_trim_order)
	if ordered.size() > result.pool_limit:
		for index: int in range(result.pool_limit, ordered.size()):
			result.dropped.append(ordered[index])
		ordered.resize(result.pool_limit)
	ordered.sort_custom(_display_order)
	result.traits = ordered

	# 6. 输出最终效果标签。
	result.effect_tags = _effect_tags(result)
	return result

## 标签按基础等级参与反应；词条取其当前等级。
static func _level_of(merged: Dictionary, tags: Array[StringName], identifier: StringName) -> int:
	if merged.has(identifier):
		return (merged[identifier] as TraitInstance).level
	return TAG_LEVEL if tags.has(identifier) else 0

## 裁剪顺序：类别优先级 → 等级 → 层数 → id。
static func _trim_order(a: TraitInstance, b: TraitInstance) -> bool:
	var priority_a: int = TraitCategory.priority_of(a.category)
	var priority_b: int = TraitCategory.priority_of(b.category)
	if priority_a != priority_b:
		return priority_a < priority_b
	if a.level != b.level:
		return a.level > b.level
	if a.stacks != b.stacks:
		return a.stacks > b.stacks
	return String(a.id) < String(b.id)

## 展示顺序：类别优先级 → id，保证同一套材料每次输出一致。
static func _display_order(a: TraitInstance, b: TraitInstance) -> bool:
	var priority_a: int = TraitCategory.priority_of(a.category)
	var priority_b: int = TraitCategory.priority_of(b.category)
	if priority_a != priority_b:
		return priority_a < priority_b
	return String(a.id) < String(b.id)

## 最终效果标签 = 元素词条 id + 反应 id，排序去重。
static func _effect_tags(result: TraitPoolResult) -> Array[StringName]:
	var tags: Array[StringName] = []
	for trait_instance: TraitInstance in result.traits:
		if trait_instance.category == TraitCategory.Kind.ELEMENT and not tags.has(trait_instance.id):
			tags.append(trait_instance.id)
	for reaction: Dictionary in result.reactions:
		var reaction_id: StringName = reaction.get("id", &"")
		if not reaction_id.is_empty() and not tags.has(reaction_id):
			tags.append(reaction_id)
	tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return tags
