extends Resource

class_name Inventory
##背包数据资源，只用于存储背包数据

signal inventory_update

@export var has_items:Array[int]
##物品id和数量的字典
@export var items:Dictionary[int,int]

##物品栏物品id及所在格子位置0-8
@export var handy_items_pos:Dictionary[int,int]
##物品栏物品id和数量的字典
@export var handy_items:Dictionary[int,int]


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
        items[item_id] = num #没有该物品

    else:
        items[item_id] += num

    inventory_update.emit()

##返回背包内对应物品数量，没有返回0
func get_count(item_id:int) ->int:
    if !has_items.has(item_id):
        return 0
    return items[item_id]

##移除物品栏物品函数，item_id为物品id
func remove_handy_item(item_id:int,num:int = 1) ->void:

    if !has_items.has(item_id):return #没有该物品，退出函数

    items[item_id] -= num

    if items[item_id] <= 0:
        has_items.erase(item_id)
        items.erase(item_id) #全部拿完，背包中失去该物品
        handy_items.erase(item_id) #物品栏里也一起清掉
        handy_items_pos.erase(item_id) #格子位置一并释放
    else:
        _sync_handy_count(item_id) #物品栏数量跟随背包数量

    inventory_update.emit()

##增加物品栏物品函数，item_id为物品id
func add_handy_item(item_id:int,num:int)->void:

    if !has_items.has(item_id):
        has_items.append(item_id)
        items[item_id] = num #没有该物品

    else:
        items[item_id] += num

    handy_items[item_id] = items[item_id] #物品栏数量跟随背包数量

    inventory_update.emit()

##返回物品栏内对应物品数量，没有返回0
func get_handy_count(item_id:int) ->int:
    if !handy_items.has(item_id):
        return 0
    return handy_items[item_id]

##物品栏数量与背包数量保持一致，物品栏里没登记过的id不新建
func _sync_handy_count(item_id:int) ->void:
    if handy_items.has(item_id):
        handy_items[item_id] = items[item_id]
