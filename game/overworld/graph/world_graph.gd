class_name WorldGraph extends Resource
## The authored biome adjacency graph: which biomes exist and which ones touch. This is
## the fixed topology every seed embeds onto a lattice (Group C) — positions/rotation vary
## per seed, neighbours never do. Adding a biome is adding a node + an edge here; nothing
## hardcodes the count.
##
## `edges` are undirected index pairs into `nodes` (Vector2i(a, b)). `start_index` is the
## node the player spawns in (Glade).

@export var nodes: Array[BiomeNode] = []
@export var edges: Array[Vector2i] = []
@export var start_index: int = 0

## The world-level rare-only enemy pool (H3): enemies that NO area `roster` rolls, guaranteed
## 1–2 placements each by the specials pass overriding a few anchors. "Rare" lives here — a
## world list — not as a flag on CreatureResource (a do-not-rewrite integration point).
@export var rare_enemies: Array[PackedScene] = []


## Node indices adjacent to `index` (undirected).
func neighbors(index: int) -> Array[int]:
	var out: Array[int] = []
	for e in edges:
		if e.x == index and not out.has(e.y):
			out.append(e.y)
		elif e.y == index and not out.has(e.x):
			out.append(e.x)
	return out


## Every node reachable from `start_index` by edges — true iff the graph is one piece.
## (Named `all_nodes_reachable` to avoid shadowing `Object.is_connected(signal, callable)`.)
func all_nodes_reachable() -> bool:
	if nodes.is_empty():
		return false
	var seen := {start_index: true}
	var stack: Array[int] = [start_index]
	while not stack.is_empty():
		var n: int = stack.pop_back()
		for m in neighbors(n):
			if not seen.has(m):
				seen[m] = true
				stack.append(m)
	return seen.size() == nodes.size()


## Data-integrity check for the content test. Returns [] when valid, else a list of reasons.
func validate() -> Array[String]:
	var errs: Array[String] = []
	if nodes.is_empty():
		errs.append("no nodes")
		return errs
	if start_index < 0 or start_index >= nodes.size():
		errs.append("start_index %d out of range 0..%d" % [start_index, nodes.size() - 1])
	for i in nodes.size():
		var node := nodes[i]
		if node == null or node.biome == null:
			errs.append("node %d has no biome" % i)
			continue
		if not node.biome.has_required_area():
			errs.append("biome '%s' (node %d) has no required area" % [node.biome.id, i])
	for e in edges:
		if e.x < 0 or e.x >= nodes.size() or e.y < 0 or e.y >= nodes.size():
			errs.append("edge %s references a missing node" % e)
		elif e.x == e.y:
			errs.append("edge %s is a self-loop" % e)
	if not all_nodes_reachable():
		errs.append("graph is not connected from start_index")
	return errs
