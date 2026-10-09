extends Resource

class_name Inventory
##背包数据资源，只用于存储背包数据

signal inventory_update

@export var has_items:Array[ItemData]
##物品和数量的字典
@export var items:Dictionary[ItemData,int]

##移除物品函数
func remove_item(item:ItemData,num:int = 1) ->void:

    if !has_items.has(item):return #没有该物品，退出函数

    items[item] -= num

    if items[item] <= 0:
        has_items.erase(item)
        items.erase(item) #全部拿完，背包中失去该物品

    inventory_update.emit()

##增加物品函数
func add_item(item:ItemData,num:int)->void:

    if !has_items.has(item):
        has_items.append(item)
        items[item] = num #没有该物品

    else:
        items[item] += num

    inventory_update.emit()

##返回背包内对应物品数量，没有返回0
func get_count(item:ItemData) ->int:
    if !items.has(item):
        return 0
    return items[item]
    
