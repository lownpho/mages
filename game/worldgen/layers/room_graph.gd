class_name RoomGraph
## Layer 2: builds one BIOME's room graph from (world_spec, biome_id, config). A biome spans a
## rectangle of macro-cells (its placement); the graph covers the whole region's slot rect.
## Pure data — no tiles. An instance holds the never-evicted BiomeGraph cache; the heavy
## lifting is the static build() so tests can force fresh, cache-free builds.
##
## Rooms come from a demand-carving guillotine BSP — correct by construction, no retries:
## world-unique pins are carved first (exact 1x1 leaves, no RNG), then every quota demand
## (min_per_biome × min_size_slots per room type) gets a leaf of exactly its demanded size
## carved out, then the remaining rects subdivide randomly down to bsp_max_leaf_slots.
## validate() guarantees demands fit, so subdivision is a total function.
##
## SINGLE per-biome RNG, seeded seed_for([world_seed, NS_ROOM_GRAPH, origin_cell.x,
## origin_cell.y]), consumed in EXACTLY this order:
##   1. Demand carving consumes NO RNG: demands in canonical order (area desc, longest side
##      desc, type id asc); each picks the working rect + corner whose leaf lies FARTHEST from
##      the nearest entrance anchor for difficulty >= 2 and NEAREST for difficulty <= 1 (ties:
##      first in scan order) — the entrance anchors (contract border slots, or the region
##      centre for the starting/sealed biome) are pure geometry known before subdivision, so
##      hard set-pieces land deep and easy ones shallow by construction.
##   2. Random subdivision: FIFO over the working rect list; a 1x1 rect is a leaf with NO roll;
##      a rect within bsp_max_leaf_slots (either orientation) consumes ONE stop roll (hit =
##      leaf); every rect that splits consumes ONE cut roll (axis = longer side, ties split x).
##   3. Spanning tree: canonical edge list (rooms row-major by top-left, then neighbour),
##      Fisher-Yates shuffle, randomized Kruskal via union-find.
##   4. Loops + geometry: one keep-roll per NON-tree edge in canonical order; then, for every
##      kept edge (tree + kept loops) in canonical order, one openness roll → OPEN, else DOOR
##      with one offset roll. Border-contract crossings are appended afterwards (they consume
##      NO biome RNG; canonical order: region cells row-major × sides N,E,S,W).
##   5. Type assignment over the biome's ROSTER: pass 1 world-unique stamps (no RNG); pass 2
##      quota minimums in DESCENDING difficulty (min-size area desc, then registry order within
##      a tie — the boss picks before lesser set-pieces), one pick-roll per placed room — drawn
##      from the free rooms FITTING the type's size window whose depth TIER is nearest the
##      type's authored difficulty (falling back to all free rooms, with a warning, if none
##      fits); pass 3 weighted fill in registry order, one sample-roll per remaining room among
##      the fitting types of the room's tier, falling through to lower tiers (the biome's
##      fallback_room_type when nothing fits).
##
## Between steps 4 and 5 each room gets an entrance DEPTH (no RNG): BFS over the kept internal
## edges from the biome's entrance rooms — every room carrying an external border-contract
## door, or the room covering the region's central slot for the starting biome and for a
## sealed biome. The depth range splits into quarters (RoomSpec.tier, 0..3) and each
## RoomTypeDef's `difficulty` is matched against it — the hand-authored rooms themselves form
## the difficulty ramp from entrance to boss.
extends RefCounted

var _cache: Dictionary = {}   ## StringName biome_id -> BiomeGraph; never evicted, never iterated


## Cached accessor. Cache reads don't break the no-dict-iteration rule; we never iterate.
func get_biome_graph(world_spec: WorldSpec, biome_id: StringName, config: GenConfig) -> BiomeGraph:
	if _cache.has(biome_id):
		return _cache[biome_id]
	var g := build(world_spec, biome_id, config)
	_cache[biome_id] = g
	return g


## Build one biome's graph from scratch (no cache). Deterministic in (world_seed, biome_id, config).
static func build(world_spec: WorldSpec, biome_id: StringName, config: GenConfig) -> BiomeGraph:
	var place: WorldSpec.BiomePlacement = world_spec.placement_for(biome_id)
	var bs := config.biome_slots
	var t := config.room_slot_tiles
	var biome := config.biome_by_id(biome_id)
	var origin_slot := place.rect.position * bs
	var sw := place.rect.size.x * bs
	var sh := place.rect.size.y * bs
	var rng := config.rng_for([world_spec.world_seed, WgHash.NS_ROOM_GRAPH,
			place.rect.position.x, place.rect.position.y] as Array[int])
	# Integer thresholds from the config's float dials, once per biome build — generation
	# loops compare integers, never floats. Sentinel -1 on the biome inherits the global dial.
	var stop_chance := biome.bsp_stop_chance if biome.bsp_stop_chance >= 0.0 else config.bsp_stop_chance
	var threshold_stop := WgHash.threshold(stop_chance)
	var loop_chance := biome.room_extra_connection_chance if biome.room_extra_connection_chance >= 0.0 \
			else config.extra_connection_chance
	var threshold_loop := WgHash.threshold(loop_chance)
	var openness_threshold := WgHash.threshold(biome.open_passage_chance)

	# --- Step 0: world-unique pins (no RNG) -------------------------------------------------------
	# Region-local 1x1 leaves at fixed slots, carved out of the working rect before anything else.
	var pins: Array = []   # of [Vector2i local_slot, StringName type_id], canonical (y, x) order
	for ur in world_spec.unique_rooms:
		var local: Vector2i = ur.world_slot - origin_slot
		if local.x >= 0 and local.y >= 0 and local.x < sw and local.y < sh:
			pins.append([local, ur.type_id])
	pins.sort_custom(func(p, q): return p[0].y < q[0].y if p[0].y != q[0].y else p[0].x < q[0].x)

	var rects: Array = [Rect2i(0, 0, sw, sh)]   # working list, region-local slots
	var leaves: Array = []                      # of [Rect2i, StringName pinned_type (&"" = none)]
	for pin in pins:
		_carve_cell(rects, pin[0])
		leaves.append([Rect2i(pin[0], Vector2i.ONE), pin[1]])

	# --- Step 1: demand carving (no RNG — anchor-aware) --------------------------------------------
	var roster := config.rooms_for_biome(biome_id)   # this biome's room types, registry order
	var anchors := _entrance_anchors(world_spec, place.rect, biome_id == config.starting_biome,
			bs, origin_slot, sw, sh)
	var demands: Array = []   # of [Vector2i size, StringName type_id, int difficulty]
	for rt_def in roster:
		for _k in rt_def.min_per_biome:
			demands.append([rt_def.min_size_slots, rt_def.id, rt_def.difficulty])
	demands.sort_custom(func(p, q):
		var pa: int = p[0].x * p[0].y
		var qa: int = q[0].x * q[0].y
		if pa != qa:
			return pa > qa
		var pm: int = maxi(p[0].x, p[0].y)
		var qm: int = maxi(q[0].x, q[0].y)
		if pm != qm:
			return pm > qm
		return String(p[1]) < String(q[1]))
	for d in demands:
		var size: Vector2i = d[0]
		var deep: bool = d[2] >= 2
		var best_i := -1
		var best_corner := 0
		var best_size := size
		var best_score := 0
		for i in rects.size():
			var r: Rect2i = rects[i]
			var oriented: Vector2i
			if size.x <= r.size.x and size.y <= r.size.y:
				oriented = size
			elif size.y <= r.size.x and size.x <= r.size.y:
				oriented = Vector2i(size.y, size.x)
			else:
				continue
			for corner in 4:
				var d2 := _nearest_anchor_d2(anchors, _corner_rect(r, oriented, corner))
				var score := d2 if deep else -d2
				if best_i < 0 or score > best_score:
					best_score = score
					best_i = i
					best_corner = corner
					best_size = oriented
		if best_i < 0:
			# validate() makes this unreachable for sane content; pins can fragment in theory.
			push_warning("RoomGraph: no rect fits demand %s in biome '%s'" % [size, biome_id])
			continue
		leaves.append([_carve_demand(rects, best_i, best_size, best_corner), &""])

	# --- Step 2: random subdivision (FIFO; every rect terminates as a leaf) ------------------------
	var max_leaf := config.bsp_max_leaf_slots
	var qi := 0
	while qi < rects.size():
		var r: Rect2i = rects[qi]
		qi += 1
		if r.size == Vector2i.ONE:
			leaves.append([r, &""])
			continue
		var fits_cap := (r.size.x <= max_leaf.x and r.size.y <= max_leaf.y) \
				or (r.size.y <= max_leaf.x and r.size.x <= max_leaf.y)
		if fits_cap and WgHash.chance(rng, threshold_stop):
			leaves.append([r, &""])
			continue
		var split_x := r.size.x >= r.size.y
		if r.size.x == 1:
			split_x = false
		elif r.size.y == 1:
			split_x = true
		if split_x:
			var cut := rng.randi_range(1, r.size.x - 1)
			rects.append(Rect2i(r.position, Vector2i(cut, r.size.y)))
			rects.append(Rect2i(r.position + Vector2i(cut, 0), Vector2i(r.size.x - cut, r.size.y)))
		else:
			var cut := rng.randi_range(1, r.size.y - 1)
			rects.append(Rect2i(r.position, Vector2i(r.size.x, cut)))
			rects.append(Rect2i(r.position + Vector2i(0, cut), Vector2i(r.size.x, r.size.y - cut)))

	# Canonical room order: row-major by top-left. Leaves tile the region exactly.
	leaves.sort_custom(func(p, q):
		var rp: Rect2i = p[0]
		var rq: Rect2i = q[0]
		return rp.position.y < rq.position.y if rp.position.y != rq.position.y \
				else rp.position.x < rq.position.x)
	var n_rooms := leaves.size()
	var room_top: Array[Vector2i] = []
	var room_size: Array[Vector2i] = []
	var owner := PackedInt32Array()
	owner.resize(sw * sh)
	owner.fill(-1)
	for i in n_rooms:
		var lr: Rect2i = leaves[i][0]
		room_top.append(lr.position)
		room_size.append(lr.size)
		for dy in lr.size.y:
			for dx in lr.size.x:
				owner[(lr.position.y + dy) * sw + lr.position.x + dx] = i

	# --- Step 3: spanning tree ----------------------------------------------------------------------
	var edges := _enumerate_edges(owner, sw, sh, n_rooms)   # Array of Vector2i(a, b), a < b
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

	# --- Step 4: loops + passage geometry -----------------------------------------------------------
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
	_append_contracts(world_spec, place.rect, biome_id, bs, t, origin_slot, owner, sw,
			room_top, room_passages)

	# --- Step 4b: entrance depth (pure BFS, no RNG) --------------------------------------------------
	var depth := _compute_depth(biome_id == config.starting_biome, owner, sw, sh, n_rooms,
			kept, room_passages)
	var max_depth := 0
	for i in n_rooms:
		max_depth = maxi(max_depth, depth[i])

	# --- Step 5: type assignment ---------------------------------------------------------------------
	var types: Array[StringName] = []
	types.resize(n_rooms)
	types.fill(&"")
	# Pass 1: world-unique stamps (pinned 1x1 leaves carved in step 0).
	for i in n_rooms:
		if leaves[i][1] != &"":
			types[i] = leaves[i][1]
	# Pass 2: quota minimums — every room type's min_per_biome is guaranteed a size-fitting room
	# (the demand leaves exist by construction): one uniform pick-roll per placed room, types in
	# DESCENDING min-size area (difficulty desc, registry order within a tie) so the size-hungry
	# set-pieces claim the big leaves first — a 1x1 type fits anything, so ordering by difficulty
	# first would let a deep 1x1 quota eat the only leaf a shallow 2x2 one could have used. The
	# pool is the free FITTING rooms whose depth tier is NEAREST the type's difficulty; if a
	# quota stole every fitting leaf, any free room (warned).
	var placed: Dictionary = {}   # type_id -> count; lookup-only
	for i in n_rooms:
		if types[i] != &"":
			placed[types[i]] = int(placed.get(types[i], 0)) + 1
	var reg_index: Dictionary = {}   # RoomTypeDef -> registry position; lookup-only
	for i in roster.size():
		reg_index[roster[i]] = i
	var quota_order := roster.duplicate()
	quota_order.sort_custom(func(p, q):
		var pa: int = p.min_size_slots.x * p.min_size_slots.y
		var qa: int = q.min_size_slots.x * q.min_size_slots.y
		if pa != qa:
			return pa > qa
		if p.difficulty != q.difficulty:
			return p.difficulty > q.difficulty
		return reg_index[p] < reg_index[q])
	for rt_def in quota_order:
		for _k in range(rt_def.min_per_biome - int(placed.get(rt_def.id, 0))):
			var pool := _quota_pool(types, room_size, depth, max_depth, rt_def, true)
			if pool.is_empty():
				pool = _quota_pool(types, room_size, depth, max_depth, rt_def, false)
				if not pool.is_empty():
					push_warning("RoomGraph: quota for '%s' placed on a non-fitting room in '%s'"
							% [rt_def.id, biome_id])
			if pool.is_empty():
				break   # no free room left at all
			types[pool[rng.randi_range(0, pool.size() - 1)]] = rt_def.id
			placed[rt_def.id] = int(placed.get(rt_def.id, 0)) + 1
	# Pass 3: weighted fill from the biome's roster, in canonical room order. A room only takes
	# types of its own difficulty tier WHOSE SIZE WINDOW IT FITS, falling through tier-1, tier-2…
	# when a tier offers nothing — the biome's fallback_room_type when none does.
	for i in n_rooms:
		if types[i] != &"":
			continue
		var chosen: StringName = biome.fallback_room_type
		for tier in range(RoomSpec.tier_for(depth[i], max_depth), -1, -1):
			var total := 0
			for rt_def in roster:
				if rt_def.difficulty == tier and placed.get(rt_def.id, 0) < rt_def.max_per_biome \
						and _fits(rt_def, room_size[i]):
					total += rt_def.weight
			if total <= 0:
				continue
			var r := rng.randi_range(0, total - 1)
			for rt_def in roster:
				if rt_def.difficulty != tier or placed.get(rt_def.id, 0) >= rt_def.max_per_biome \
						or not _fits(rt_def, room_size[i]):
					continue
				r -= rt_def.weight
				if r < 0:
					chosen = rt_def.id
					break
			break
		types[i] = chosen
		placed[chosen] = int(placed.get(chosen, 0)) + 1

	# --- Assemble BiomeGraph ---------------------------------------------------------------------------
	var graph := BiomeGraph.new()
	graph.biome_id = biome_id
	graph.origin_slot = origin_slot
	graph.size_slots = Vector2i(sw, sh)
	graph.slot_to_room = owner
	for i in n_rooms:
		var spec := RoomSpec.new(origin_slot + room_top[i], room_size[i], biome_id)
		spec.type_id = types[i]
		spec.passages = room_passages[i]
		spec.depth = depth[i]
		spec.biome_max_depth = max_depth
		spec.void_sides = _void_sides(world_spec, origin_slot, room_top[i], room_size[i])
		graph.rooms.append(spec)
	return graph


## Whether a room of `size` slots satisfies a type's size window (either orientation).
static func _fits(rt: RoomTypeDef, size: Vector2i) -> bool:
	if size.x >= rt.min_size_slots.x and size.x <= rt.max_size_slots.x \
			and size.y >= rt.min_size_slots.y and size.y <= rt.max_size_slots.y:
		return true
	return size.y >= rt.min_size_slots.x and size.y <= rt.max_size_slots.x \
			and size.x >= rt.min_size_slots.y and size.x <= rt.max_size_slots.y


## Free rooms for a quota pick: tier gap to the type's difficulty is minimal over the candidate
## set; `need_fit` restricts candidates to rooms fitting the type's size window.
static func _quota_pool(types: Array[StringName], room_size: Array[Vector2i],
		depth: PackedInt32Array, max_depth: int, rt_def: RoomTypeDef, need_fit: bool) -> Array[int]:
	var best_gap := 99
	for i in types.size():
		if types[i] == &"" and (not need_fit or _fits(rt_def, room_size[i])):
			best_gap = mini(best_gap, absi(RoomSpec.tier_for(depth[i], max_depth) - rt_def.difficulty))
	var pool: Array[int] = []
	if best_gap == 99:
		return pool
	for i in types.size():
		if types[i] == &"" and (not need_fit or _fits(rt_def, room_size[i])) \
				and absi(RoomSpec.tier_for(depth[i], max_depth) - rt_def.difficulty) == best_gap:
			pool.append(i)
	return pool


# --- BSP carving helpers ---------------------------------------------------------------------------

## Remove the working rect containing `cell` and re-add its complement around the 1x1 cell:
## the x-strips left/right of the cell's column (full height), then the y-remainders above/below
## within the column. Deterministic, no RNG. The cell itself becomes the caller's pinned leaf.
static func _carve_cell(rects: Array, cell: Vector2i) -> void:
	for i in rects.size():
		var r: Rect2i = rects[i]
		if not r.has_point(cell):
			continue
		rects.remove_at(i)
		if cell.x > r.position.x:
			rects.append(Rect2i(r.position, Vector2i(cell.x - r.position.x, r.size.y)))
		if cell.x + 1 < r.position.x + r.size.x:
			rects.append(Rect2i(Vector2i(cell.x + 1, r.position.y),
					Vector2i(r.position.x + r.size.x - cell.x - 1, r.size.y)))
		if cell.y > r.position.y:
			rects.append(Rect2i(Vector2i(cell.x, r.position.y), Vector2i(1, cell.y - r.position.y)))
		if cell.y + 1 < r.position.y + r.size.y:
			rects.append(Rect2i(Vector2i(cell.x, cell.y + 1),
					Vector2i(1, r.position.y + r.size.y - cell.y - 1)))
		return
	push_error("RoomGraph: pinned slot %s not inside any working rect" % cell)


## The `size` leaf rect sitting at one of `r`'s four corners (0 NW, 1 NE, 2 SW, 3 SE).
static func _corner_rect(r: Rect2i, size: Vector2i, corner: int) -> Rect2i:
	var at_east := corner == 1 or corner == 3
	var at_south := corner == 2 or corner == 3
	var lx := r.position.x + r.size.x - size.x if at_east else r.position.x
	var ly := r.position.y + r.size.y - size.y if at_south else r.position.y
	return Rect2i(Vector2i(lx, ly), size)


## Guillotine-carve a `size` leaf out of rects[idx] at one of its four corners, replacing the
## rect with its two remainder strips: first the x-complement strip (full height), then the
## y-complement within the leaf's column. Returns the carved leaf rect.
static func _carve_demand(rects: Array, idx: int, size: Vector2i, corner: int) -> Rect2i:
	var r: Rect2i = rects[idx]
	rects.remove_at(idx)
	var at_east := corner == 1 or corner == 3
	var at_south := corner == 2 or corner == 3
	var leaf := _corner_rect(r, size, corner)
	if r.size.x > size.x:
		var strip_x := r.position.x if at_east else r.position.x + size.x
		rects.append(Rect2i(Vector2i(strip_x, r.position.y), Vector2i(r.size.x - size.x, r.size.y)))
	if r.size.y > size.y:
		var strip_y := r.position.y if at_south else r.position.y + size.y
		rects.append(Rect2i(Vector2i(leaf.position.x, strip_y), Vector2i(size.x, r.size.y - size.y)))
	return leaf


## Squared distance (in half-slot units) from a leaf's centre to the nearest entrance anchor.
static func _nearest_anchor_d2(anchors: Array[Vector2i], leaf: Rect2i) -> int:
	var c := leaf.position * 2 + leaf.size   # centre in half-slots
	var best := 0x7fffffffffffffff
	for a in anchors:
		var dx := c.x - (a.x * 2 + 1)
		var dy := c.y - (a.y * 2 + 1)
		best = mini(best, dx * dx + dy * dy)
	return best


## Entrance anchor slots (region-local), known BEFORE subdivision: the border slots carrying
## external contract crossings — or the region centre for the starting biome (the player spawns
## there) and for a sealed biome. Pure lookups, no RNG; same cell/side mapping as
## _append_contracts. Used to steer demand carving (hard rooms deep, easy rooms shallow).
static func _entrance_anchors(world_spec: WorldSpec, region: Rect2i, is_starting: bool,
		bs: int, origin_slot: Vector2i, sw: int, sh: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_starting:
		var sides := [
			{"delta": Vector2i(0, -1), "side": WorldSpec.SIDE_NORTH},
			{"delta": Vector2i(1, 0), "side": WorldSpec.SIDE_EAST},
			{"delta": Vector2i(0, 1), "side": WorldSpec.SIDE_SOUTH},
			{"delta": Vector2i(-1, 0), "side": WorldSpec.SIDE_WEST},
		]
		for cy in range(region.position.y, region.position.y + region.size.y):
			for cx in range(region.position.x, region.position.x + region.size.x):
				var cell := Vector2i(cx, cy)
				for nb in sides:
					var other: Vector2i = cell + nb["delta"]
					if region.has_point(other):
						continue
					var other_bid := world_spec.biome_at(other)
					if other_bid == &"":
						continue
					var side: int = nb["side"]
					for c in world_spec.get_contract(cell, other):
						if side == WorldSpec.SIDE_EAST:
							out.append(Vector2i((cx + 1) * bs - 1, cy * bs + c.slot_index) - origin_slot)
						elif side == WorldSpec.SIDE_WEST:
							out.append(Vector2i(cx * bs, cy * bs + c.slot_index) - origin_slot)
						elif side == WorldSpec.SIDE_SOUTH:
							out.append(Vector2i(cx * bs + c.slot_index, (cy + 1) * bs - 1) - origin_slot)
						else:
							out.append(Vector2i(cx * bs + c.slot_index, cy * bs) - origin_slot)
	if out.is_empty():
		out.append(Vector2i(sw >> 1, sh >> 1))
	return out


## Bitmask of the room's sides that face sealed void (world edge or an unclaimed macro-cell)
## along at least one slot. Pure lookups, no RNG.
static func _void_sides(world_spec: WorldSpec, origin_slot: Vector2i,
		top: Vector2i, size: Vector2i) -> int:
	var mask := 0
	var w0 := origin_slot + top   # room origin in WORLD slots
	for dx in size.x:
		if world_spec.biome_at_slot(Vector2i(w0.x + dx, w0.y - 1)) == &"":
			mask |= 1 << WorldSpec.SIDE_NORTH
		if world_spec.biome_at_slot(Vector2i(w0.x + dx, w0.y + size.y)) == &"":
			mask |= 1 << WorldSpec.SIDE_SOUTH
	for dy in size.y:
		if world_spec.biome_at_slot(Vector2i(w0.x - 1, w0.y + dy)) == &"":
			mask |= 1 << WorldSpec.SIDE_WEST
		if world_spec.biome_at_slot(Vector2i(w0.x + size.x, w0.y + dy)) == &"":
			mask |= 1 << WorldSpec.SIDE_EAST
	return mask


## Per-room BFS hops from the biome entrance, over the kept internal edges. Sources: every room
## with an external border-contract door — or, for the starting biome (the player spawns near
## its centre, so difficulty must ramp outward from there) and for a sealed biome, the room
## covering the region's central slot. The spanning tree guarantees every room is reached.
static func _compute_depth(is_starting: bool, owner: PackedInt32Array, sw: int, sh: int,
		n_rooms: int, kept: Array, room_passages: Array) -> PackedInt32Array:
	var depth := PackedInt32Array()
	depth.resize(n_rooms)
	depth.fill(-1)
	var queue: Array[int] = []
	if not is_starting:
		for i in n_rooms:
			for p in room_passages[i]:
				if p.external:
					depth[i] = 0
					queue.append(i)
					break
	if queue.is_empty():
		var centre := owner[(sh >> 1) * sw + (sw >> 1)]
		depth[centre] = 0
		queue.append(centre)

	var adj: Array = []   # per room: PackedInt32Array of neighbour room indices
	for _i in n_rooms:
		adj.append(PackedInt32Array())
	for entry in kept:
		var e: Vector2i = entry["edge"]
		adj[e.x].append(e.y)
		adj[e.y].append(e.x)
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for nb in adj[cur]:
			if depth[nb] == -1:
				depth[nb] = depth[cur] + 1
				queue.append(nb)
	for i in n_rooms:
		if depth[i] < 0:   # unreachable can't happen (spanning tree); keep the invariant depth >= 0
			depth[i] = 0
	return depth


# --- Edge helpers ------------------------------------------------------------------------------

static func _ekey(e: Vector2i, n: int) -> int:
	return e.x * n + e.y


static func _enumerate_edges(owner: PackedInt32Array, sw: int, sh: int, n: int) -> Array:
	var seen: Dictionary = {}   # membership only; never iterated
	var edges: Array = []
	for ly in sh:
		for lx in sw:
			var u := owner[ly * sw + lx]
			if lx + 1 < sw:
				var v := owner[ly * sw + lx + 1]
				if v != u:
					_add_edge(seen, edges, n, u, v)
			if ly + 1 < sh:
				var w := owner[(ly + 1) * sw + lx]
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


# --- Passage geometry ----------------------------------------------------------------------------

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
## Contracts exist per macro-cell edge where the two cells belong to DIFFERENT biomes; both
## sides compute the identical crossings lazily (see BorderContracts). Canonical iteration
## order: region cells row-major × sides N,E,S,W. Consumes NO biome RNG. A crossing's
## slot_index runs along the shared CELL edge; its tile_offset is relative to that SLOT's wall
## start — we rebase it onto the owning ROOM's wall-segment start (rooms can span slots).
static func _append_contracts(world_spec: WorldSpec, region: Rect2i, biome_id: StringName,
		bs: int, t: int, origin_slot: Vector2i, owner: PackedInt32Array, sw: int,
		room_top: Array[Vector2i], out: Array) -> void:
	var sides := [
		{"delta": Vector2i(0, -1), "side": WorldSpec.SIDE_NORTH},
		{"delta": Vector2i(1, 0), "side": WorldSpec.SIDE_EAST},
		{"delta": Vector2i(0, 1), "side": WorldSpec.SIDE_SOUTH},
		{"delta": Vector2i(-1, 0), "side": WorldSpec.SIDE_WEST},
	]
	for cy in range(region.position.y, region.position.y + region.size.y):
		for cx in range(region.position.x, region.position.x + region.size.x):
			var cell := Vector2i(cx, cy)
			for nb in sides:
				var other: Vector2i = cell + nb["delta"]
				if region.has_point(other):
					continue   # interior cell edge — internal passages already cover it
				var other_bid := world_spec.biome_at(other)
				if other_bid == &"" or other_bid == biome_id:
					continue   # void (sealed) or impossible self-adjacency
				var side: int = nb["side"]
				for c in world_spec.get_contract(cell, other):
					# Region-local border slot hosting this crossing.
					var local: Vector2i
					var edge_start: int   # room wall-segment start along the border axis (slots)
					if side == WorldSpec.SIDE_EAST:
						local = Vector2i((cx + 1) * bs - 1, cy * bs + c.slot_index) - origin_slot
					elif side == WorldSpec.SIDE_WEST:
						local = Vector2i(cx * bs, cy * bs + c.slot_index) - origin_slot
					elif side == WorldSpec.SIDE_SOUTH:
						local = Vector2i(cx * bs + c.slot_index, (cy + 1) * bs - 1) - origin_slot
					else:
						local = Vector2i(cx * bs + c.slot_index, cy * bs) - origin_slot
					var room_i := owner[local.y * sw + local.x]
					if side == WorldSpec.SIDE_EAST or side == WorldSpec.SIDE_WEST:
						edge_start = room_top[room_i].y
						out[room_i].append(RoomSpec.Passage.new(side, RoomSpec.KIND_DOOR,
								(local.y - edge_start) * t + c.tile_offset, c.width, true, false))
					else:
						edge_start = room_top[room_i].x
						out[room_i].append(RoomSpec.Passage.new(side, RoomSpec.KIND_DOOR,
								(local.x - edge_start) * t + c.tile_offset, c.width, true, false))
