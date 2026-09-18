extends Node
## Regression: the Map must cover the warped floor Rooms own past the planned macro grid, where
## the World still renders and the player can walk. Run:
##   godot --headless --path game res://tests/generation/test_map_edges.tscn

var fails: Array[String] = []


func _ready() -> void:
	for seed in WorldFixture.shipped().seeds:
		_check_seed(seed)
	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for failure in fails:
			print("  FAIL: ", failure)
	get_tree().quit(0 if fails.is_empty() else 1)


func _check_seed(seed: int) -> void:
	var graph: WorldGraph = WorldFixture.shipped().graph(seed)
	var interiors := WorldFixture.interiors(graph)
	var inside := Rect2i(Vector2i.ZERO, graph.plan.size * WorldPlan.CELL)
	var found := 0
	for y in range(inside.position.y, inside.end.y + WorldPlan.CELL):
		for x in range(inside.position.x, inside.end.x + WorldPlan.CELL):
			var tile := Vector2i(x, y)
			if inside.has_point(tile) or interiors.class_at(tile) != WorldInteriors.FLOOR:
				continue
			var room := graph.owner_at(tile)
			if room == null:
				continue
			var state := MapState.new()
			state.setup(graph, interiors)
			state.discover_at(graph.tile_of(room.seed_point))
			var coord := Vector2i(floori(float(tile.x) / WorldPlan.CELL), floori(float(tile.y) / WorldPlan.CELL))
			var image := state.macro_image(coord)
			if image == null:
				_check(false, "seed %d: no macro image for edge cell %s holding owned floor %s" % [seed, coord, tile])
				return
			var painted := image.floor_image.get_pixelv(tile - image.rect.position).a > 0.0
			_check(painted, "seed %d: edge floor %s is missing from the Map" % [seed, tile])
			var covered := state.images_in(Rect2(Vector2(tile), Vector2.ONE), 1).any(
					func(layer: Dictionary) -> bool: return Rect2(layer.world_rect).has_point(Vector2(tile)))
			_check(covered, "seed %d: the Map view doesn't request the edge cell holding %s" % [seed, tile])
			found += 1
			if found >= 3:
				return
	_check(found > 0, "seed %d: fixture has floor past the planned grid" % seed)


func _check(condition: bool, message: String) -> void:
	if not condition:
		fails.append(message)