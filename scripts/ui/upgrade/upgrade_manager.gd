class_name UpgradeManager
extends Node

## 升级流程的中介：监听 RunProgress 的升级事件，驱动三选一面板，并把选卡结果落到玩家身上。
##
## 单独成节点是为了让面板保持纯 UI，抽卡与状态留在 RunProgress。

var _panel: UpgradePanel = null
var _player: PlayerCharacter = null


func _ready() -> void:
	_panel = get_parent().get_node_or_null("UpgradePanel") as UpgradePanel
	if _panel != null:
		_panel.card_chosen.connect(_on_card_chosen)
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as PlayerCharacter
	var progress: Node = get_node_or_null("/root/RunProgress")
	if progress == null:
		return
	if not progress.level_up.is_connected(_on_level_up):
		progress.level_up.connect(_on_level_up)
	if not progress.cards_changed.is_connected(_on_cards_changed):
		progress.cards_changed.connect(_on_cards_changed)
	_offer_next()


## 选卡后把成长重新落到玩家身上（生命上限、移速、武器）。
func _on_cards_changed() -> void:
	if _player != null:
		_player.apply_progress(false)


func _on_level_up(_level: int) -> void:
	# 等级本身也带成长(生命上限/武器伤害/药水效果)：先把新的生命上限落到生命组件上，
	# 再抽卡，否则选卡之前血条上限不会跟着涨。
	# 武器伤害/药水效果是每次结算时读聚合值，不用重造武器（重造会打断正在挥的这一刀）。
	if _player != null:
		_player.apply_progress(false, false)
	_offer_next()


## 调试改造后重新抽取正在展示的选项，避免残留已满层或互斥的卡。
func refresh_pending_choices() -> void:
	var progress: Node = get_node_or_null("/root/RunProgress")
	if _panel == null or not _panel.visible or progress == null:
		return
	var previous_pity: int = progress.rolls_since_rare
	_offer_next()
	progress.rolls_since_rare = previous_pity


func _offer_next() -> void:
	if _panel == null:
		return
	var progress: Node = get_node_or_null("/root/RunProgress")
	if progress == null or progress.pending_choices <= 0:
		return
	var cards: Array[UpgradeCard] = progress.roll_choices(_current_weapon_id(), _health_ratio())
	_panel.show_choices(cards, progress.level)


func _on_card_chosen(card_id: StringName) -> void:
	var progress: Node = get_node_or_null("/root/RunProgress")
	if progress == null:
		return
	if not progress.take_card(card_id):
		return
	if progress.pending_choices > 0:
		_offer_next()
		return
	if _panel != null:
		_panel.visible = false
	get_tree().paused = false


func _current_weapon_id() -> StringName:
	if _player == null:
		return &""
	var weapon: WeaponDefinition = _player.weapon_controller.equipped_weapon
	return weapon.id if weapon != null else &""


func _health_ratio() -> float:
	if _player == null or _player.max_health <= 0.0:
		return 1.0
	return clampf(_player.health / _player.max_health, 0.0, 1.0)
