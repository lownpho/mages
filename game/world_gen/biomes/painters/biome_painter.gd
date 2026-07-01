class_name BiomePainter extends RefCounted
## Fills one biome's cells however it likes — but only within `cells`, and only into this
## biome's layers (handed in via GenContext). The streamer calls `fill` once per biome per
## chunk. A painter must be a pure function of (seed, tile): use `Hash` for every roll, never
## per-chunk state, so adjacent chunks agree at their shared edge and a chunk rebuilds
## identically after being discarded.
##
## Area-aware: a painter reads per-tile overrides via `ctx.macro.area_at(tile)` (an
## AreaResource or null) and resolves dials through `area.resolve_*(biome.<dial>)`.
##
## The base is abstract; subclasses override `fill`. `world_seed` is passed explicitly (the
## GenContext carries no RNG — determinism is via Hash keyed on the seed). Group G extends a
## painter to spawn encounters: it reaches `ctx.enemies` (the y-sorted container), `ctx.macro`
## (for `area_at`), and the resolved AreaResource, all already available here.

## Blocker-variant pick for the world-edge wall. Its own channel so the wall tile doesn't
## correlate with a subclass's cover/decor rolls on the same cell.
const CH_EDGE_WALL := 90

## Fill every tile in `cells` (all owned by `biome`) into `ctx`'s layers. Pure function of
## `(world_seed, tile)`.
func fill(_ctx: GenContext, _biome: Resource, _cells: Array[Vector2i], _world_seed: int) -> void:
	push_error("BiomePainter.fill() is abstract — override it")


## The impassable outer hull. At any world-edge cell force a biome-appropriate blocker on the
## objects layer, returning true so the caller skips this cell's normal cover/decor. Called right
## after painting ground (the wall sits on top), and BEFORE the trail/cover logic so it overrides
## trails too — a trail reaching the hull is walled, sealing the world everywhere. BORDER=4 tiles
## of colliding blockers = a solid physical wall. Pure function of the seed.
func _edge_wall(ctx: GenContext, biome: Resource, cell: Vector2i, world_seed: int) -> bool:
	if ctx.macro == null or biome.blocker_tiles.is_empty() or not ctx.macro.is_world_edge(cell):
		return false
	ctx.objects.set_cell(cell, biome.blocker_source,
		Hash.pick(world_seed, cell.x, cell.y, CH_EDGE_WALL, biome.blocker_tiles))
	return true


# How far (tiles) from an anchor to hunt for a walkable tile to seed the reachability flood.
const _PLACE_RADIUS := 4
# The four 4-connected steps — the flood's adjacency (movement is 4-directional walkable).
const _NEIGH: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
# Max tiles the reachability flood explores. A walkable pocket smaller than this that is FULLY
# enclosed by cover and contains no trail is treated as UNREACHABLE — no enemy spawns there (the
# player can't get in). A component that touches a trail, or is larger than this, is reachable.
# Trails plus per-area branch corridors thread through every area, so a genuine spawn area always
# reaches a trail well within this budget; only sealed pockets fail.
const _REACH_BUDGET := 400
# Chebyshev radius of blocker-free tiles required around a spawn. A blocker is a full-tile 8px
# collider and the biggest enemy body is ~6px, so a tile one step from a tree overlaps it; requiring
# the Moore neighbourhood (R=1 ⇒ ≥2-tile separation) clear guarantees no enemy wedges against cover.
const _CLEARANCE := 2

## True iff this painter puts a blocker (tree / edge wall / cave rubble) on this cell. A pure
## function of the seed that MUST match what `fill` paints, so `_spawn_encounters` can avoid blocked
## tiles without reading the objects layer (which a not-yet-built neighbour chunk hasn't painted).
## Base has no blockers; ForestPainter/CavePainter override it.
func _blocks(_ctx: GenContext, _biome: Resource, _cell: Vector2i, _world_seed: int) -> bool:
	return false


## The shared encounter pass: every painter family calls this at the end of `fill` so enemy
## placement is one implementation (see Encounters). Anchors are hash-thinned per tile; each spawns
## its rolled creatures into `ctx.enemies` (the shared y-sorted node the streamer tracks + frees on
## unload). Group members are spread over distinct nearby WALKABLE tiles (`_placement_tiles`) so a
## pack doesn't pile onto one point and nobody spawns inside a tree/wall. Position is set BEFORE
## add_child so a creature's `_ready` reads its final position.
func _spawn_encounters(ctx: GenContext, biome: Resource, cells: Array[Vector2i], world_seed: int) -> void:
	if ctx.enemies == null or ctx.macro == null:
		return
	for cell in cells:
		if not Encounters.is_anchor(world_seed, cell.x, cell.y):
			continue
		if not ctx.macro.in_world(cell):
			continue
		# The scenes this anchor spawns: an H3 forced coverage/rare enemy (same anchor, same path),
		# else the rolled template's members.
		var scenes: Array[PackedScene] = []
		var forced: PackedScene = ctx.macro.anchor_override(cell)
		if forced != null:
			scenes.append(forced)
		else:
			for roll in Encounters.rolls_at(ctx.macro.area_at(cell), cell, world_seed):
				scenes.append(roll.scene)
		if scenes.is_empty():
			continue
		# One distinct walkable tile per member, clustered around the anchor. Fewer tiles than members
		# (dense woods) simply spawns fewer — never on a blocker.
		var tiles := _placement_tiles(ctx, biome, cell, scenes.size(), world_seed)
		for i in tiles.size():
			var creature: Node2D = scenes[i].instantiate()
			creature.position = ctx.scatter_pos(tiles[i], world_seed,
				Encounters.CH_SCATTER_X + i * 2, Encounters.CH_SCATTER_Y + i * 2)
			ctx.enemies.add_child(creature)


# Up to `count` distinct spawn tiles for a group, all guaranteed REACHABLE. Seeds a flood at the
# nearest passable tile to the anchor, floods its walkable component, and — only if that component
# connects to the trail network (or is too big to be a sealed pocket) — returns the nearest `count`
# stand-on tiles. If the anchor sits in a sealed pocket the player can't reach, returns [] (no spawn).
# Deterministic: the component + the distance sort are order-independent, so a rebuild is identical.
func _placement_tiles(ctx: GenContext, biome: Resource, anchor: Vector2i, count: int, world_seed: int) -> Array[Vector2i]:
	var seed_tile := anchor
	var found := false
	for r in range(0, _PLACE_RADIUS + 1):
		for t in _ring(anchor, r):
			if _passable(ctx, biome, t, world_seed):
				seed_tile = t; found = true; break
		if found:
			break
	if not found:
		return []

	var reach := _flood_reachable(ctx, biome, seed_tile, count, world_seed)
	if not reach.reachable:
		return []   # sealed pocket — the player can't reach it, so spawn nothing here

	# Nearest stand-on tiles to the anchor: passable, outside the spawn pocket, and with clearance
	# from cover so the enemy's body doesn't overlap an adjacent tree collider.
	var tiles: Array[Vector2i] = []
	for t in reach.tiles:
		if not _in_spawn_pocket(t) and _has_clearance(ctx, biome, t, world_seed):
			tiles.append(t)
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := maxi(absi(a.x - anchor.x), absi(a.y - anchor.y))
		var db := maxi(absi(b.x - anchor.x), absi(b.y - anchor.y))
		if da != db: return da < db
		if a.x != b.x: return a.x < b.x
		return a.y < b.y)
	return tiles.slice(0, count)


# Flood the walkable component of `start` (4-connected passable tiles). Returns
# { reachable: bool, tiles: Array[Vector2i] }. reachable is true iff the component touches an
# is_trail tile (so it links to the network that reaches the player's spawn) OR the flood hits
# `_REACH_BUDGET` (too large to be a sealed pocket). Stops early once reachability is proven and
# `count` tiles are gathered. The boolean is order-independent → deterministic.
func _flood_reachable(ctx: GenContext, biome: Resource, start: Vector2i, count: int, world_seed: int) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var tiles: Array[Vector2i] = [start]
	var touched: bool = ctx.macro.is_trail(start)
	while not queue.is_empty():
		if tiles.size() >= _REACH_BUDGET:
			return {"reachable": true, "tiles": tiles}
		if touched and tiles.size() >= count:
			break
		var t: Vector2i = queue.pop_front()
		for d in _NEIGH:
			var n: Vector2i = t + d
			if seen.has(n) or not _passable(ctx, biome, n, world_seed):
				continue
			seen[n] = true
			tiles.append(n)
			queue.append(n)
			if ctx.macro.is_trail(n):
				touched = true
	return {"reachable": touched, "tiles": tiles}


# Chebyshev-radius-`r` ring of tiles around `center` (r == 0 → just the centre). Fixed order.
func _ring(center: Vector2i, r: int) -> Array[Vector2i]:
	if r == 0:
		return [center]
	var out: Array[Vector2i] = []
	for dx in range(-r, r + 1):
		out.append(center + Vector2i(dx, -r))
		out.append(center + Vector2i(dx, r))
	for dy in range(-r + 1, r):
		out.append(center + Vector2i(-r, dy))
		out.append(center + Vector2i(r, dy))
	return out


# A tile you can walk THROUGH: in-world, in THIS biome (so `_blocks` uses the right dials), and not
# blocked. The flood traverses these (the spawn pocket is passable — it's cleared ground).
func _passable(ctx: GenContext, biome: Resource, tile: Vector2i, world_seed: int) -> bool:
	if not ctx.macro.in_world(tile):
		return false
	if ctx.macro.biome_at(tile) != biome:
		return false
	return not _blocks(ctx, biome, tile, world_seed)


func _in_spawn_pocket(tile: Vector2i) -> bool:
	return tile.x * tile.x + tile.y * tile.y <= Encounters.SPAWN_CLEAR * Encounters.SPAWN_CLEAR


# No blocker within Chebyshev _CLEARANCE of `tile` — so a spawned enemy has room and can't overlap an
# adjacent tree collider. Pure (uses `_blocks`), so it's correct even before a neighbour chunk paints.
func _has_clearance(ctx: GenContext, biome: Resource, tile: Vector2i, world_seed: int) -> bool:
	for dy in range(-_CLEARANCE, _CLEARANCE + 1):
		for dx in range(-_CLEARANCE, _CLEARANCE + 1):
			if _blocks(ctx, biome, tile + Vector2i(dx, dy), world_seed):
				return false
	return true
