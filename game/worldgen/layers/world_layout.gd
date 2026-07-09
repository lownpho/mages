class_name WorldLayout
## Layer 1: packs every biome exactly once onto the world grid via a deterministic
## bottom-left skyline packer, checks the adjacency rules, then assigns world-unique room homes.
## Pure static function of (world_seed, config) — no scene tree, safe headless.
##
## RNG consumption order per build():
## 1. Per attempt (config.max_layout_retries, seed parts [world_seed, NS_WORLD_LAYOUT, attempt]):
##    Fisher-Yates the biome list. The bottom-left scan that follows draws no RNG at all —
##    packing itself is a deterministic function of the shuffled order.
## 2. Per world-unique room type (sorted by id ascending), per re-roll attempt (seed parts
##    [world_seed, NS_UNIQUE, type_id_fold, attempt], one RNG instance per attempt): one draw
##    picks the host biome (from the id-sorted, placed-only allowed list), then one draw each
##    for the interior local slot's x and y, in that order.
extends RefCounted


## Build the WorldSpec, or null (with push_error) if the config is invalid or the adjacency
## rules are unsatisfiable within max_layout_retries — a content bug, not a runtime condition.
static func build(world_seed: int, config: GenConfig) -> WorldSpec:
	if not config.validate():
		return null
	var w := config.world_width_cells

	var placements: Array = []
	var placed := false
	for attempt in config.max_layout_retries:
		var rng := config.rng_for([world_seed, WgHash.NS_WORLD_LAYOUT, attempt] as Array[int])
		placements = _pack(rng, config, w)
		if _adjacency_ok(placements, config):
			placed = true
			break
	if not placed:
		push_error("WorldLayout: adjacency rules unsatisfiable after %d attempts (config bug)"
				% config.max_layout_retries)
		return null

	var grid_h := 0
	for p in placements:
		grid_h = maxi(grid_h, p.rect.position.y + p.rect.size.y)

	var grid: Array[StringName] = []
	grid.resize(w * grid_h)
	grid.fill(&"")
	for p in placements:
		for y in range(p.rect.position.y, p.rect.position.y + p.rect.size.y):
			for x in range(p.rect.position.x, p.rect.position.x + p.rect.size.x):
				grid[y * w + x] = p.id

	var spec := WorldSpec.new()
	spec.world_seed = world_seed
	spec.grid_w = w
	spec.grid_h = grid_h
	spec.biome_grid = grid
	spec.placements = placements
	spec.config = config
	spec.unique_rooms = _place_unique_rooms(world_seed, config, spec)
	return spec


## One packing attempt: shuffle the biome list (the only RNG this function consumes), then
## bottom-left skyline pack each biome's size_cells rect in that shuffled order — for each
## biome, scan candidate x in [0, width - size.x], candidate y = the tallest column height over
## [x, x+size.x), and take the (y, then x) minimum. Placement cannot fail: validate() guarantees
## every biome's width fits world_width_cells. Returns Array[BiomePlacement] in config.biomes
## order (NOT shuffle order — callers rely on a stable, content-authored order).
static func _pack(rng: RandomNumberGenerator, config: GenConfig, w: int) -> Array:
	var order: Array[BiomeDef] = []
	for b in config.biomes:
		order.append(b)
	# Fisher-Yates with the unit RNG — Array.shuffle() would use the global RNG.
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := order[i]
		order[i] = order[j]
		order[j] = t

	var heights: Array[int] = []
	heights.resize(w)
	heights.fill(0)

	var by_id: Dictionary = {}   # biome id -> BiomePlacement; lookups only, never iterated
	for b in order:
		var size := b.size_cells
		var best_x := 0
		var best_y := -1
		for x in (w - size.x + 1):
			var y := 0
			for col in range(x, x + size.x):
				y = maxi(y, heights[col])
			if best_y < 0 or y < best_y:
				best_y = y
				best_x = x
		by_id[b.id] = WorldSpec.BiomePlacement.new(b.id, Rect2i(best_x, best_y, size.x, size.y))
		for col in range(best_x, best_x + size.x):
			heights[col] = best_y + size.y

	var out: Array = []
	for b in config.biomes:
		out.append(by_id[b.id])
	return out


## REQUIRED pairs must share an edge segment >= 1 cell; FORBIDDEN pairs must not.
static func _adjacency_ok(placements: Array, config: GenConfig) -> bool:
	var rect_by_id: Dictionary = {}   # biome id -> Rect2i; lookups only, never iterated
	for p in placements:
		rect_by_id[p.id] = p.rect
	for r in config.adjacency.required:
		if not _pair_adjacent(rect_by_id, r.biome_a, r.biome_b):
			return false
	for r in config.adjacency.forbidden:
		if _pair_adjacent(rect_by_id, r.biome_a, r.biome_b):
			return false
	return true


static func _pair_adjacent(rect_by_id: Dictionary, a: StringName, b: StringName) -> bool:
	if not (rect_by_id.has(a) and rect_by_id.has(b)):
		return false
	return _rects_adjacent(rect_by_id[a], rect_by_id[b])


## True iff two non-overlapping rects share an edge segment of >= 1 cell (a flush side with
## overlapping span on the perpendicular axis). Corner-only contact returns false.
static func _rects_adjacent(a: Rect2i, b: Rect2i) -> bool:
	var a_right := a.position.x + a.size.x
	var b_right := b.position.x + b.size.x
	var a_bottom := a.position.y + a.size.y
	var b_bottom := b.position.y + b.size.y
	if a_right == b.position.x or b_right == a.position.x:
		var lo := maxi(a.position.y, b.position.y)
		var hi := mini(a_bottom, b_bottom)
		return lo < hi
	if a_bottom == b.position.y or b_bottom == a.position.y:
		var lo := maxi(a.position.x, b.position.x)
		var hi := mini(a_right, b_right)
		return lo < hi
	return false


## World-unique room homes. Types ordered by type_id ascending; collisions re-roll
## the later type with attempt indices. The StringName type_id is encoded into the seed parts
## by folding its UTF-8 bytes — stable under content additions, unlike a list index.
static func _place_unique_rooms(world_seed: int, config: GenConfig, spec: WorldSpec) -> Array:
	var world_types: Array[RoomTypeDef] = []
	for rt in config.room_types:
		if rt.unique_scope == RoomTypeDef.UniqueScope.WORLD:
			world_types.append(rt)
	world_types.sort_custom(func(p, q): return String(p.id) < String(q.id))

	var out: Array = []
	var taken: Dictionary = {}   # "x,y" world_slot -> true; lookups only, never iterated
	for rt in world_types:
		var tkey := WgHash.fold_bytes(0, String(rt.id).to_utf8_buffer())
		# Allowed biomes sorted by id, filtered to ones actually placed on the grid.
		var cands: Array[StringName] = rt.unique_allowed_biomes.duplicate()
		cands.sort_custom(func(p, q): return String(p) < String(q))
		var placeable: Array[StringName] = []
		for bid in cands:
			if spec.placement_for(bid) != null:
				placeable.append(bid)
		if placeable.is_empty():
			push_error("WorldLayout: world-unique type '%s' has no placeable biome" % rt.id)
			continue

		var attempt := 0
		while true:
			var rng := config.rng_for([world_seed, WgHash.NS_UNIQUE, tkey, attempt] as Array[int])
			var bid: StringName = placeable[rng.randi_range(0, placeable.size() - 1)]
			var origin := spec.region_origin_slot(bid)
			var size := spec.region_size_slots(bid)
			# Interior slots only — never on the region border (avoids contract interaction).
			var local := Vector2i(rng.randi_range(1, size.x - 2), rng.randi_range(1, size.y - 2))
			var world_slot := origin + local
			var key := "%d,%d" % [world_slot.x, world_slot.y]
			if not taken.has(key):
				taken[key] = true
				out.append(WorldSpec.UniqueRoom.new(rt.id, world_slot))
				break
			attempt += 1
	return out
