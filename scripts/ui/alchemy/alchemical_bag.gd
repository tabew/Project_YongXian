extends BagUI

##炼金台里那块背包：显隐由炼金台自己管（Tab 不再单独开关它），
##shift+左键也不往快捷栏挪。除此之外和普通背包一样——
##显示/收格子的逻辑都在 BagUI 里，别在这里把 _refresh_slot 覆盖掉，
##否则炼金台背包会把已经用掉的药水一直留在格子里。

func _input(_event: InputEvent) -> void:
	pass

func _on_slot_quick_move(_item_id:int,_num:int) ->void:
	return
