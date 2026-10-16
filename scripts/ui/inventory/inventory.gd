extends Resource

class_name Inventory
##背包数据资源，只用于存储背包数据

signal inventory_update

##当前选中的物品栏格子改变
signal handy_selection_changed

##当前选中的物品栏格子
@export var handy_selected:int = 0

##背包内已有物品的id列表：背包同种物品只占一条记录，不能分开
@export var has_items:Array[int]
##背包物品id和数量的字典
@export var items:Dictionary[int,int]

var get_item_data:Dictionary[int,ItemData]

##物品栏(快捷栏)每格的物品id：格子位置0-8 -> 物品id，空格子没有键
##物品栏按格子管理，同一个物品id可以同时占好几个格子
@export var handy_items_pos:Dictionary[int,int]
##物品栏每格的数量：格子位置0-8 -> 数量
@export var handy_items:Dictionary[int,int]

##物品栏格子数量，与bottom_bag_ui场景里的格子数一致
const HANDY_SLOT_COUNT:int = 9

func _init() -> void:
    for item in has_items:
        get_item_data[item] = get_item_template(item)
    for item in handy_items_pos:
        get_item_data[handy_items_pos[item]] = get_item_template(handy_items_pos[item])

##取物品注册表节点。
func get_registry_node() ->Node:

    var loop:MainLoop = Engine.get_main_loop()

    if !(loop is SceneTree):
        return null

    var tree:SceneTree = loop as SceneTree

    if tree.root == null:
        return null

    return tree.root.get_node_or_null("ItemListGlobal")

##按物品id取模板，注册表缺失或没登记时返回 null
func get_item_template(item_id:int) ->ItemData:

    var registry:Node = get_registry_node()

    if registry == null or item_id < 0:
        return null

    return registry.get_template(item_id) as ItemData

##移除物品函数，item_id为物品id
func remove_item(item_id:int,num:int = 1) ->void:

    if !has_items.has(item_id):return #没有该物品，退出函数

    items[item_id] -= num

    if items[item_id] <= 0:
        has_items.erase(item_id)
        items.erase(item_id) #全部拿完，背包中失去该物品

    inventory_update.emit()

##增加物品函数，item_id为物品id
func add_item(item_id:int,num:int)->void:

    if !has_items.has(item_id):
        has_items.append(item_id)
        items[item_id] = num 
        get_item_data[item_id] = get_item_template(item_id)#没有该物品

    else:
        items[item_id] += num

    inventory_update.emit()

##返回背包内对应物品数量，没有返回0
func get_count(item_id:int) ->int:
    if !has_items.has(item_id):
        return 0
    return items[item_id]

##取物品栏某格的物品id，空格返回-1
func get_handy_slot_id(pos:int) ->int:

    return handy_items_pos.get(pos,-1)

##取物品栏某格的数量，空格返回0
func get_handy_slot_count(pos:int) ->int:

    return handy_items.get(pos,0)

#//////////////////////////////////选取部分
##选中物品栏某格
func select_handy_slot(pos:int) ->bool:

    if pos < 0 or pos >= HANDY_SLOT_COUNT:
        return false

    if pos == handy_selected:
        return false

    handy_selected = pos
    handy_selection_changed.emit()

    return true

##取当前选中的格子位置
func get_selected_handy() ->int:

    return handy_selected

##左键使用选取格子物品
func left_use_handy_slot(player:PlayerCharacter) -> void:

    var pos:int = handy_selected

    if pos < 0:
        return

    var item_id:int = get_handy_slot_id(pos)

    if item_id < 0 or get_handy_slot_count(pos) <= 0:
        return

    var item:ItemData = get_item_data[item_id]

    if item == null:
        return

    var consume:int = item.left_use(player)

    if consume > 0:
        remove_handy_slot(pos,consume)
        if item_id>=300:
           _drop_runtime_instance_if_gone(item_id)

    return

##右键使用选取格子物品
func right_use_handy_slot(player:PlayerCharacter) -> void:

    var pos:int = handy_selected

    if pos < 0:
        return

    var item_id:int = get_handy_slot_id(pos)

    if item_id < 0 or get_handy_slot_count(pos) <= 0:
        return

    var item:ItemData = get_item_data[item_id]

    if item == null:
        return

    var consume:int = item.right_use(player)

    if consume > 0:
        remove_handy_slot(pos,consume)
        if item_id>=300:
           _drop_runtime_instance_if_gone(item_id)

    return
#//////////////////////////////

func _drop_runtime_instance_if_gone(item_id:int) ->void:

    var registry:Node = get_registry_node()

    if registry == null or not registry.has_runtime_instance(item_id):
        return

    if get_count(item_id) > 0:
        return

    for pos:int in HANDY_SLOT_COUNT:
        if get_handy_slot_id(pos) == item_id:
            return

    registry.unregister_instance(item_id)

##把物品放进物品栏某格
func add_handy_slot(pos:int,item_id:int,num:int = 1) ->bool:

    if pos < 0 or pos >= HANDY_SLOT_COUNT or item_id < 0 or num <= 0:
        return false

    #物品栏按格子管理：本格被别的物品占着就不收
    if handy_items_pos.has(pos) and handy_items_pos[pos] != item_id:
        return false

    handy_items_pos[pos] = item_id
    handy_items[pos] = get_handy_slot_count(pos) + num

    inventory_update.emit()

    return true

##减少物品栏某格的数量，减完就清掉该格
func remove_handy_slot(pos:int,num:int = 1) ->void:

    if !handy_items_pos.has(pos):
        return

    num = mini(num,get_handy_slot_count(pos))

    handy_items[pos] -= num

    if handy_items[pos] <= 0:
        clear_handy_slot(pos) #拿完了，本格空出来
        return

    inventory_update.emit()

##清空物品栏某格
func clear_handy_slot(pos:int) ->void:

    if !handy_items_pos.has(pos) and !handy_items.has(pos):
        return

    handy_items_pos.erase(pos)
    handy_items.erase(pos)

    inventory_update.emit()

##交换快捷栏两个格子。
##from_pos是手上那份物品原来所在的格子，item_id/num就是手上那份：
func swap_handy_slot(from_pos:int,to_pos:int,item_id:int,num:int = 1) ->void:

    if from_pos < 0 or to_pos < 0 or from_pos == to_pos or item_id < 0 or num <= 0:
        return

    var to_id:int = get_handy_slot_id(to_pos)
    var to_count:int = get_handy_slot_count(to_pos)

    #原格那一堆 = 还留在格里的 + 手上拿着的
    var from_count:int = num
    if get_handy_slot_id(from_pos) == item_id:
        from_count += get_handy_slot_count(from_pos)

    #目标格的东西搬到原格
    if to_id < 0 or to_count <= 0:
        handy_items_pos.erase(from_pos)
        handy_items.erase(from_pos)
    else:
        handy_items_pos[from_pos] = to_id
        handy_items[from_pos] = to_count

    #原格那一堆搬到目标格
    handy_items_pos[to_pos] = item_id
    handy_items[to_pos] = from_count

    inventory_update.emit()

#////////////////////快捷移动
##快捷移动用的格子查找：先找已有的同种格子，没有同种再找空格，都满了返回-1
func find_handy_slot_for(item_id:int) ->int:

    for pos in HANDY_SLOT_COUNT:
        if get_handy_slot_id(pos) == item_id:
            return pos

    for pos in HANDY_SLOT_COUNT:
        if get_handy_slot_id(pos) < 0:
            return pos

    return -1

##快捷移动(shift+左键)：背包->物品栏(快捷栏)，整堆挪进一个格子，返回实际挪走的数量
func quick_move_to_handy(item_id:int,num:int = 1) ->int:

    var count:int = num
    var owned:int = get_count(item_id)

    if item_id < 0 or count <= 0 or owned <= 0:
        return 0

    if count > owned:
        count = owned #背包里没有这么多，只挪有的

    var pos:int = find_handy_slot_for(item_id)

    if pos < 0:
        return 0 #物品栏满了，整堆留在背包里

    add_handy_slot(pos,item_id,count)
    remove_item(item_id,count)

    return count

##快捷移动(shift+左键)：物品栏(快捷栏)->背包，整格挪回背包，返回实际挪走的数量
func quick_move_to_bag(pos:int) ->int:

    var item_id:int = get_handy_slot_id(pos)
    var count:int = get_handy_slot_count(pos)

    if item_id < 0 or count <= 0:
        return 0

    add_item(item_id,count)
    remove_handy_slot(pos,count)

    return count
#////////////////////////

#////////////////////附魔
##用药水给背包里的武器附魔。同一个 attribute_id 只有更高等级才会顶替，
##等级不够的整条忽略——低级药水不会让已经附魔过的武器回退。
##药水在拖拽开始时就已被拿掉一份，所以这里失败要把它还回背包。
func enchant_bag_weapon(weapon_item_id:int,potion_item_id:int) ->bool:

    if weapon_item_id < 0 or !has_items.has(weapon_item_id):
        return false

    var instance:WeaponData = _weapon_instance_for(get_item_template(weapon_item_id) as WeaponData)

    if instance == null:
        return false

    var potion:PotionData = get_item_template(potion_item_id) as PotionData
    var consumed:bool = _consume_enchant_potion(potion_item_id)
    var applied:Array[String] = _apply_enchant(instance,potion)

    if applied.is_empty():
        _return_enchant_potion(potion_item_id,consumed)
        return false

    #模板武器换成附魔实例：武器不可堆叠，只换走一份，剩下的同款留在原 id
    if instance.id != weapon_item_id:
        _swap_one_bag_item_id(weapon_item_id,instance.id)

    _finish_enchant(instance,applied,potion_item_id)

    return true

##用药水给物品栏(快捷栏)某一格里的武器附魔
func enchant_handy_weapon(pos:int,potion_item_id:int) ->bool:

    var weapon_item_id:int = get_handy_slot_id(pos)

    if weapon_item_id < 0:
        return false

    var instance:WeaponData = _weapon_instance_for(get_item_template(weapon_item_id) as WeaponData)

    if instance == null:
        return false

    var potion:PotionData = get_item_template(potion_item_id) as PotionData
    var consumed:bool = _consume_enchant_potion(potion_item_id)
    var applied:Array[String] = _apply_enchant(instance,potion)

    if applied.is_empty():
        _return_enchant_potion(potion_item_id,consumed)
        return false

    #模板武器换成附魔实例：本格换成实例，多出来的同款模板武器退回背包
    if instance.id != weapon_item_id:
        _swap_one_handy_item_id(pos,weapon_item_id,instance.id)

    _finish_enchant(instance,applied,potion_item_id)

    return true

##取这把武器的可附魔实例：模板要先复制成独立实例并登记运行时 id(400+)，
##已经是实例的直接用——它的武器定义本来就是本实例独有的一份，原地改就行。
func _weapon_instance_for(weapon_item:WeaponData) ->WeaponData:

    if weapon_item == null or weapon_item.weapon == null:
        return null

    var registry:Node = get_registry_node()

    if registry != null and registry.has_runtime_instance(weapon_item.id):
        return weapon_item

    var instance:WeaponData = weapon_item.duplicate() as WeaponData

    if instance == null:
        return null

    #附魔写在武器定义上，必须是本实例独有的一份，不能改共享模板
    instance.weapon = weapon_item.weapon.duplicate(true) as WeaponDefinition
    instance.id = WeaponData.next_instance_id()

    if registry != null:
        while !registry.register_instance(instance):
            instance.id = WeaponData.next_instance_id()

    return instance

##把药水的炼金属性逐条附上，返回真正生效的属性名
func _apply_enchant(instance:WeaponData,potion:PotionData) ->Array[String]:

    var applied:Array[String] = []

    if potion == null:
        return applied

    for attribute:AlchemicalData in potion.alchemical_attribute:

        if attribute != null and instance.weapon.add_enchant(attribute):
            applied.append(attribute.name)

    return applied

##附魔收尾：登记新实例、药水用完就注销它的运行时实例、通知 UI
func _finish_enchant(instance:WeaponData,applied:Array[String],potion_item_id:int) ->void:

    get_item_data[instance.id] = instance

    _drop_runtime_instance_if_gone(potion_item_id)

    inventory_update.emit()

    _notify("附魔成功：%s + %s" % [instance.name,"、".join(applied)])

##附魔要消耗一份药水。拖拽路径上药水已经被拿走了(背包里没有)，直接调用时还在背包里，
##所以这里统一扣：扣到了返回 true，附魔失败时要还回去。
func _consume_enchant_potion(potion_item_id:int) ->bool:

    if get_count(potion_item_id) > 0:
        remove_item(potion_item_id,1)
        return true

    return false

##附魔没生效：把刚才扣掉的那份药水放回背包
func _return_enchant_potion(potion_item_id:int,consumed:bool) ->void:

    if consumed:
        add_item(potion_item_id,1)

    _notify("附魔失败：药水没有能上武器的属性(属性没开武器附魔，或等级不高于已有的同类附魔)")

##背包里某种物品只换走一份(模板武器 -> 附魔实例)。
##武器是不可堆叠的独立实例：同 id 堆叠时只迁移一份，剩下的还留在原 id 里，
##否则一瓶药水会把整堆武器都变成同一个实例、数量也一起搬过去。
func _swap_one_bag_item_id(old_id:int,new_id:int) ->void:

    if get_count(old_id) <= 0:
        return

    remove_item(old_id,1)

    items[new_id] = 1

    if !has_items.has(new_id):
        has_items.append(new_id)

    get_item_data[new_id] = get_item_template(new_id)

##物品栏某一格的物品只换走一份(模板武器 -> 附魔实例)。
##本格留给附魔实例(数量 1)，多出来的同款模板武器退回背包：物品栏一格只能装一种 id。
func _swap_one_handy_item_id(pos:int,old_id:int,new_id:int) ->void:

    if get_handy_slot_id(pos) != old_id:
        return

    var leftover:int = get_handy_slot_count(pos) - 1

    handy_items_pos[pos] = new_id
    handy_items[pos] = 1

    get_item_data[new_id] = get_item_template(new_id)

    if leftover > 0:
        add_item(old_id,leftover)

##事件总线：UI 提示用。取不到就安静跳过，--script 测试里没有 HUD 也不会炸
func _notify(message:String) ->void:

    var loop:MainLoop = Engine.get_main_loop()

    if !(loop is SceneTree):
        return

    var tree:SceneTree = loop as SceneTree

    if tree.root == null:
        return

    var bus:Node = tree.root.get_node_or_null("EventBus")

    if bus != null and bus.has_signal("notification"):
        bus.emit_signal("notification",message)