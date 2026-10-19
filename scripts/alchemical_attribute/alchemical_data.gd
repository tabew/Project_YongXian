class_name AlchemicalData
extends Resource

##炼金属性，参与反应，也可以直接产生效果

@export var attribute_id:int
@export var name:String ="";

##最大效果等级，无法强化的默认0级,一般效果最高暂定3级
@export var max_level:int = 0;

#施加效果是否需要对象
@export var need_target:bool = true

#效果是否是瞬时触发且只触发一次
@export var is_take_only_one:bool = false

##作为武器附魔时效果作用到谁：need_target = false 的属性固定作用在命中点(爆炸这类)
enum EnchantTarget
{
	HIT_TARGET, ## 被命中的目标
	WIELDER,    ## 武器持有者，治疗/恢复这类对自己生效
}

@export var enchant_target: EnchantTarget = EnchantTarget.HIT_TARGET

##能不能用于武器附魔。默认 false：普通炼金属性只参与炼药，不做武器附魔；
##附魔专属属性(单独出的附魔资源)把自己的模板设成 true。
@export var can_be_weapon_enchant: bool = false

##可反应属性名单
@export var can_be_interacted_attribute:Array[int];

##效果等级，最低0级，最高参考maxLevel，等级不影响效果时长。
##无法强化的属性默认0级，原料具有的效果一般为0级，具有等级的药水效果1级起步
@export var level:int = 0;

##判断属性是否可以与之反应：查反应表
func can_interact_with(attribute:AlchemicalData) ->bool:
	if attribute == null:
		return false

	return AlchemyReactions.has_reaction(attribute_id,attribute.attribute_id)

##反应函数，实现A+B=C+D。A 为反应主体，attribute 里是参与反应的其它属性。
##which = 1 返回产物，which = 2 返回被消耗的反应物；没有反应时两者都返回空数组。
##"抵消"类配方没有产物，但 which = 2 会返回双方，坩埚据此把两个属性都消耗掉。
func interact(attribute:Array[AlchemicalData],which:int = 1) ->Array[AlchemicalData]:
	var result:Array[AlchemicalData] = []

	if attribute.is_empty() or attribute[0] == null:
		return result

	var other:AlchemicalData = attribute[0]
	var reaction:Dictionary = AlchemyReactions.lookup(attribute_id,other.attribute_id)

	if reaction.is_empty():
		return result
	if which == 2:
		result.append(self)
		result.append(other)
		return result

	#产物等级：以双方里较高的等级为基准，再套用表里的等级变化。
	#这样反应与投料顺序无关，谁先发起结果都一样。
	var base_level:int = maxi(level,other.level)

	for entry:Array in reaction["products"]:
		var produced_level:int = base_level + int(entry[1])

		if produced_level < 0:
			continue
		var produced:AlchemicalData = _create_attribute(int(entry[0]),produced_level)

		if produced != null:
			result.append(produced)
	return result


##按 id 造属性实例：运行时取注册表。
##不直接引用自动加载符号，脚本在 --script 模式下也能编译。
func _create_attribute(id: int, attribute_level: int) -> AlchemicalData:
	var loop: MainLoop = Engine.get_main_loop()

	if !(loop is SceneTree):
		return null
	var tree: SceneTree = loop as SceneTree
	var registry: Node = tree.root.get_node_or_null("AlchemicalAttributeList")

	if registry == null or !registry.has_method("create"):
		return null
	return registry.call("create", id, attribute_level) as AlchemicalData

##具有等级的属性升级，需要两个相同等级的属性
func can_upgrade_level(attribute:AlchemicalData) -> bool:
	if level >= max_level:
		return false
	if attribute.level == level:
		return true
	else :
		return false

##产生使用效果
func use_effect(object:Node = null) -> void:
	pass


##武器附魔命中时的实际入口。
##默认就是普通效果；需要知道"这一下打了多少"的附魔（吸血）重写它。
func apply_weapon_enchant(target: Node, _hit: CombatHit) -> void:
	use_effect(target)


##正负面词条
enum POLARITY
{
	AUTO = 0,      ##由属性自己决定（默认正面）
	POSITIVE = 1,  ##增益类
	NEGATIVE = 2,  ##伤害/减益类
	NEUTRAL = 3,   ##中性词条，只做修饰、本身不作用于生物
}

##正负面词条（AUTO = 问属性自己）
@export var polarity: POLARITY = POLARITY.AUTO


##这个属性对目标算正面还是负面
func effect_polarity() -> POLARITY:
	if polarity != POLARITY.AUTO:
		return polarity
	return _default_polarity()


##属性正负面判断，增益类不用重写，会造成伤害或减益的属性重写成 NEGATIVE
func _default_polarity() -> POLARITY:
	return POLARITY.POSITIVE


##正面效果
func is_positive_effect() -> bool:
	return effect_polarity() == POLARITY.POSITIVE


##负面效果
func is_negative_effect() -> bool:
	return effect_polarity() == POLARITY.NEGATIVE

