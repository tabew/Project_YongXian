class_name AlchemyMaterialItems
extends RefCounted

## 把炼金材料注册成世界物品：地面掉落 / 背包 / 炼金背包共用同一套 id 与图标。
## 图标用代码生成（品质描边 + 材料主色 + 中央高光），不依赖美术资源；
## 注册进 ItemListGlobal 的查询表，所以按 id 取模板的既有 UI 无需改动。

const ICON_SIZE: int = 12
## 品质描边色：普通 / 稀有 / 史诗 / 传说 / Boss。
const QUALITY_BORDER_COLORS: Array[Color] = [
	Color("9aa0a6"),
	Color("5b9bd5"),
	Color("a86bd6"),
	Color("e0a030"),
	Color("ff5a4a"),
]

static var _templates: Dictionary = {}


## 某材料的物品模板；不是炼金材料时返回 null。
static func template_of(material_id: int) -> IngredientData:
	if not MaterialCatalog.has_material(material_id):
		return null
	if _templates.has(material_id):
		return _templates[material_id]
	var definition: Dictionary = MaterialCatalog.definition_of(material_id)
	var item: IngredientData = IngredientData.new()
	item.id = material_id
	item.name = String(definition.get("name", "炼金材料"))
	item.max_stack = int(definition.get("max_stack", 99))
	item.texture = build_icon(material_id)
	_templates[material_id] = item
	return item


## 把全部炼金材料注册进物品注册表；返回新增条数。
static func register_into(item_list: Node) -> int:
	if item_list == null or not item_list.has_method("register_template"):
		return 0
	var added: int = 0
	for material_id: int in MaterialCatalog.all_ids():
		var template: IngredientData = template_of(material_id)
		if template != null and bool(item_list.call("register_template", template)):
			added += 1
	return added


## 代码生成图标：品质描边 + 材料主色 + 中央高光。
static func build_icon(material_id: int) -> ImageTexture:
	var definition: Dictionary = MaterialCatalog.definition_of(material_id)
	var quality: int = clampi(int(definition.get("quality", 0)), 0, QUALITY_BORDER_COLORS.size() - 1)
	var base: Color = hue_color(material_id)
	var border: Color = QUALITY_BORDER_COLORS[quality]
	var highlight: Color = base.lightened(0.45)
	var image: Image = Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y: int in range(ICON_SIZE):
		for x: int in range(ICON_SIZE):
			var edge: bool = x == 0 or y == 0 or x == ICON_SIZE - 1 or y == ICON_SIZE - 1
			image.set_pixel(x, y, border if edge else base)
	var center: int = ICON_SIZE / 2
	for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		image.set_pixel(center - 1 + offset.x, center - 1 + offset.y, highlight)
	return ImageTexture.create_from_image(image)


## 由材料 id 稳定派生主色：同一材料每次启动颜色一致。
static func hue_color(material_id: int) -> Color:
	var hue: float = fmod(float(material_id) * 0.61803398875, 1.0)
	return Color.from_hsv(hue, 0.55, 0.78)
