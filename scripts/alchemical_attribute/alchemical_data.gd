class_name AlchemicalData
extends Resource

##炼金属性，参与反应，也可以直接产生效果

##效果等级，最低0级，最高参考maxLevel，等级不影响效果时长。
##无法强化的属性默认0级，原料具有的效果一般为0级，具有等级的药水效果1级起步
var level:int = 0;
##最大效果等级，无法强化的默认0级,一般效果最高暂定3级
var max_level:int = 0;

##反应函数，实现A+B=C+D，如果A为反应主体，那么该函数由反应主体A执行
func interact(attribute:Array[AlchemicalData]) -> void:
	pass

##产生使用效果
func use_effect(object:Node) -> void:
	pass

