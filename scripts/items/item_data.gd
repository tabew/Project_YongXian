class_name ItemData
extends Resource
##物品数据模板

@export var id:int #物品id
@export var name:String #物品名称
@export var texture:Texture2D #物品图标
@export var max_stack:int = 999 #最大堆叠数


##具有的炼金属性，类型为array[AlchemicalData]
@export var alchemical_attribute:Array[AlchemicalData] = []
##具有的物理属性，类型为array[AlchemicalData]
@export var physical_attribute:Array[PhysicalData] = []


##物品对应场景的文件路径
@export_file("*.tscn") var item_scene_path:String = ""

##取得物品对应的场景，没配置或路径无效时返回 null
func get_item_scene() -> PackedScene:
	if item_scene_path.is_empty():
		return null

	if !ResourceLoader.exists(item_scene_path,"PackedScene"):
		return null

	return load(item_scene_path) as PackedScene

func create_model() -> IngredientModel:
	var scene:PackedScene = get_item_scene()
	if !scene:
		return null

	var model :IngredientModel = scene.instantiate() as IngredientModel
	if !model:
		return null

	model.data = self

	return model

func use() -> void:
	pass
