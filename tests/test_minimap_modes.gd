extends Node

class FakeChunkManager extends ChunkManager:
	var test_chunks: Dictionary = {}

	func loaded_chunks() -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		for coords: Vector2i in test_chunks.keys():
			result.append(coords)
		return result

	func get_cached_chunk(coords: Vector2i) -> ChunkData:
		return test_chunks.get(coords)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var generator := WorldGenerator.new(13579)
	var manager := FakeChunkManager.new()
	var player := Node2D.new()
	var minimap := Minimap.new()
	minimap.size = Vector2(164, 164)
	get_tree().root.add_child(manager)
	get_tree().root.add_child(player)
	get_tree().root.add_child(minimap)

	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var coords := Vector2i(x, y)
			manager.test_chunks[coords] = generator.generate_chunk(coords)

	minimap.bind(manager, player)
	# 快照按帧预算推进：多跑几次把这批区块补齐。
	for _step: int in 12:
		minimap._capture_loaded_chunks()
	minimap._rebuild()
	var compact_size: Vector2i = minimap._image.get_size()
	if compact_size != Vector2i(128, 128):
		push_error("Compact minimap resolution changed: %s" % compact_size)
		get_tree().quit(1)
		return
	# 没探索过的区块必须留迷雾：小地图不提前泄露远处地图。
	var explored_pixel: Color = minimap._image.get_pixel(64, 64)
	var unknown := Color(
		float(minimap._unknown_rgb[0]) / 255.0,
		float(minimap._unknown_rgb[1]) / 255.0,
		float(minimap._unknown_rgb[2]) / 255.0
	)
	if explored_pixel.is_equal_approx(unknown):
		push_error("Explored centre of the compact map is still fogged")
		get_tree().quit(1)
		return
	var fogged: bool = false
	for probe: int in [4, 12, 120, 124]:
		for other: int in [4, 12, 120, 124]:
			if minimap._image.get_pixel(probe, other).is_equal_approx(unknown):
				fogged = true
	if not fogged:
		push_error("Compact minimap shows unexplored terrain")
		get_tree().quit(1)
		return

	minimap.set_expanded(true)
	var full_size: Vector2i = minimap._image.get_size()
	if full_size.x < 480 or full_size.y < 224:
		push_error("Full map does not cover at least 15x7 detailed chunks: %s" % full_size)
		get_tree().quit(1)
		return
	if minimap._active_tiles_per_pixel != 1:
		push_error("Full map is not using one tile per pixel")
		get_tree().quit(1)
		return

	# 滚轮缩放：放大后地图矩形要变大，且光标下的点保持不动。
	var fitted: Rect2 = minimap._calculate_map_rect()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = fitted.get_center()
	minimap._gui_input(wheel)
	var zoomed: Rect2 = minimap._calculate_map_rect()
	if minimap._zoom <= 1.0 or zoomed.size.x <= fitted.size.x:
		push_error("Mouse wheel did not zoom the full map in")
		get_tree().quit(1)
		return
	if not zoomed.has_point(fitted.get_center()):
		push_error("Zoom did not keep the cursor anchor in view")
		get_tree().quit(1)
		return

	# 中键拖动：按住中键移动要平移地图。
	var drag := InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_MIDDLE
	drag.pressed = true
	drag.position = zoomed.get_center()
	minimap._gui_input(drag)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40.0, 0.0)
	motion.position = drag.position + motion.relative
	minimap._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	release.pressed = false
	minimap._gui_input(release)
	var panned: Rect2 = minimap._calculate_map_rect()
	if not panned.position.x > zoomed.position.x:
		push_error("Middle drag did not pan the full map")
		get_tree().quit(1)
		return
	# 拖动越界要被夹住，不能把地图拖出画面。
	motion.relative = Vector2(100000.0, 0.0)
	minimap._gui_input(motion)
	if minimap._pan.length() > minimap._fitted_map_rect().size.length():
		push_error("Pan is not clamped to the map bounds")
		get_tree().quit(1)
		return

	# 收起再展开应回到整局适配。
	minimap.set_expanded(false)
	if not is_equal_approx(minimap._zoom, 1.0) or not minimap._pan.is_zero_approx():
		push_error("Zoom and pan were not reset when closing the full map")
		get_tree().quit(1)
		return
	minimap.set_expanded(true)
	minimap.set_expanded(false)
	if minimap._image.get_size() != Vector2i(128, 128):
		push_error("Compact minimap was not restored after closing the full map")
		get_tree().quit(1)
		return

	print(
		"MINIMAP_MODE_TEST_PASSED compact=", compact_size, " full=", full_size,
		" zoom=", minimap._zoom, " pan=", minimap._pan
	)
	get_tree().quit(0)
