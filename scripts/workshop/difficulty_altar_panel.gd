class_name DifficultyAltarPanel
extends WorkshopPanel

## 难度祭坛：只做基础 3 档；自定义修饰接口预留。

func _build_content(parent: VBoxContainer) -> void:
	set_titles("难度祭坛", "通关一次解锁下一档")
	_build_rows(parent)


func _build_rows(parent: VBoxContainer) -> void:
	for tier: int in DifficultyTier.COUNT:
		var unlocked: bool = DifficultyTier.is_unlocked(tier, manager.state.clears)
		var current: bool = manager.difficulty_tier == tier
		var description: String = "%s（%.1fx）　%s" % [
			DifficultyTier.name_of(tier), DifficultyTier.multiplier(tier), DifficultyTier.description_of(tier),
		]
		if not unlocked:
			description += "　（未解锁）"
		var button_text: String = "已选择" if current else "选择"
		var row: HBoxContainer = make_row(description, button_text, _on_select.bind(tier), unlocked and not current)
		parent.add_child(row)
	parent.add_child(make_info_row("自定义修饰", "接口预留", Color(0.62, 0.66, 0.74)))


func _on_select(tier: int) -> void:
	if manager.set_difficulty(tier):
		play_sfx(&"ui_toggle")
	else:
		play_sfx(&"brew_reject")
	refresh()


func refresh() -> void:
	if _content == null:
		return
	clear_content()
	set_titles("难度祭坛", "当前：%s（%.1fx）　通关次数 %d" % [
		DifficultyTier.name_of(manager.difficulty_tier),
		DifficultyTier.multiplier(manager.difficulty_tier),
		manager.state.clears,
	])
	_build_rows(_content)
