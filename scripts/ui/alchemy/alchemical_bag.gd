extends BagUI

func _input(event: InputEvent) -> void:
    pass

func _on_slot_quick_move(item_id:int,num:int) ->void:
    return

##背包里某种物品的数量变了就同步显示，整堆拿完就把格子收掉
func _refresh_slot(item_id:int) ->void:
    return