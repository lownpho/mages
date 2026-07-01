extends Node
## Headless test for Group D trails (biome-scale connectivity). Pure logic.
##   godot --headless --path game world_gen/tests/test_trails.tscn
## Over ~50 seeds: flood-fill (4-connected) over is_trail tiles from the spawn biome centre and
## assert every biome centre is reached (one connected trail network); is_trail stable across
## calls and identical on re-setup; every biome centre is itself on a trail. Plus one graph with
## a forced corridor_edge (a non-embeddable star) to prove the backstop corridor still connects.

const GRAPH_PATH := "res://world_gen/content/world_graph.tres"

const SEEDS := 50
const FLOOD_BUDGET := 2_000_000   # generous cap so the fill always terminates (corridors ~1500 long)


func _ready() -> void:
	var fails: Array[String] = []
	var graph: WorldGraph = load(GRAPH_PATH)
	if graph == null:
		_report(["could not load " + GRAPH_PATH])
		return

	var n_nodes := graph.nodes.size()
	var total_flooded := 0

	for s in SEEDS:
		var seed := 2000 + s * 6301
		var macro = MacroMap.new()
		macro.setup(seed, graph)

		# 1. Every biome centre is itself on a trail (so portals placed there are reachable).
		var centers: Dictionary = macro.biome_centers()
		for i in n_nodes:
			if not macro.is_trail(centers[i]):
				fails.append("seed %d: biome centre %d not on a trail" % [seed, i])

		# 2. Flood-fill over trail tiles from spawn centre; every biome centre must be reached.
		var visited := _flood(macro, centers[graph.start_index])
		total_flooded += visited.size()
		if visited.size() >= FLOOD_BUDGET:
			fails.append("seed %d: flood hit budget (%d) — trails may be unbounded" % [seed, visited.size()])
		for i in n_nodes:
			if not visited.has(centers[i]):
				fails.append("seed %d: biome centre %d not reached by trail flood" % [seed, i])

		# 3. is_trail stable across calls and identical on re-setup with the same seed.
		var macro2 = MacroMap.new()
		macro2.setup(seed, graph)
		for t in _sample_tiles(centers[graph.start_index]):
			var v := macro.is_trail(t)
			if v != macro.is_trail(t):
				fails.append("seed %d: is_trail not stable at %s" % [seed, t])
			if v != macro2.is_trail(t):
				fails.append("seed %d: is_trail differs on re-setup at %s" % [seed, t])

		if fails.size() > 20:
			break

	print("seeds: %d   avg trail tiles flooded: %d" % [SEEDS, total_flooded / maxi(1, SEEDS)])

	# 4. Forced corridor_edge: a 6-node star is non-embeddable (centre degree 5), so Group C
	#    records corridors. The trail network must still connect every centre from spawn.
	var star := _star_graph(6)
	var macro3 = MacroMap.new()
	macro3.setup(4242, star)
	var corridors: Array[Vector2i] = macro3.corridor_edges()
	print("star-graph corridor edges: %d" % corridors.size())
	if corridors.is_empty():
		fails.append("star graph produced no corridor edges — cannot test corridor connectivity")
	else:
		var star_centers: Dictionary = macro3.biome_centers()
		var reached := _flood(macro3, star_centers[star.start_index])
		for i in star.nodes.size():
			if not reached.has(star_centers[i]):
				fails.append("star: centre %d not reached through corridor network" % i)

	_report(fails)


func _report(fails: Array[String]) -> void:
	print("RESULT: ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	get_tree().quit(1 if not fails.is_empty() else 0)


# 4-connected flood over is_trail tiles, bounded to in_world and a tile budget.
func _flood(macro, start: Vector2i) -> Dictionary:
	var visited := {}
	if not macro.is_trail(start):
		return visited
	var stack: Array[Vector2i] = [start]
	visited[start] = true
	const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty() and visited.size() < FLOOD_BUDGET:
		var t: Vector2i = stack.pop_back()
		for d in DIRS:
			var n: Vector2i = t + d
			if not visited.has(n) and macro.in_world(n) and macro.is_trail(n):
				visited[n] = true
				stack.append(n)
	return visited


# Tiles near the spawn centre (mix of on/off trail) to compare is_trail between runs.
func _sample_tiles(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [center]
	for dy in range(-40, 41, 8):
		for dx in range(-40, 41, 8):
			out.append(center + Vector2i(dx, dy))
	return out


# n-node star: node 0 connected to every other node — non-embeddable once degree > 4, so the
# embedding records corridor_edges the trail network must still connect.
func _star_graph(n: int) -> WorldGraph:
	var biome: Resource = load("res://world_gen/content/biomes/glade.tres")
	var g := WorldGraph.new()
	for i in n:
		var node := BiomeNode.new()
		node.biome = biome
		g.nodes.append(node)
	for i in range(1, n):
		g.edges.append(Vector2i(0, i))
	g.start_index = 0
	return g
