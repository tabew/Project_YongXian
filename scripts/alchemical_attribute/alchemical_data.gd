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

##可反应属性名单
@export var can_be_interacted_attribute:Array[int];

##效果等级，最低0级，最高参考maxLevel，等级不影响效果时长。
##无法强化的属性默认0级，原料具有的效果一般为0级，具有等级的药水效果1级起步
@export var level:int = 0;

##判断属性是否可以与之反应
func can_interact_with(attribute:AlchemicalData) ->bool:
	if attribute == null:
		return false

	if can_be_interacted_attribute.has(attribute.attribute_id):
		return true

	return false

##反应函数，实现A+B=C+D，如果A为反应主体，那么该函数由反应主体A执行，必须继承重写(第二个参数决定是获取生成物还是反应物,默认为1获取生成物，2获取反应物)
func interact(attribute:Array[AlchemicalData],which:int = 1) ->Array[AlchemicalData]:
	var result:Array[AlchemicalData]
	return result

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

