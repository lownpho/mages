class_name WorldLayout
## Layer 1 (spec §5): places every biome exactly once on the world grid via randomized
## backtracking under the adjacency rules, then assigns world-unique room homes. Pure static
## function of (world_seed, config) — no scene tree, safe headless.
extends RefCounted


## Build the WorldSpec, or null (with push_error) if the config is invalid or the adjacency
## rules are unsatisfiable within max_layout_retries — a content bug, not a runtime condition
## (spec §5.2 step 6).
static func build(world_seed: int, config: GenConfig) -> WorldSpec:
	if not config.validate():
		return null
	var w := config.world_width_biomes
	var h := config.world_height_biomes()
	var n_cells := w * h

	var grid: Array[StringName] = []
	var placed := false
	for attempt in config.max_layout_retries:
		var rng := config.rng_for([world_seed, WgHash.NS_WORLD_LAYOUT, attempt] as Array[int])
		grid = _try_place(rng, config, w, h)
		if not grid.is_empty() and _required_satisfied(grid, config, w, h):
			placed = true
			break
	if not placed:
		push_error("WorldLayout: adjacency rules unsatisfiable after %d attempts (config bug)"
				% config.max_layout_retries)
		return null
	assert(grid.size() == n_cells)

	var spec := WorldSpec.new()
	spec.world_seed = world_seed
	spec.grid_w = w
	spec.grid_h = h
	spec.biome_grid = grid
	spec.config = config
	spec.unique_rooms = _place_unique_rooms(world_seed, config, spec)
	return spec


## One placement attempt (spec §5.2 steps 1–4): shuffle the biome list, fill cells row-major,
## backtrack when no remaining biome is admissible. Returns [] if backtracking exhausts.
static func _try_place(rng: RandomNumberGenerator, config: GenConfig, w: int, h: int) -> Array[StringName]:
	var order: Array[StringName] = []
	for b in config.biomes:
		order.append(b.id)
	# Fisher-Yates with the unit RNG — Array.shuffle() would use the global RNG (spec §4.2).
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := order[i]
		order[i] = order[j]
		order[j] = t

	var n_cells := w * h
	var grid: Array[StringName] = []
	grid.resize(n_cells)
	grid.fill(&"")
	var used: Dictionary = {}          # biome id -> true; read-only lookups, never iterated
	var cand: Array[int] = []          # per-cell next candidate index into `order`
	cand.resize(n_cells)
	cand.fill(0)

	var i := 0
	while i >= 0 and i < n_cells:
		var found := false
		while cand[i] < order.size():
			var bid := order[cand[i]]
			cand[i] += 1
			if used.has(bid):
				continue
			if _admissible(grid, config, w, bid, i):
				grid[i] = bid
				used[bid] = true
				found = true
				break
		if found:
			i += 1
			if i < n_cells:
				cand[i] = 0
		else:
			cand[i] = 0
			i -= 1
			if i >= 0:
				used.erase(grid[i])
				grid[i] = &""
	if i < 0:
		return []
	return grid


## Admissible = violates no FORBIDDEN rule against the already-placed left/up neighbors.
static func _admissible(grid: Array[StringName], config: GenConfig, w: int, bid: StringName, cell: int) -> bool:
	var x := cell % w
	if x > 0 and _forbidden(config, bid, grid[cell - 1]):
		return false
	if cell >= w and _forbidden(config, bid, grid[cell - w]):
		return false
	return true


static func _forbidden(config: GenConfig, a: StringName, b: StringName) -> bool:
	for r in config.adjacency.forbidden:
		if (r.biome_a == a and r.biome_b == b) or (r.biome_a == b and r.biome_b == a):
			return true
	return false


static func _required_satisfied(grid: Array[StringName], config: GenConfig, w: int, h: int) -> bool:
	for r in config.adjacency.required:
		if not _pair_adjacent(grid, w, h, r.biome_a, r.biome_b):
			return false
	return true


static func _pair_adjacent(grid: Array[StringName], w: int, h: int, a: StringName, b: StringName) -> bool:
	for y in h:
		for x in w:
			var here := grid[y * w + x]
			if here != a and here != b:
				continue
			var other := b if here == a else a
			if x + 1 < w and grid[y * w + x + 1] == other:
				return true
			if y + 1 < h and grid[(y + 1) * w + x] == other:
				return true
	return false


## World-unique room homes (spec §5.4). Types ordered by type_id ascending; collisions re-roll
## the later type with attempt indices. The StringName type_id is encoded into the seed parts
## by folding its UTF-8 bytes — stable under content additions, unlike a list index.
static func _place_unique_rooms(world_seed: int, config: GenConfig, spec: WorldSpec) -> Array:
	var world_types: Array[RoomTypeDef] = []
	for rt in config.room_types:
		if rt.unique_scope == RoomTypeDef.UniqueScope.WORLD:
			world_types.append(rt)
	world_types.sort_custom(func(p, q): return String(p.id) < String(q.id))

	var out: Array = []
	var taken: Dictionary = {}   # "bx,by,sx,sy" -> true; lookups only, never iterated
	for rt in world_types:
		var tkey := WgHash.fold_bytes(0, String(rt.id).to_utf8_buffer())
		# Allowed biomes sorted by id, filtered to ones actually placed on the grid.
		var cands: Array[StringName] = rt.unique_allowed_biomes.duplicate()
		cands.sort_custom(func(p, q): return String(p) < String(q))
		var coords: Array[Vector2i] = []
		for bid in cands:
			var c := _find_biome(spec, bid)
			if c.x >= 0:
				coords.append(c)
		if coords.is_empty():
			push_error("WorldLayout: world-unique type '%s' has no placeable biome" % rt.id)
			continue

		var attempt := 0
		while true:
			var rng := config.rng_for([world_seed, WgHash.NS_UNIQUE, tkey, attempt] as Array[int])
			var bc := coords[rng.randi_range(0, coords.size() - 1)]
			# Interior slots only — never on the biome border (avoids contract interaction).
			var s := config.biome_slots
			var ls := Vector2i(rng.randi_range(1, s - 2), rng.randi_range(1, s - 2))
			var key := "%d,%d,%d,%d" % [bc.x, bc.y, ls.x, ls.y]
			if not taken.has(key):
				taken[key] = true
				out.append(WorldSpec.UniqueRoom.new(rt.id, bc, ls))
				break
			attempt += 1
	return out


static func _find_biome(spec: WorldSpec, bid: StringName) -> Vector2i:
	for y in spec.grid_h:
		for x in spec.grid_w:
			if spec.biome_grid[y * spec.grid_w + x] == bid:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
