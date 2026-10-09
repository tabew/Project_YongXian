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
	var compact_size: Vector2i = minimap._image.get_size()
	if compact_size != Vector2i(80, 80):
		push_error("Compact minimap resolution changed: %s" % compact_size)
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

	minimap.set_expanded(false)
	if minimap._image.get_size() != Vector2i(80, 80):
		push_error("Compact minimap was not restored after closing the full map")
		get_tree().quit(1)
		return

	print("MINIMAP_MODE_TEST_PASSED compact=", compact_size, " full=", full_size)
	get_tree().quit(0)
