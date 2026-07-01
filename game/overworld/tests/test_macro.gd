extends Node
## Headless test for Group C macro layout (Embedding + MacroMap biome half). Pure logic.
##   godot --headless --path game overworld/tests/test_macro.tscn
## Verifies, over ~50 seeds: one region per biome, every authored edge realized (adjacent cell
## or recorded corridor), biome_at stable + identical on re-setup, off-hull → null/not-in-world;
## plus the embeddability policy fires on a deliberately non-embeddable graph.

const GRAPH_PATH := "res://overworld/world_graph.tres"

const SEEDS := 50


func _ready() -> void:
	var fails: Array[String] = []
	var graph: WorldGraph = load(GRAPH_PATH)
	if graph == null:
		_report(["could not load " + GRAPH_PATH])
		return
	var errs := graph.validate()
	if not errs.is_empty():
		fails.append("authored graph invalid: " + str(errs))

	var n_nodes := graph.nodes.size()
	var sample_tiles := _sample_tiles()
	var corridor_total := 0

	for s in SEEDS:
		var seed := 1000 + s * 7919
		var macro = MacroMap.new()
		macro.setup(seed, graph)

		# 1. Each biome appears exactly once, and its centre lies in its own region.
		var seen_ids := {}
		for i in n_nodes:
			var center: Vector2i = macro.biome_center(i)
			var b: Resource = macro.biome_at(center)
			var own: Resource = graph.nodes[i].biome
			if b != own:
				fails.append("seed %d: node %d centre not in its own biome" % [seed, i])
			var id = own.id
			if seen_ids.has(id):
				fails.append("seed %d: biome '%s' appears more than once" % [seed, id])
			seen_ids[id] = true
		if seen_ids.size() != n_nodes:
			fails.append("seed %d: %d biomes seen, expected %d" % [seed, seen_ids.size(), n_nodes])

		# 2. Every authored edge = adjacent cells, or recorded as a corridor.
		var corridors: Array[Vector2i] = macro.corridor_edges()
		corridor_total += corridors.size()
		for e in graph.edges:
			var ca: Vector2i = macro.node_cell(e.x)
			var cb: Vector2i = macro.node_cell(e.y)
			var adjacent := (absi(ca.x - cb.x) + absi(ca.y - cb.y)) == 1
			var recorded := corridors.has(Vector2i(e.x, e.y)) or corridors.has(Vector2i(e.y, e.x))
			if not adjacent and not recorded:
				fails.append("seed %d: edge %s neither adjacent nor corridor" % [seed, e])

		# 3. biome_at stable across repeated calls, and identical on re-setup with same seed.
		var macro2 = MacroMap.new()
		macro2.setup(seed, graph)
		for t in sample_tiles:
			var a1 = macro.biome_at(t)
			if a1 != macro.biome_at(t):
				fails.append("seed %d: biome_at not stable at %s" % [seed, t])
			if a1 != macro2.biome_at(t):
				fails.append("seed %d: biome_at differs on re-setup at %s" % [seed, t])

		# 4. Off-hull tile → null biome and not in_world.
		var far := Vector2i(MacroMap.CELL * 40, MacroMap.CELL * 40)
		if macro.biome_at(far) != null or macro.in_world(far):
			fails.append("seed %d: far tile is in_world" % seed)

		# 5. is_world_edge: a biome centre is deep interior (not edge); the last in-world tile
		# walking +x out of the hull IS an edge.
		if macro.is_world_edge(macro.biome_center(graph.start_index)):
			fails.append("seed %d: biome centre flagged as world edge" % seed)
		var start_c: Vector2i = macro.biome_center(graph.start_index)
		var last_in := start_c
		var tx := start_c
		while macro.in_world(tx) and tx.x - start_c.x < MacroMap.CELL * 4:
			last_in = tx
			tx += Vector2i(1, 0)
		if not macro.is_world_edge(last_in):
			fails.append("seed %d: hull boundary tile not flagged as world edge" % seed)

		if fails.size() > 20:
			break

	print("seeds: %d   corridor edges on real graph: %d (expected 0)" % [SEEDS, corridor_total])
	if corridor_total != 0:
		fails.append("real graph produced %d corridor edges (should embed cleanly)" % corridor_total)

	# 6. Embeddability policy fires on a non-embeddable graph (6-node star: centre degree 5 > 4).
	var star := _star_graph(6)
	var emb := Embedding.new()
	emb.setup(4242, star)
	print("star-graph corridor edges (policy fired): %d" % emb.corridor_edges.size())
	if emb.corridor_edges.is_empty():
		fails.append("non-embeddable star produced no corridor — policy did not fire")
	# ...but it still placed every node (no silent drop): all 6 nodes have a cell.
	if emb.cells.size() != star.nodes.size():
		fails.append("star: %d nodes placed, expected %d" % [emb.cells.size(), star.nodes.size()])

	_report(fails)


func _report(fails: Array[String]) -> void:
	print("RESULT: ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	get_tree().quit(1 if not fails.is_empty() else 0)


# A spread of tiles across and beyond the hull, to compare biome_at between runs.
func _sample_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for gy in range(-3, 4):
		for gx in range(-3, 4):
			out.append(Vector2i(gx * (MacroMap.CELL / 2), gy * (MacroMap.CELL / 2)))
	return out


# n-node star: node 0 connected to every other node. Degree n-1 at the centre — non-embeddable
# on a square lattice once n-1 > 4. Biomes reuse one real .tres (embedding ignores biome data).
func _star_graph(n: int) -> WorldGraph:
	var biome: Resource = load("res://overworld/biomes/glade/glade.tres")
	var g := WorldGraph.new()
	for i in n:
		var node := BiomeNode.new()
		node.biome = biome
		g.nodes.append(node)
	for i in range(1, n):
		g.edges.append(Vector2i(0, i))
	g.start_index = 0
	return g
