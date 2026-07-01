extends Node
const GRAPH_PATH := "res://world_gen/content/world_graph.tres"
func _ready() -> void:
	var graph: WorldGraph = load(GRAPH_PATH)
	for world_seed in [7, 101, 5551, 90210]:
		var macro := MacroMap.new()
		macro.setup(world_seed, graph)
		var count := 0
		var first := Vector2i.ZERO
		# scan a wide band; find tiles both is_trail and is_world_edge
		for y in range(-3000, 3000, 1):
			for x in range(-3000, 3000, 1):
				var t := Vector2i(x, y)
				if macro.is_world_edge(t) and macro.is_trail(t):
					if count == 0: first = t
					count += 1
			if count > 0 and y % 500 == 0:
				pass
		print("seed %d: edge&trail tiles = %d first=%s" % [world_seed, count, first])
	get_tree().quit()
