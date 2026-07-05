class_name RoomGraph
## Layer 2: builds one biome's room graph from (world_spec, biome_coord, config).
## Pure data — no tiles. An instance holds the never-evicted BiomeGraph cache; the heavy
## lifting is the static build() so tests can force fresh, cache-free builds.
##
## SINGLE per-biome RNG, seeded seed_for([world_seed, NS_ROOM_GRAPH, bx, by]), consumed in EXACTLY
## this order:
##   1. Slot merging: row-major over slots; ONE merge roll per ELIGIBLE slot (not already merged,
##      not a world-unique host), regardless of outcome. On a hit, shapes 2x2, 2x1, 1x2 are tried
##      in that fixed order (geometry only, no RNG); first fit wins.
##   2. Spanning tree: canonical edge list (rooms row-major, then neighbour), Fisher-Yates shuffle,
##      randomized Kruskal via union-find.
##   3. Loops + geometry: one keep-roll per NON-tree edge in canonical order; then, for every kept
##      edge (tree + kept loops) in canonical order, one openness roll → OPEN, else DOOR with one
##      offset roll. Border-contract crossings are appended afterwards (they consume NO biome RNG).
##   4. Type assignment: pass 1 world-unique stamps (no RNG); pass 2 table minimums (quotas), one
##      pick-roll per placed room, entries in authored table order; pass 3 weighted fill, one
##      sample-roll per remaining room.
extends RefCounted

var _cache: Dictionary = {}   ## Vector2i biome_coord -> BiomeGraph; never evicted, never iterated


## Cached accessor. Cache reads don't break the no-dict-iteration rule; we never iterate.
func get_biome_graph(world_spec: WorldSpec, biome_coord: Vector2i, config: GenConfig) -> BiomeGraph:
	if _cache.has(biome_coord):
		return _cache[biome_coord]
	var g := build(world_spec, biome_coord, config)
	_cache[biome_coord] = g
	return g


## Build one biome's graph from scratch (no cache). Deterministic in (world_seed, biome_coord, config).
static func build(world_spec: WorldSpec, biome_coord: Vector2i, config: GenConfig) -> BiomeGraph:
	var s := config.biome_slots
	var t := config.room_slot_tiles
	var bid := world_spec.biome_at(biome_coord)
	var biome := config.biome_by_id(bid)
	var rng := config.rng_for(
			[world_spec.world_seed, WgHash.NS_ROOM_GRAPH, biome_coord.x, biome_coord.y] as Array[int])
	# Integer thresholds from the config's float dials, once per biome build — generation
	# loops compare integers, never floats.
	# Per-biome override (sentinel -1 inherits the global dial), mirroring open_passage_chance.
	var merge_chance := biome.room_merge_chance if biome.room_merge_chance >= 0.0 else config.room_merge_chance
	var threshold_merge := WgHash.threshold(merge_chance)
	var threshold_loop := WgHash.threshold(config.extra_connection_chance)
	var openness_threshold := WgHash.threshold(biome.open_passage_chance)

	# World-unique host slots in THIS biome (local coords). Lookup-only dict, never iterated for RNG.
	var unique_here: Dictionary = {}
	for ur in world_spec.unique_rooms:
		if ur.biome_coord == biome_coord:
			unique_here[ur.local_slot] = ur.type_id

	# --- Step 1: slot merging -------------------------------------------------------------------
	var owner := PackedInt32Array()
	owner.resize(s * s)
	owner.fill(-1)
	var room_top: Array[Vector2i] = []   # local slot top-left per room
	var room_size: Array[Vector2i] = []
	for ly in s:
		for lx in s:
			var idx := ly * s + lx
			if owner[idx] != -1:
				continue
			var here := Vector2i(lx, ly)
			if unique_here.has(here):
				_claim(owner, room_top, room_size, s, here, Vector2i.ONE)
				continue
			# Eligible slot: consume exactly one merge roll regardless of outcome.
			var shape := Vector2i.ONE
			if WgHash.chance(rng, threshold_merge):
				for sh in [Vector2i(2, 2), Vector2i(2, 1), Vector2i(1, 2)]:
					if _shape_fits(owner, unique_here, s, here, sh):
						shape = sh
						break
			_claim(owner, room_top, room_size, s, here, shape)

	var n_rooms := room_top.size()

	# --- Step 2: spanning tree ------------------------------------------------------------------
	# Canonical edge list: room indices are already row-major by top-left, so (a<b) sorted by (a,b)
	# is "by top-left room, then neighbour".
	var edges := _enumerate_edges(owner, s, n_rooms)   # Array of Vector2i(a, b), a < b
	edges.sort_custom(func(p, q): return p.x < q.x if p.x != q.x else p.y < q.y)

	var order := edges.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector2i = order[i]
		order[i] = order[j]
		order[j] = tmp

	var parent := PackedInt32Array()
	parent.resize(n_rooms)
	for i in n_rooms:
		parent[i] = i
	var tree: Dictionary = {}   # edge key -> true; lookup-only
	for e in order:
		if _uf_union(parent, e.x, e.y):
			tree[_ekey(e, n_rooms)] = true

	# --- Step 3: loops + passage geometry -------------------------------------------------------
	var kept: Array = []   # of {edge: Vector2i, from_tree: bool}, in canonical order
	for e in edges:
		var is_tree: bool = tree.has(_ekey(e, n_rooms))
		if is_tree:
			kept.append({"edge": e, "from_tree": true})
		elif WgHash.chance(rng, threshold_loop):
			kept.append({"edge": e, "from_tree": false})

	var room_passages: Array = []   # per room: Array[RoomSpec.Passage]
	for i in n_rooms:
		room_passages.append([])
	for entry in kept:
		var e: Vector2i = entry["edge"]
		_carve_passage(room_top, room_size, t, config.door_width_tiles, openness_threshold, rng,
				e.x, e.y, entry["from_tree"], room_passages)

	# Border-contract crossings — forced external doors; NO biome RNG consumed here.
	_append_contracts(world_spec, biome_coord, s, t, owner, room_top, room_passages)

	# --- Step 4: type assignment ----------------------------------------------------------------
	var types: Array[StringName] = []
	types.resize(n_rooms)
	types.fill(&"")
	# Pass 1: world-unique stamps (the host slot is always its own 1x1 room).
	for ur in world_spec.unique_rooms:
		if ur.biome_coord == biome_coord:
			types[owner[ur.local_slot.y * s + ur.local_slot.x]] = ur.type_id
	# Pass 2: table minimums — every entry's min_per_biome is guaranteed (as far as free rooms
	# allow): one uniform pick-roll per placed room, entries in authored table order. min == max
	# pins an exact count (exactly one boss room); rooms stamped by pass 1 count toward quotas.
	var table: Array = []       # applicable entries (known room type ids)
	for e in biome.room_type_table:
		if config.room_type_by_id(e.type_id) != null:
			table.append(e)
	var placed: Dictionary = {}   # type_id -> count; lookup-only
	for i in n_rooms:
		if types[i] != &"":
			placed[types[i]] = int(placed.get(types[i], 0)) + 1
	for e in table:
		for _k in range(e.min_per_biome - int(placed.get(e.type_id, 0))):
			var free: Array[int] = []
			for i in n_rooms:
				if types[i] == &"":
					free.append(i)
			if free.is_empty():
				break
			types[free[rng.randi_range(0, free.size() - 1)]] = e.type_id
			placed[e.type_id] = int(placed.get(e.type_id, 0)) + 1
	# Pass 3: weighted fill from the biome's room-type table (the table IS the opt-in — no other
	# filter), in canonical room order. Everything already placed counts toward max_per_biome.
	for i in n_rooms:
		if types[i] != &"":
			continue
		var total := 0
		for e in table:
			if placed.get(e.type_id, 0) < e.max_per_biome:
				total += e.weight
		if total <= 0:
			types[i] = config.fallback_room_type
			continue
		var r := rng.randi_range(0, total - 1)
		var chosen: StringName = config.fallback_room_type
		for e in table:
			if placed.get(e.type_id, 0) >= e.max_per_biome:
				continue
			r -= e.weight
			if r < 0:
				chosen = e.type_id
				break
		types[i] = chosen
		placed[chosen] = int(placed.get(chosen, 0)) + 1

	# --- Assemble BiomeGraph --------------------------------------------------------------------
	var graph := BiomeGraph.new()
	graph.biome_coord = biome_coord
	graph.size_slots = s
	graph.slot_to_room = owner
	for i in n_rooms:
		var spec := RoomSpec.new(biome_coord * s + room_top[i], room_size[i], bid)
		spec.type_id = types[i]
		spec.passages = room_passages[i]
		graph.rooms.append(spec)
	return graph


# --- Merge helpers ------------------------------------------------------------------------------

static func _claim(owner: PackedInt32Array, room_top: Array[Vector2i], room_size: Array[Vector2i],
		s: int, top: Vector2i, size: Vector2i) -> void:
	var i := room_top.size()
	room_top.append(top)
	room_size.append(size)
	for dy in size.y:
		for dx in size.x:
			owner[(top.y + dy) * s + (top.x + dx)] = i


static func _shape_fits(owner: PackedInt32Array, unique_here: Dictionary, s: int,
		top: Vector2i, size: Vector2i) -> bool:
	if top.x + size.x > s or top.y + size.y > s:
		return false
	for dy in size.y:
		for dx in size.x:
			var c := Vector2i(top.x + dx, top.y + dy)
			if owner[c.y * s + c.x] != -1 or unique_here.has(c):
				return false
	return true


# --- Edge helpers -------------------------------------------------------------------------------

static func _ekey(e: Vector2i, n: int) -> int:
	return e.x * n + e.y


static func _enumerate_edges(owner: PackedInt32Array, s: int, n: int) -> Array:
	var seen: Dictionary = {}   # membership only; never iterated
	var edges: Array = []
	for ly in s:
		for lx in s:
			var u := owner[ly * s + lx]
			if lx + 1 < s:
				var v := owner[ly * s + lx + 1]
				if v != u:
					_add_edge(seen, edges, n, u, v)
			if ly + 1 < s:
				var w := owner[(ly + 1) * s + lx]
				if w != u:
					_add_edge(seen, edges, n, u, w)
	return edges


static func _add_edge(seen: Dictionary, edges: Array, n: int, a: int, b: int) -> void:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	var key := lo * n + hi
	if not seen.has(key):
		seen[key] = true
		edges.append(Vector2i(lo, hi))


static func _uf_find(parent: PackedInt32Array, x: int) -> int:
	var root := x
	while parent[root] != root:
		root = parent[root]
	while parent[x] != root:
		var nxt := parent[x]
		parent[x] = root
		x = nxt
	return root


static func _uf_union(parent: PackedInt32Array, a: int, b: int) -> bool:
	var ra := _uf_find(parent, a)
	var rb := _uf_find(parent, b)
	if ra == rb:
		return false
	parent[rb] = ra
	return true


# --- Passage geometry ---------------------------------------------------------------------------

## Record one internal passage on both rooms of edge (ia, ib) with geometrically consistent offsets.
static func _carve_passage(room_top: Array[Vector2i], room_size: Array[Vector2i], t: int,
		door_width: int, openness_threshold: int, rng: RandomNumberGenerator,
		ia: int, ib: int, from_tree: bool, out: Array) -> void:
	var ta := room_top[ia]
	var sa := room_size[ia]
	var tb := room_top[ib]
	var sb := room_size[ib]
	var side_a: int
	var side_b: int
	var seg_lo: int       # low-coord end of the shared segment, in slots (along the border axis)
	var seg_hi: int
	var edge_a: int       # this room's wall-segment start, in slots (along the border axis)
	var edge_b: int

	if ta.x + sa.x == tb.x:                 # A west of B — vertical border, axis = y
		side_a = WorldSpec.SIDE_EAST
		side_b = WorldSpec.SIDE_WEST
		seg_lo = maxi(ta.y, tb.y)
		seg_hi = mini(ta.y + sa.y, tb.y + sb.y)
		edge_a = ta.y
		edge_b = tb.y
	elif tb.x + sb.x == ta.x:               # B west of A
		side_a = WorldSpec.SIDE_WEST
		side_b = WorldSpec.SIDE_EAST
		seg_lo = maxi(ta.y, tb.y)
		seg_hi = mini(ta.y + sa.y, tb.y + sb.y)
		edge_a = ta.y
		edge_b = tb.y
	elif ta.y + sa.y == tb.y:               # A north of B — horizontal border, axis = x
		side_a = WorldSpec.SIDE_SOUTH
		side_b = WorldSpec.SIDE_NORTH
		seg_lo = maxi(ta.x, tb.x)
		seg_hi = mini(ta.x + sa.x, tb.x + sb.x)
		edge_a = ta.x
		edge_b = tb.x
	else:                                   # B north of A
		side_a = WorldSpec.SIDE_NORTH
		side_b = WorldSpec.SIDE_SOUTH
		seg_lo = maxi(ta.x, tb.x)
		seg_hi = mini(ta.x + sa.x, tb.x + sb.x)
		edge_a = ta.x
		edge_b = tb.x

	var shared_len := (seg_hi - seg_lo) * t
	var base_a := (seg_lo - edge_a) * t     # shared-segment start, in this room's edge frame (tiles)
	var base_b := (seg_lo - edge_b) * t
	if WgHash.chance(rng, openness_threshold):
		out[ia].append(RoomSpec.Passage.new(side_a, RoomSpec.KIND_OPEN, base_a, shared_len, false, from_tree))
		out[ib].append(RoomSpec.Passage.new(side_b, RoomSpec.KIND_OPEN, base_b, shared_len, false, from_tree))
	else:
		var door_off := rng.randi_range(2, shared_len - door_width - 2)
		out[ia].append(RoomSpec.Passage.new(side_a, RoomSpec.KIND_DOOR, base_a + door_off, door_width, false, from_tree))
		out[ib].append(RoomSpec.Passage.new(side_b, RoomSpec.KIND_DOOR, base_b + door_off, door_width, false, from_tree))


## Append border-contract crossings as forced external DOORs on the correct edge rooms.
## A crossing's slot_index runs along the shared border; its tile_offset is relative to that SLOT's
## wall start. We map it to the room owning that border slot and rebase the offset onto the ROOM's
## wall-segment start (crucial for merged rooms, whose start is not the slot's).
static func _append_contracts(world_spec: WorldSpec, biome_coord: Vector2i,
		s: int, t: int, owner: PackedInt32Array, room_top: Array[Vector2i], out: Array) -> void:
	var neighbours := [
		{"delta": Vector2i(1, 0), "side": WorldSpec.SIDE_EAST},
		{"delta": Vector2i(-1, 0), "side": WorldSpec.SIDE_WEST},
		{"delta": Vector2i(0, 1), "side": WorldSpec.SIDE_SOUTH},
		{"delta": Vector2i(0, -1), "side": WorldSpec.SIDE_NORTH},
	]
	for nb in neighbours:
		var other: Vector2i = biome_coord + nb["delta"]
		if world_spec.biome_at(other) == &"":
			continue
		var side: int = nb["side"]
		for c in world_spec.get_contract(biome_coord, other):
			# Local border slot hosting this crossing; edge-axis local coord = c.slot_index.
			var local_slot: Vector2i
			var edge_start: int   # room wall-segment start along the border axis (slots)
			var room_i: int
			if side == WorldSpec.SIDE_EAST:
				local_slot = Vector2i(s - 1, c.slot_index)
				room_i = owner[local_slot.y * s + local_slot.x]
				edge_start = room_top[room_i].y
			elif side == WorldSpec.SIDE_WEST:
				local_slot = Vector2i(0, c.slot_index)
				room_i = owner[local_slot.y * s + local_slot.x]
				edge_start = room_top[room_i].y
			elif side == WorldSpec.SIDE_SOUTH:
				local_slot = Vector2i(c.slot_index, s - 1)
				room_i = owner[local_slot.y * s + local_slot.x]
				edge_start = room_top[room_i].x
			else:
				local_slot = Vector2i(c.slot_index, 0)
				room_i = owner[local_slot.y * s + local_slot.x]
				edge_start = room_top[room_i].x
			var offset: int = (c.slot_index - edge_start) * t + c.tile_offset
			out[room_i].append(RoomSpec.Passage.new(side, RoomSpec.KIND_DOOR, offset, c.width, true, false))
