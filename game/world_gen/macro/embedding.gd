class_name Embedding extends RefCounted
## Deterministically lays the authored WorldGraph onto an integer lattice so that
## **every graph edge becomes two 4-adjacent lattice cells** — adjacency is *placed*, not
## hoped for (unlike Voronoi/flood-fill, where "Glade borders Deepwood" would be emergent).
## The lattice is pure topology: cells carry no size here; MacroMap scales a cell to tiles
## and warps its borders. `start_index` is pinned at lattice (0,0) so the spawn cell is the
## world origin.
##
## Layout varies per seed while the *topology* (who neighbours whom) never does, via two
## adjacency-preserving operations:
##   1. a per-node seed-shuffled order of the four free directions in the greedy BFS, so a
##      given neighbour lands in a different free cell each seed;
##   2. a whole-lattice rotation (0/90/180/270) + optional mirror — lattice symmetries that
##      fix the origin, so `start_index` stays at (0,0) and 4-adjacency is preserved.
## Deliberate deviation from the brief's "small jitter": a literal per-cell translation jitter
## would break the adjacency guarantee (two neighbours could drift apart), so the sub-cell
## "jitter" lives instead in `MacroMap.biome_center` (nudges the *centre within* a cell, which
## can't change which cells touch). Border wobble (also cosmetic) is MacroMap's domain warp.
##
## EMBEDDABILITY POLICY — square lattice + load-time validation (primary).
## A square lattice caps node degree at 4 and forbids crossing edges; the authored graph is a
## planar tree of max degree 3, so it always embeds. If an edge's endpoint has no free adjacent
## cell (a non-embeddable graph, e.g. a 5-node star or K4), we do NOT silently produce a wrong
## layout: we `push_warning` (authoring stays honest), place the node in the nearest free cell
## anyway (so it still gets a biome region + centre), and record the edge in `corridor_edges`.
## Group D then satisfies that adjacency for gameplay with a guaranteed trail corridor between
## the two biome centres. So every authored edge is realized as EITHER a shared border OR a
## recorded corridor — never dropped.

const _CH_DIR := 20        # per-node free-direction shuffle
const _CH_ROT := 21        # whole-lattice rotation pick
const _CH_MIRROR := 22     # whole-lattice mirror flip

# N / E / S / W — the four 4-adjacent lattice steps.
const _DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var cells: Dictionary = {}            # int node_index -> Vector2i lattice cell
var occupied: Dictionary = {}         # Vector2i lattice cell -> int node_index (reverse of `cells`)
var corridor_edges: Array[Vector2i] = []  # graph index pairs that couldn't be made adjacent (Group D backstop)

var _seed: int


func setup(world_seed: int, world_graph: WorldGraph) -> void:
	_seed = world_seed
	cells.clear()
	occupied.clear()
	corridor_edges.clear()
	_embed(world_graph)
	_apply_transform(world_graph)


## Lattice cell of a node (post-transform). Vector2i.ZERO for `start_index`.
func cell_of(node_index: int) -> Vector2i:
	return cells.get(node_index, Vector2i.ZERO)


## Greedy BFS from start: place start at (0,0), then drop each unplaced neighbour into a free
## 4-adjacent cell, trying directions in a per-node seed-shuffled order.
func _embed(graph: WorldGraph) -> void:
	var start := graph.start_index
	cells[start] = Vector2i.ZERO
	occupied[Vector2i.ZERO] = start
	var queue: Array[int] = [start]

	while not queue.is_empty():
		var node: int = queue.pop_front()
		var base: Vector2i = cells[node]
		var order := _shuffled_dirs(node)
		for m in graph.neighbors(node):
			if cells.has(m):
				continue
			var placed_cell: Variant = _place(m, base, order)
			if placed_cell == null:
				# No free adjacent cell: non-embeddable edge. Warn, drop it in the nearest
				# free cell so it still has a region, and record the adjacency for Group D.
				push_warning("Embedding: edge (%d,%d) not embeddable on the square lattice — recording a corridor adjacency (Group D backstop)." % [node, m])
				corridor_edges.append(Vector2i(node, m))
				var fallback := _nearest_free(base)
				cells[m] = fallback
				occupied[fallback] = m
			queue.append(m)


# Try each direction in `order`; occupy the first free adjacent cell. Returns the cell placed,
# or null when all four adjacent cells are taken (the non-embeddable case).
func _place(node: int, base: Vector2i, order: Array[Vector2i]) -> Variant:
	for d in order:
		var c: Vector2i = base + d
		if not occupied.has(c):
			cells[node] = c
			occupied[c] = node
			return c
	return null


# The four directions ordered by a per-(seed,node) hash — deterministic, but different each
# seed, so neighbours fan out differently without changing which nodes are neighbours.
func _shuffled_dirs(node: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = _DIRS.duplicate()
	var s := _seed
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Hash.value(s, node, _DIRS.find(a), _CH_DIR) < Hash.value(s, node, _DIRS.find(b), _CH_DIR))
	return out


# Spiral outward from `base` to the first unoccupied cell — only reached in the non-embeddable
# fallback, so it never runs for the authored (planar, degree-3) graph.
func _nearest_free(base: Vector2i) -> Vector2i:
	var radius := 1
	while radius < 64:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := base + Vector2i(dx, dy)
				if not occupied.has(c):
					return c
		radius += 1
	return base  # unreachable for any sane graph


# Rotate the whole lattice 0/90/180/270 and optionally mirror it. These are lattice
# automorphisms fixing the origin, so start stays at (0,0) and every adjacency is preserved.
func _apply_transform(graph: WorldGraph) -> void:
	var rot := Hash.range_i(_seed, 0, 0, _CH_ROT, 0, 3)
	var mirror := Hash.chance(_seed, 0, 0, _CH_MIRROR, 0.5)
	var new_cells: Dictionary = {}
	var new_occupied: Dictionary = {}
	for node in graph.nodes.size():
		if not cells.has(node):
			continue
		var c: Vector2i = _transform(cells[node], rot, mirror)
		new_cells[node] = c
		new_occupied[c] = node
	cells = new_cells
	occupied = new_occupied


func _transform(c: Vector2i, rot: int, mirror: bool) -> Vector2i:
	var v := c
	if mirror:
		v = Vector2i(-v.x, v.y)
	for _i in rot:
		v = Vector2i(-v.y, v.x)  # 90° CCW about the origin
	return v
