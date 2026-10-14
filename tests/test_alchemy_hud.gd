extends SceneTree

## 完整炼金台 UI：页签切换、图鉴完成度与占位、预设行状态、暂停与恢复。

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var station: AlchemyStation = AlchemyStation.new()
	station.preset_slots = 2
	root.add_child(station)
	var hud: AlchemyHud = (load("res://scenes/ui/alchemy/alchemy_hud.tscn") as PackedScene).instantiate() as AlchemyHud
	root.add_child(hud)
	hud.bind(station)

	station.in_combat = false
	station.press_brew()
	await process_frame
	await process_frame
	_check(station.is_menu_open(), "非战斗按 E 打开完整炼金台")
	_check(paused, "打开后世界暂停")
	_check(hud._tab_buttons.size() == 5, "五个页签：背包 / 图鉴 / 预设 / 实验 / 合金")
	_check(hud._tab == AlchemyHud.Tab.BAG, "默认停在背包页")
	_check(hud._bag_page.visible and not hud._compendium_page.visible, "背包页可见")

	hud.cycle_tab()
	_check(hud._tab == AlchemyHud.Tab.COMPENDIUM, "Tab 切到图鉴页")
	_check(not hud._bag_page.visible and hud._compendium_page.visible, "图鉴页可见")
	await process_frame
	await process_frame
	_check(hud._compendium_summary_label.text.contains("完成度"), "图鉴显示完成度百分比")
	_check(hud._compendium_list_label.text.contains("？？？"), "未发现条目显示「？？？」")
	_check(hud._compendium_list_label.text.contains("【元素】"), "图鉴按类别分栏")
	_check(hud._compendium_list_label.text.contains("【反应】"), "图鉴含反应栏")

	hud.cycle_tab()
	_check(hud._tab == AlchemyHud.Tab.PRESET, "Tab 切到预设页")
	await process_frame
	await process_frame
	_check(hud._preset_status_labels.size() == 2, "预设行数等于预设格数")
	_check(hud._preset_status_labels[0].text == "（空）", "空预设显示「（空）」")

	# 存入一个预设后显示材料名与就绪状态。
	station.absorb_material(1002, 2)
	station.absorb_material(1001, 2)
	station.clear_slots()
	station.fill_first_free_slot(1002)
	station.fill_first_free_slot(1001)
	_check(station.save_preset(0), "存入预设")
	await process_frame
	await process_frame
	_check(hud._preset_status_labels[0].text.contains("硝石"), "预设显示材料名")
	_check(hud._preset_status_labels[0].text.contains("就绪"), "预设显示就绪")

	hud.cycle_tab()
	_check(hud._tab == AlchemyHud.Tab.EXPERIMENT, "Tab 切到实验页")
	_check(not hud._preset_page.visible and hud._experiment_page.visible, "实验页可见")
	await process_frame
	await process_frame
	_check(hud._experiment_summary_label.text.contains("实验解锁"), "实验页显示解锁进度")
	_check(hud._experiment_list_label.text.contains("？？？"), "未解锁实验显示「？？？」")
	_check(hud._experiment_list_label.text.contains("毒沼"), "未解锁实验显示产地提示")

	hud.cycle_tab()
	_check(hud._tab == AlchemyHud.Tab.FORGE, "Tab 切到合金页")
	_check(not hud._experiment_page.visible and hud._forge_page.visible, "合金页可见")
	await process_frame
	await process_frame
	_check(hud._forge_summary_label.text.contains("合金"), "合金页显示合金状态")
	_check(hud._forge_list_label.text.contains("重铸"), "合金页显示重铸状态")
	_check(hud._forge_material_grid.get_child_count() > 0, "合金页列出背包材料")

	# 诅咒炼金：背包页的诅咒行列出全部诅咒，选中后显示收益 / 代价。
	_check(hud._curse_row != null, "背包页构建了诅咒行")
	_check(hud._curse_row.get_child_count() == AlchemyCurses.CURSES.size() + 1, "诅咒行 = 不诅咒 + 全部诅咒")
	_check(hud._curse_label.text.contains("诅咒：无"), "默认没有诅咒")
	hud._on_curse_pressed(&"frenzy")
	await process_frame
	await process_frame
	_check(hud._curse_label.text.contains("狂乱"), "选中诅咒后显示名字")
	_check(hud._curse_label.text.contains("热量 +30"), "选中诅咒后显示代价")
	hud._on_curse_pressed(&"")
	await process_frame
	await process_frame
	_check(hud._curse_label.text.contains("诅咒：无"), "取消后回到无诅咒")

	hud.cycle_tab()
	_check(hud._tab == AlchemyHud.Tab.BAG, "Tab 循环回背包页")

	# 炼金后图鉴完成度上升。
	var before: float = station.compendium.completion_ratio()
	station.brew_from_slots()
	await process_frame
	await process_frame
	_check(station.compendium.completion_ratio() > before, "炼金后图鉴完成度上升")

	# 过热警告表现：抖动幅度分级 + 过载红闪 / 耳鸣。
	_check(hud._overload_flash != null, "构建了过载红闪层")
	_check(hud._warning_player.stream != null and hud._tinnitus_player.stream != null, "构建了警告音与耳鸣音")
	_check(hud._shake_amplitude(0) == 0.0, "无警告不抖动")
	_check(hud._shake_amplitude(1) < hud._shake_amplitude(2), "黄色抖动小于橙色")
	_check(hud._shake_amplitude(2) < hud._shake_amplitude(3), "橙色抖动小于红色")

	# 炼金已积了热量，先清零再分级验证。
	station.session.heat.reset()
	station.session.heat.add_heat(60.0)
	await process_frame
	_check(station.warning_level() == 1, "热量 60 进入黄色警告")
	station.session.heat.add_heat(35.0)
	await process_frame
	_check(station.warning_level() == 3, "热量 95 进入红色警告")
	var moved: bool = false
	for _frame: int in range(6):
		await process_frame
		if absf(hud._status_panel.offset_left - AlchemyHud.STATUS_X) > 0.05 \
				or absf(hud._status_panel.offset_top - AlchemyHud.STATUS_Y) > 0.05:
			moved = true
	_check(moved, "红色警告时状态条抖动")

	station.session.heat.add_heat(AlchemyRules.HEAT_MAX)
	_check(hud._flash_remaining > 0.0, "过载触发屏幕红闪")
	await process_frame
	_check(hud._overload_flash.color.a > 0.0, "红闪有可见透明度")

	# 短按 E 失败反馈：提示条显示原因并在 TOAST_SECONDS 后自动消失。
	_check(hud._toast_label != null, "构建了短按失败提示条")
	_check(hud._toast_label.text == "", "初始无提示文本")
	station.brew_rejected.emit("材料不足，无法复用配方")
	_check(hud._toast_label.text == "材料不足，无法复用配方", "失败时提示条显示原因")
	_check(hud._toast_remaining > 0.0, "提示开始倒计时")
	hud._toast_remaining = 0.01
	await process_frame
	await process_frame
	_check(hud._toast_label.text == "", "提示到时自动清空")

	# 实验页：用当前素材槽做实验，成功或事故都会给出提示。
	station.absorb_material(1002, 2)
	station.absorb_material(1001, 2)
	station.clear_slots()
	station.fill_first_free_slot(1002)
	station.fill_first_free_slot(1001)
	hud._on_experiment_pressed()
	_check(hud._toast_label.text.contains("实验"), "实验给出成功或事故提示")

	# 武器炼金槽：合金页显示槽位状态，按钮把当前素材槽熔成永久槽。
	hud._tab = AlchemyHud.Tab.FORGE
	hud._apply_tab_visibility()
	await process_frame
	_check(hud._forge_slot_label.text.contains("临时槽"), "合金页显示武器临时槽状态")
	_check(hud._forge_slot_label.text.contains("永久槽：空"), "合金页提示永久槽为空")
	station.clear_slots()
	station.absorb_material(1006, 3)
	station.fill_first_free_slot(1006)
	hud._on_permanent_slot_pressed()
	await process_frame
	await process_frame
	_check(station.weapon_slots.permanent_count() == 1, "合金页按钮熔出一个永久槽")
	_check(hud._forge_slot_label.text.contains("永久槽：") and not hud._forge_slot_label.text.contains("永久槽：空"), "合金页显示永久槽内容")
	_check(hud._toast_label.text.contains("永久槽 +1"), "熔出永久槽后弹 Toast")

	_check(station.cancel(), "Esc 关闭炼金台")
	await process_frame
	await process_frame
	_check(not station.is_menu_open() and not paused, "关闭后世界恢复")

	# 战斗轮盘：素材槽 / 词条池 / 预览（含叠加与替换提示）/ 当前生效 / 热量条。
	station.in_combat = true
	# 前面的过热断言把热量打满了，先清零，否则炼金会被过热锁定拒绝。
	station.session.heat.reset()
	station.absorb_material(1002, 2)
	station.absorb_material(1001, 2)
	station.clear_slots()
	station.fill_first_free_slot(1002)
	station.fill_first_free_slot(1001)
	station.press_brew()
	station.input_state.charge_time = AlchemyRules.LONG_PRESS_SECONDS
	station.input_state.tick(0.0)
	await process_frame
	await process_frame
	_check(station.is_wheel_open(), "战斗中长按 E 打开轮盘")
	_check(hud._wheel.visible, "轮盘可见")
	_check(hud._wheel_slot_buttons.size() == station.slots.slot_count(), "轮盘列出全部素材槽")
	_check(hud._wheel_slot_buttons[0].text.contains("硝石"), "轮盘素材槽显示材料名")
	_check(hud._wheel_pool_label.text.contains("词条池"), "轮盘显示词条池")
	_check(hud._wheel_preview_label.text.contains("预览"), "轮盘显示预览")
	_check(hud._wheel_preview_label.text.contains("替换旧效果"), "轮盘提示不同组合会替换")
	_check(hud._wheel_active_label.text.contains("当前："), "轮盘显示当前生效")
	_check(hud._wheel_heat_bar.max_value == 1.0, "轮盘热量条按比例显示")
	station.brew_from_slots()
	await process_frame
	await process_frame
	_check(hud._wheel_preview_label.text.contains("时间叠加"), "同组合时轮盘提示时间叠加")
	station.input_state.close()
	await process_frame
	_check(not station.is_wheel_open(), "松开 E 关闭轮盘")
	station.in_combat = false

	Engine.time_scale = 1.0
	paused = false
	station.free()
	hud.free()
	print("ALCHEMY HUD: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
