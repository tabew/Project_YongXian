class_name AlchemicalData
extends Resource

##炼金属性，参与反应，也可以直接产生效果

@export var name:String ="";

##最大效果等级，无法强化的默认0级,一般效果最高暂定3级
@export var max_level:int = 0;


##可反应属性名单
@export var can_be_interacted_attribute:Array[AlchemicalData];

##效果等级，最低0级，最高参考maxLevel，等级不影响效果时长。
##无法强化的属性默认0级，原料具有的效果一般为0级，具有等级的药水效果1级起步
var level:int = 0;

##判断属性是否可以与之反应
func can_interact_with(attribute:AlchemicalData) ->bool:
	if can_be_interacted_attribute.has(attribute):
		return true
	
	else:
		return false

##反应函数，实现A+B=C+D，如果A为反应主体，那么该函数由反应主体A执行，必须继承重写(第二个参数决定是获取生成物还是反应物,默认为1获取生成物，2获取反应物)
func interact(attribute:Array[AlchemicalData],which:int = 1) ->Array[AlchemicalData]:
	var result:Array[AlchemicalData]
	return result

##产生使用效果
func use_effect(object:Node) -> void:
	pass
