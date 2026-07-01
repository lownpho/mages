class_name MacroMap extends RefCounted
## The macro layout: the only piece with global knowledge of the world. It answers the
## question a per-tile hash can't — *which biome owns this tile?* — by embedding the authored
## WorldGraph onto a lattice (see `embedding.gd`) and scaling each lattice cell to a
## ≈CELL-tile square. The outer hull is the **union of occupied cells** (non-square, organic),
## so `biome_at` is null outside it. Cell borders are domain-warped (cosmetic) so biomes
## undulate into each other instead of meeting on ruler-straight seams.
##
## Guarantees: node↔biome is 1:1 and each node occupies one lattice cell, so there is
## **exactly one region per biome**; `biome_at` is a pure function of the seed (stable across
## calls, identical on re-`setup` with the same seed).
##
## This is the biome half of MacroMap. Group D adds trails (`is_trail`); Group E adds
## sub-areas (`area_at`). They reuse `embedding` (cells) and `biome_center` (trail/portal
## targets) — hence those are public.

# Embedding / Trails are global class_names (used unqualified). Areas / Specials omit class_name,
# so they're still preloaded here.
const Areas := preload("res://overworld/macro/areas.gd")
const Specials := preload("res://overworld/macro/specials.gd")

# Tiles per lattice cell — the biome span. Target biome ≈1500 tiles across (old REGION_SIZE
# was 1200 at a smaller biome target). One uniform cell for every biome this group;
# per-biome sizing (via `target_radius_tiles`) is a later tuning task.
const CELL := 1500
# Domain-warp amplitude in tiles for organic borders. Kept << CELL/2 so a cell's geometric
# centre stays deep interior — a reliable trail/portal target for Groups D/H.
const WARP := 150.0
# Sub-cell centre jitter: nudges a biome's centre within its cell per seed (the "small jitter"
# variety). Bounded so centre + jitter + warp stays well inside the cell.
const CENTER_JITTER := 200.0
# Outer ring thickness (tiles) flagged as world edge — Group I walls it.
const BORDER := 4

const _CH_CENTER_X := 30
const _CH_CENTER_Y := 31

var _seed: int
var _graph: WorldGraph
var _embedding: Embedding
var _trails: Trails
var _areas: Areas
var _specials: Specials
var _warp_noise: FastNoiseLite
var _cell_biome: Dictionary = {}   # Vector2i lattice cell -> Resource (BiomeResource)
# Memo of `_warped` (Vector2i tile -> Vector2). The same tile is warped by biome_at, area_at and
# is_world_edge, and the encounter flood/clearance pass re-queries the same tiles many times over,
# so one cache collapses all that repeated noise sampling. Pure memo of a deterministic function —
# no effect on results. Bounded (cleared past _CACHE_CAP) so streaming can't grow it without limit;
# reset on every setup so a reseed starts clean.
var _warp_cache: Dictionary = {}
const _CACHE_CAP := 120000


func setup(world_seed: int, world_graph: WorldGraph) -> void:
	_seed = world_seed
	_graph = world_graph
	_embedding = Embedding.new()
	_embedding.setup(world_seed, world_graph)

	_warp_cache.clear()
	_warp_noise = FastNoiseLite.new()
	_warp_noise.seed = world_seed
	_warp_noise.frequency = 0.004          # low frequency: borders undulate at biome scale
	_warp_noise.fractal_octaves = 2

	# Bake occupied cell -> biome resource (one region per biome by construction).
	_cell_biome.clear()
	for node in _graph.nodes.size():
		if not _embedding.cells.has(node):
			continue
		_cell_biome[_embedding.cells[node]] = _graph.nodes[node].biome

	# Trails carve guaranteed-clear corridors along every edge (and every non-embeddable
	# corridor_edge) between biome centres — the connectivity backbone (Group D).
	_trails = Trails.new()
	_trails.setup(world_seed, biome_centers(), _graph.edges, _embedding.corridor_edges)

	# Bake sub-area types per biome (Group E), then branch a trail from each biome centre to every
	# area-cell centre so every placed area instance sits on the connected network. Bounded
	# (~5 biomes × 16 cells) and deterministic — same up-front-pass philosophy as trails.
	var node_biomes: Dictionary = {}
	for node in _graph.nodes.size():
		if _embedding.cells.has(node):
			node_biomes[node] = _graph.nodes[node].biome
	_areas = Areas.new()
	_areas.setup(world_seed, node_biomes)
	for node in node_biomes:
		var center := biome_center(node)
		for index in Areas.COUNT:
			if _areas.type_at(node, index) != null:
				_trails.add_corridor(center, area_cell_center(node, index))

	# Specials pass (Group H): places the unique per-count things — one portal per biome, one
	# door per dungeon type — onto/near the now-complete trail network. Same up-front,
	# seed-deterministic philosophy as trails/areas.
	_specials = Specials.new()
	_specials.setup(world_seed, self, _graph)


## Which biome owns this tile, or null if the tile is off-world (outside the hull).
## Pure function of the seed → the partition never shifts.
func biome_at(tile: Vector2i) -> Resource:
	return _cell_biome.get(_cell_of_tile(tile), null)


## True iff the tile lies inside the hull (some biome owns it).
func in_world(tile: Vector2i) -> bool:
	return _cell_biome.has(_cell_of_tile(tile))


## True if the tile is in-world but within BORDER of the hull boundary — the ring Group I walls.
func is_world_edge(tile: Vector2i) -> bool:
	var w := _warped(tile)
	var cell := _cell_from_warped(w)
	if not _cell_biome.has(cell):
		return false
	# Fast interior reject: a neighbour at ±BORDER warps within (BORDER + 2·WARP) of this tile's
	# warped point, so if that point is deeper than that margin inside its cell every neighbour stays
	# in the same occupied cell and this can't be an edge — skip the four extra warps. Sound because
	# the warp displacement is bounded by WARP on each side.
	var margin := BORDER + 2.0 * WARP + 2.0
	var half := CELL / 2.0
	if absf(w.x - cell.x * CELL) < half - margin and absf(w.y - cell.y * CELL) < half - margin:
		return false
	for d in Embedding._DIRS:
		if not in_world(tile + d * BORDER):
			return true
	return false


## Biome centre in tile coords — the reliable trail/portal target for a node. Cell centre plus
## a small per-seed jitter that stays interior.
func biome_center(node_index: int) -> Vector2i:
	var cell: Vector2i = _embedding.cell_of(node_index)
	var jx := (Hash.value(_seed, node_index, 0, _CH_CENTER_X) * 2.0 - 1.0) * CENTER_JITTER
	var jy := (Hash.value(_seed, node_index, 0, _CH_CENTER_Y) * 2.0 - 1.0) * CENTER_JITTER
	return cell * CELL + Vector2i(roundi(jx), roundi(jy))


## node_index -> biome centre (tile coords), for Groups D/E/H to enumerate biome centres.
func biome_centers() -> Dictionary:
	var out: Dictionary = {}
	for node in _graph.nodes.size():
		if _embedding.cells.has(node):
			out[node] = biome_center(node)
	return out


## Lattice cell of a node (topology coords), for Group E's sub-cell subdivision.
func node_cell(node_index: int) -> Vector2i:
	return _embedding.cell_of(node_index)


## Graph edges that couldn't be realized as adjacent cells — Group D carves a trail corridor
## between these biome centres to honour the authored adjacency.
func corridor_edges() -> Array[Vector2i]:
	return _embedding.corridor_edges


## True iff the tile lies on a guaranteed-clear trail corridor. Pure function of the seed, so it
## agrees across chunk borders. The union of trails is one connected component through every biome
## centre; Group F's painter must leave these tiles walkable.
func is_trail(tile: Vector2i) -> bool:
	return _trails.is_trail(tile)


## The specials placed at world-init (Group H): each {tile:Vector2i, type:StringName,
## payload:Dictionary}. Types this content: &"portal" (per biome), &"door" (per dungeon type per
## biome). Every tile is reachable (on/adjacent to a trail) and in-world. Pure function of the
## seed — identical on re-`setup`. The H3/H5/H6 agent extends the type set through `specials.gd`.
func specials() -> Array[Dictionary]:
	return _specials.all()


## The specials whose `tile` lies inside `rect` — the streamer calls this per chunk to know which
## special scenes to instantiate for the tiles it is building.
func specials_in_rect(rect: Rect2i) -> Array[Dictionary]:
	return _specials.in_rect(rect)


## The forced enemy scene at an anchor tile, or null (H3). The painter's encounter pass calls this
## at each anchor before rolling: a non-null result replaces the roll (coverage/rare override) on
## the same anchor via the same spawn path. Pure function of the seed.
func anchor_override(tile: Vector2i) -> PackedScene:
	return _specials.anchor_override(tile)


## The AreaResource owning this tile, or null off-world. The area-cell index is taken from the
## same warped coordinate as `biome_at`, so an area never leaks past its biome border. Pure
## function of the seed.
func area_at(tile: Vector2i) -> Resource:
	var w := _warped(tile)
	var cell := _cell_from_warped(w)
	if not _cell_biome.has(cell):
		return null
	return _areas.type_at(_embedding.occupied[cell], _area_index(w, cell))


## Centre of area-cell `index` in biome `node`, in tile coords — trail target / enumeration
## anchor. Un-warped grid centre (deterministic, stays interior); Group E branches a trail here.
func area_cell_center(node: int, index: int) -> Vector2i:
	var cell: Vector2i = _embedding.cell_of(node)
	var side := float(CELL) / Areas.GRID
	@warning_ignore("integer_division")
	var gy := index / Areas.GRID
	var gx := index % Areas.GRID
	var cx := cell.x * CELL - CELL / 2.0 + (gx + 0.5) * side
	var cy := cell.y * CELL - CELL / 2.0 + (gy + 0.5) * side
	return Vector2i(roundi(cx), roundi(cy))


## Every placed area instance in biome `node`: an Array of {index:int, type:AreaResource,
## center:Vector2i}. Groups G/H enumerate instances through this (e.g. filter by
## `type.tags.has(&"boss")` for boss anchors). Null-type cells (empty area_set) are skipped.
func area_instances(node: int) -> Array:
	var out: Array = []
	for index in Areas.COUNT:
		var t: Resource = _areas.type_at(node, index)
		if t != null:
			out.append({"index": index, "type": t, "center": area_cell_center(node, index)})
	return out


# The domain-warped coordinate of a tile (organic borders): the biome/area partition lives in
# this warped space, so both `biome_at` and `area_at` warp once and derive cell + area-cell here.
func _warped(tile: Vector2i) -> Vector2:
	var cached: Variant = _warp_cache.get(tile)
	if cached != null:
		return cached
	var wx: float = tile.x + _warp_noise.get_noise_2d(tile.x, tile.y) * WARP
	var wy: float = tile.y + _warp_noise.get_noise_2d(tile.x + 1000.0, tile.y) * WARP
	var w := Vector2(wx, wy)
	if _warp_cache.size() >= _CACHE_CAP:
		_warp_cache.clear()
	_warp_cache[tile] = w
	return w


# Nearest lattice cell to a warped coordinate (round-based, so the origin sits at the centre of
# cell (0,0)).
func _cell_from_warped(w: Vector2) -> Vector2i:
	return Vector2i(roundi(w.x / float(CELL)), roundi(w.y / float(CELL)))


# The area-cell index (0..COUNT-1) of a warped coordinate within its cell: local offset into the
# cell's [−CELL/2, +CELL/2) span, bucketed into the GRID×GRID sub-grid (row-major).
func _area_index(w: Vector2, cell: Vector2i) -> int:
	var side := float(CELL) / Areas.GRID
	var local_x := w.x - (cell.x * CELL - CELL / 2.0)
	var local_y := w.y - (cell.y * CELL - CELL / 2.0)
	var gx := clampi(int(local_x / side), 0, Areas.GRID - 1)
	var gy := clampi(int(local_y / side), 0, Areas.GRID - 1)
	return gy * Areas.GRID + gx


# The lattice cell owning a tile: domain-warp the coordinate (organic borders), then snap to
# the nearest cell.
func _cell_of_tile(tile: Vector2i) -> Vector2i:
	return _cell_from_warped(_warped(tile))
