extends RefCounted
## The specials pass: a tiny deterministic world-init placement of the handful of *unique*
## things a per-tile hash can't express — "exactly one door per dungeon type per biome", "one
## portal per biome". A stateless hash is great for "5% of tiles are trees" but has no memory of
## global counts; this pass gives those counts a home. It runs once inside `MacroMap.setup()`
## (after trails + areas exist, since every special snaps onto/near a trail) and produces a typed,
## queryable list. Pure function of the seed: same seed → same specials at the same tiles.
##
## A special is `{tile: Vector2i, type: StringName, payload: Dictionary}`. Types placed here:
##   &"portal" — payload {node:int, biome_id:StringName, neighbors:Array of {id, tile}}. On a
##       trail (the biome centre), so reachable. neighbors lists each graph-adjacent biome's
##       portal tile, for the fast-travel menu.
##   &"door"   — payload {dungeon_type:StringName, biome_id:StringName}. Off the main trail but
##       4-adjacent to it (must be found, still reachable). One per (biome, dungeon_type).
##
## Extension seam (H3/H5/H6): every special is created through `_add(tile, type, payload)`, and
## every special *tile* is validated reachable by construction. To add &"sign"/&"boss", write a
## `_place_signs(...)` / `_place_bosses(...)` that calls `_add`, then invoke it from `setup`. Rare
## anchor overrides layer on the same list (find a special or post-filter it); the shape never
## changes, so callers (streamer, painters) keep reading `{tile, type, payload}`.

# Per-node hash channels — distinct so door direction / step choices decorrelate.
const _CH_DOOR_DIR := 60
const _CH_RARE_COUNT := 70   # how many overrides (1–2) a rare enemy gets
const _CH_RARE_START := 71   # which instance a rare's overrides start from

# How far (Chebyshev) we probe outward from an area instance's centre for a usable anchor tile.
# An area-cell is CELL/GRID (≈500) tiles across and anchors are dense (~0.003), so a real anchor
# sits within a few dozen tiles of the centre; this bound is generous slack, not a tight fit.
const _ANCHOR_PROBE := 160

# Signs: how far along a trail (from the biome centre, toward a neighbour) a sign sits, and how far
# off the straight centre→neighbour line we search for an actual trail tile (the corridor wobbles).
const _SIGN_MIN := 6
const _SIGN_MAX := 60
const _SIGN_SEARCH := 5

# How far off the biome centre we probe for the door's off-trail-but-adjacent tile before giving
# up on a direction. A biome centre sits deep interior (jitter+warp << CELL/2) and the trail band
# is ~7 tiles wide, so the trail edge is always found within a few dozen tiles.
const _DOOR_PROBE := 80

# Axis directions only: stepping along an axis means the door tile's predecessor is a 4-neighbour,
# so "one step past the last trail tile" is guaranteed 4-adjacent to a trail (reachable).
const _AXES := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _seed: int
var _list: Array[Dictionary] = []
var _overrides: Dictionary = {}   # Vector2i anchor tile -> PackedScene forced by _spawn_encounters


func setup(world_seed: int, macro, graph: WorldGraph) -> void:
	_seed = world_seed
	_list.clear()
	_overrides.clear()
	var centers: Dictionary = macro.biome_centers()   # node -> centre tile (occupied cells only)
	_place_portals(macro, graph, centers)
	_place_doors(macro, graph, centers)
	_place_signs(macro, graph, centers)
	# Anchor overrides + boss reservations enumerate area instances, so they run after areas exist
	# (they do — MacroMap bakes areas before the specials pass). Overrides claim anchor tiles; the
	# painter reads them via anchor_override(). Order is fixed → the list rebuilds identically.
	_place_anchor_overrides(macro, graph)
	_place_bosses(macro, graph)


## The forced enemy scene for an anchor tile, or null. The painter's encounter pass calls this at
## every anchor BEFORE its normal rolls: a non-null result replaces the roll (H3 coverage/rare) —
## same anchor identity, same spawn path, no parallel instancing. Pure function of the seed.
func anchor_override(tile: Vector2i) -> PackedScene:
	return _overrides.get(tile, null)


## The full typed list. Each entry is {tile:Vector2i, type:StringName, payload:Dictionary}.
func all() -> Array[Dictionary]:
	return _list


## The specials whose `tile` falls inside `rect` (half-open, matching Rect2i.has_point). Linear
## scan — the list is a few dozen items, so the streamer calling this per chunk stays cheap.
func in_rect(rect: Rect2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _list:
		if rect.has_point(s.tile):
			out.append(s)
	return out


# One portal per biome, sitting on its centre (already a trail tile → reachable). Its payload
# carries every graph-adjacent biome's portal tile so the travel menu can teleport without
# re-deriving the graph at runtime.
func _place_portals(_macro, graph: WorldGraph, centers: Dictionary) -> void:
	for node in centers:
		var biome: Resource = graph.nodes[node].biome
		var neighbors: Array = []
		for m in graph.neighbors(node):
			if centers.has(m):
				neighbors.append({"id": graph.nodes[m].biome.id, "tile": centers[m]})
		_add(centers[node], &"portal", {
			"node": node, "biome_id": biome.id, "neighbors": neighbors,
		})


# One door per dungeon_type per biome (only deepwood authors any → 1 door total this content).
func _place_doors(macro, graph: WorldGraph, centers: Dictionary) -> void:
	for node in centers:
		var biome: Resource = graph.nodes[node].biome
		for dungeon_type in biome.dungeon_types:
			var tile := _door_tile(macro, node, centers[node])
			_add(tile, &"door", {"dungeon_type": dungeon_type, "biome_id": biome.id})


# A deterministic tile that is in-world, OFF the main trail, yet 4-adjacent to it: step outward
# from the biome centre along a seeded axis until the first non-trail tile whose predecessor (a
# 4-neighbour) is still trail — i.e. exactly one tile past the trail edge. Tries each axis in a
# seeded order so a blocked direction (hull edge) falls through to another.
func _door_tile(macro, node: int, center: Vector2i) -> Vector2i:
	var start := Hash.range_i(_seed, node, 0, _CH_DOOR_DIR, 0, _AXES.size() - 1)
	for k in _AXES.size():
		var dir: Vector2i = _AXES[(start + k) % _AXES.size()]
		for step in range(1, _DOOR_PROBE):
			var t := center + dir * step
			if not macro.in_world(t):
				break
			if not macro.is_trail(t) and macro.is_trail(t - dir):
				return t
	return center   # degenerate fallback (centre is on a trail, still reachable)


# --- H5 signs: one per graph-neighbour, on the trail heading that way from the biome centre ---
# Guarantees ≥1 sign per biome (a connected graph gives every biome ≥1 neighbour) and each points
# somewhere new (its target is a distinct graph-adjacent biome centre). Pure geometry, no per-player
# state: the bias is simply the neighbour direction.
func _place_signs(macro, graph: WorldGraph, centers: Dictionary) -> void:
	for node in centers:
		var center: Vector2i = centers[node]
		var used: Dictionary = {}   # avoid two neighbour signs colliding on one tile
		for m in graph.neighbors(node):
			if not centers.has(m):
				continue
			var target: Vector2i = centers[m]
			var tile := _sign_tile(macro, center, target, used)
			if tile == center:
				continue   # no trail tile found toward this neighbour (degenerate) — skip
			used[tile] = true
			_add(tile, &"sign", {"target_id": graph.nodes[m].biome.id, "target_tile": target})


# Walk out along the straight centre→target line; at each step search a small box for a trail tile
# (the corridor wobbles a few tiles off the line). First unused trail tile at distance ≥ _SIGN_MIN
# wins. Falls back to `center` (caller skips) if the whole span yields nothing.
func _sign_tile(macro, center: Vector2i, target: Vector2i, used: Dictionary) -> Vector2i:
	var dir := (Vector2(target - center)).normalized()
	for d in range(_SIGN_MIN, _SIGN_MAX):
		var p := center + Vector2i(roundi(dir.x * d), roundi(dir.y * d))
		for oy in range(-_SIGN_SEARCH, _SIGN_SEARCH + 1):
			for ox in range(-_SIGN_SEARCH, _SIGN_SEARCH + 1):
				var t := p + Vector2i(ox, oy)
				if not used.has(t) and macro.in_world(t) and macro.is_trail(t):
					return t
	return center


# --- H3 anchor overrides: guarantee coverage of every world-roster enemy + 1–2 of each rare ---
# Not a parallel spawn path: each override claims a REAL Group-G anchor tile and forces its scene
# there via _overrides, which biome_painter reads instead of the normal roll. Deterministic: fixed
# iteration order + seeded picks → the same tiles every rebuild.
func _place_anchor_overrides(macro, graph: WorldGraph) -> void:
	var instances := _all_instances(macro, graph)
	var used: Dictionary = {}   # anchor tiles already claimed (overrides must not collide)

	# Coverage: ≥1 of every world-roster member. Prefer an instance whose roster contains it; fall
	# back to any instance so the guarantee holds even if that enemy's usual area wasn't placed.
	for scene in _world_roster(graph):
		var tile = _claim_anchor(macro, _fitting(instances, scene, true), used)
		if tile == null:
			tile = _claim_anchor(macro, instances, used)
		if tile != null:
			used[tile] = true
			_overrides[tile] = scene
			_add(tile, &"coverage", {"scene": scene})

	# Rares: 1–2 of each, spread across distinct instances (rares fit anywhere — no area rolls them).
	for i in graph.rare_enemies.size():
		var scene: PackedScene = graph.rare_enemies[i]
		if scene == null or instances.is_empty():
			continue
		var count := Hash.range_i(_seed, i, 0, _CH_RARE_COUNT, 1, 2)
		var start := Hash.range_i(_seed, i, 0, _CH_RARE_START, 0, instances.size() - 1)
		var placed := 0
		for k in instances.size():
			if placed >= count:
				break
			var inst: Dictionary = instances[(start + k) % instances.size()]
			var tile = _anchor_in_instance(macro, inst, used)
			if tile != null:
				used[tile] = true
				_overrides[tile] = scene
				_add(tile, &"rare", {"scene": scene})
				placed += 1


# --- H6 boss anchors: reserve the anchor tile of every &"boss"-tagged area instance ---
# No node, no behaviour — a dormant reserved tile. Current content tags no area &"boss", so this
# places 0; the mechanism fires as soon as an area is tagged. HOOK: wire the real boss spawn here
# (or off the &"boss" special) when boss fights land.
func _place_bosses(macro, graph: WorldGraph) -> void:
	var used: Dictionary = {}
	for node in _occupied_nodes(macro, graph):
		var biome: Resource = graph.nodes[node].biome
		for inst in macro.area_instances(node):
			if not inst.type.tags.has(&"boss"):
				continue
			var tile = _anchor_in_instance(macro, {"node": node, "index": inst.index, "type": inst.type}, used)
			if tile == null:
				tile = inst.center   # degenerate: no anchor in the area — still reserve one tile
			used[tile] = true
			_add(tile, &"boss", {"biome_id": biome.id, "area_type": inst.type.type_id})


# The union of every area's roster across all biomes, in a stable first-seen order (the coverage
# pool — enemies ordinary encounters already roll).
func _world_roster(graph: WorldGraph) -> Array:
	var out: Array = []
	for node in graph.nodes:
		if node == null or node.biome == null:
			continue
		for area in node.biome.area_set:
			if area == null:
				continue
			for scene in area.roster:
				if scene != null and not out.has(scene):
					out.append(scene)
	return out


# Every placed area instance across all biomes, in a stable order: {node, index, type, center}.
func _all_instances(macro, graph: WorldGraph) -> Array:
	var out: Array = []
	for node in _occupied_nodes(macro, graph):
		for inst in macro.area_instances(node):
			out.append({"node": node, "index": inst.index, "type": inst.type, "center": inst.center})
	return out


func _occupied_nodes(macro, graph: WorldGraph) -> Array:
	var out: Array = []
	var centers: Dictionary = macro.biome_centers()
	for node in graph.nodes.size():
		if centers.has(node):
			out.append(node)
	return out


# Instances whose roster contains `scene` (require_roster) or all instances otherwise, preserving order.
func _fitting(instances: Array, scene: PackedScene, require_roster: bool) -> Array:
	if not require_roster:
		return instances
	var out: Array = []
	for inst in instances:
		if inst.type.roster.has(scene):
			out.append(inst)
	return out


# First instance (in order) that yields an unclaimed anchor tile, or null.
func _claim_anchor(macro, instances: Array, used: Dictionary):
	for inst in instances:
		var tile = _anchor_in_instance(macro, inst, used)
		if tile != null:
			return tile
	return null


# A real Group-G anchor tile inside an area instance: scan outward (bounded, deterministic row-major
# per ring) for the first tile that is an anchor, in-world, owned by this instance's area, outside
# the spawn pocket, and not already claimed — exactly the tiles _spawn_encounters visits. Null if none.
func _anchor_in_instance(macro, inst: Dictionary, used: Dictionary):
	var center: Vector2i = macro.area_cell_center(inst.node, inst.index)
	var area: Resource = inst.type
	for r in range(0, _ANCHOR_PROBE):
		for t in _ring(center, r):
			if used.has(t):
				continue
			if t.x * t.x + t.y * t.y <= Encounters.SPAWN_CLEAR * Encounters.SPAWN_CLEAR:
				continue
			if not macro.in_world(t):
				continue
			if not Encounters.is_anchor(_seed, t.x, t.y):
				continue
			if macro.area_at(t) != area:
				continue
			return t
	return null


# The tiles at Chebyshev distance `r` from `center`, in a fixed order (top row L→R, bottom, then
# side columns). r==0 is the single centre tile.
func _ring(center: Vector2i, r: int) -> Array:
	if r == 0:
		return [center]
	var out: Array = []
	for x in range(center.x - r, center.x + r + 1):
		out.append(Vector2i(x, center.y - r))
		out.append(Vector2i(x, center.y + r))
	for y in range(center.y - r + 1, center.y + r):
		out.append(Vector2i(center.x - r, y))
		out.append(Vector2i(center.x + r, y))
	return out


func _add(tile: Vector2i, type: StringName, payload: Dictionary) -> void:
	_list.append({"tile": tile, "type": type, "payload": payload})
