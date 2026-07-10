class_name Population
## Layer 4: enemy groups + feature placements for one room, as data only — no nodes, no scenes.
## Single pass — there are no interior retries any more, so identity and position are drawn
## together. TWO independent RNG streams:
##
## 1. Population rng  [world_seed, NS_POPULATION, origin_slot.x, origin_slot.y]:
##    one group-count draw, then per group IN ORDER: weighted entry pick, then —
##    single-type entry: one size draw (`randi_range(group_min, group_max)`);
##    mixed pack (members non-empty): one count draw per member
##    (`randi_range(count_min, count_max)`); then per entity ONE candidate-index draw
##    (`rng.randi_range(0, candidates.size()-1)`).
##    An empty pool consumes no draw (`_weighted_pick` returns null without drawing). If the
##    candidate list is empty when an entity's turn comes, that entity (and every later one,
##    since the list only shrinks) is skipped with no draw — a `push_warning` fires once per
##    room — but every later group still performs its own weighted-pick/size draws, so the
##    stream order above holds regardless of how many entities actually land. A room with a
##    non-empty pool and a non-empty candidate list always spawns at least one entity.
##    Candidates are the room's reachable tiles (row-major) at least `spawn_min_dist_from_doors`
##    tiles from every opening. After each pick, every candidate within squared distance < 4 of
##    the picked tile is dropped (order-preserving linear filter — deterministic, no Dictionary).
##    When `pack_spread > 0`, all members of a group (single-type or mixed) cluster around the
##    first placed entity's tile; `_filter_within` constrains subsequent picks to that radius.
##
## 2. Features rng  [world_seed, NS_FEATURES, origin_slot.x, origin_slot.y]: consumed once per
##    `RoomTypeDef.features` entry, IN ARRAY ORDER. Per feature: one count draw
##    (`randi_range(count_min, count_max)`), then per instance a tile is picked by placement —
##    CENTER (first instance only) consumes NO draw: the deterministic room-centre / nearest
##    reachable tile. Every other instance (RANDOM_REACHABLE, NEAR_WALL, or a CENTER feature's
##    2nd+ instance falling through to RANDOM_REACHABLE) consumes exactly one candidate-index
##    draw against a single reachable-tile candidate list shared by every feature in the room
##    (row-major, no door-distance requirement; NEAR_WALL draws from that list filtered to tiles
##    4-adjacent to a WALL/BLOCKER, falling back to the unfiltered list, then to CENTER, when its
##    filtered pool is empty). A picked tile is removed from the shared list exactly once (no
##    radius — unlike enemy candidates). Draws happen even when `scene` is null so a feature
##    left without a scene never shifts a later feature's stream; the resulting entry is simply
##    not appended to `out.spawns`.
extends RefCounted

const MIN_SPAWN_DIST2 := 4      # ≥ 2 tiles from other spawns


static func populate(out: RoomOutput, spec: RoomSpec, config: GenConfig, world_seed: int,
		openings: PackedInt32Array) -> void:
	out.spawns = []
	var rt := config.room_type_by_id(spec.type_id)
	if rt == null:
		return

	var ox := PackedInt32Array()
	var oy := PackedInt32Array()
	for i in openings.size():
		ox.append(openings[i] % out.width)
		@warning_ignore("integer_division")
		oy.append(openings[i] / out.width)

	_populate_enemies(out, spec, config, world_seed, rt, ox, oy)
	_populate_features(out, spec, config, world_seed, rt)

	# Stable entity ids by list index.
	for i in out.spawns.size():
		out.spawns[i]["entity_id"] = config.seed_for([world_seed, WgHash.NS_POPULATION,
				spec.origin_slot.x, spec.origin_slot.y, i] as Array[int])


static func _populate_enemies(out: RoomOutput, spec: RoomSpec, config: GenConfig, world_seed: int,
		rt: RoomTypeDef, ox: PackedInt32Array, oy: PackedInt32Array) -> void:
	var rng := config.rng_for([world_seed, WgHash.NS_POPULATION,
			spec.origin_slot.x, spec.origin_slot.y] as Array[int])

	var opening_dist2 := config.spawn_min_dist_from_doors * config.spawn_min_dist_from_doors
	var candidates := _door_clear_candidates(out, ox, oy, opening_dist2)

	var spawn_entries: Array = rt.enemies
	var groups_min := rt.enemy_groups_min
	var groups_max := rt.enemy_groups_max
	if rt.scale_groups_with_size:
		var area := maxi(1, spec.size_slots.x * spec.size_slots.y)
		groups_min *= area
		groups_max *= area
	var groups := rng.randi_range(groups_min, groups_max)
	var warned := false
	for _g in groups:
		var entry: SpawnTableEntry = _weighted_pick(rng, spawn_entries)
		if entry == null:
			continue
		var pack_spread2 := entry.pack_spread * entry.pack_spread
		var pack_centre := Vector2i(-1, -1)

		# Build flat list of {enemy_id, count} — single-type or mixed pack.
		var spawn_queue: Array[Dictionary] = []
		if entry.members.is_empty():
			var size := rng.randi_range(entry.group_min, entry.group_max)
			spawn_queue.append({"enemy_id": entry.enemy_id, "count": size})
		else:
			for m in entry.members:
				var count := rng.randi_range(m.count_min, m.count_max)
				spawn_queue.append({"enemy_id": m.enemy_id, "count": count})

		for q in spawn_queue:
			for _s in q["count"]:
				if candidates.is_empty():
					if not warned:
						push_warning("Population: room at slot %s ran out of spawn candidates" %
								[spec.origin_slot])
						warned = true
					continue
				var pool := candidates
				if pack_spread2 > 0 and pack_centre.x >= 0:
					pool = _filter_within(candidates, pack_centre, out.width, pack_spread2)
					if pool.is_empty():
						pool = candidates
				var i := rng.randi_range(0, pool.size() - 1)
				var tile := _tile_from_index(out.width, pool[i])
				if pack_centre.x < 0:
					pack_centre = tile
				out.spawns.append({"enemy_id": q["enemy_id"], "tile": tile})
				candidates = _remove_within(candidates, tile, out.width, MIN_SPAWN_DIST2)


static func _populate_features(out: RoomOutput, spec: RoomSpec, config: GenConfig,
		world_seed: int, rt: RoomTypeDef) -> void:
	if rt.features.is_empty():
		return
	var rng := config.rng_for([world_seed, WgHash.NS_FEATURES,
			spec.origin_slot.x, spec.origin_slot.y] as Array[int])
	var reachable := _reachable_candidates(out)   # shared across every feature in this room

	for f in rt.features:
		var count := rng.randi_range(f.count_min, f.count_max)
		for n in count:
			var tile := Vector2i(-1, -1)
			if f.placement == RoomFeature.Placement.CENTER and n == 0:
				tile = _feature_tile(out)
			else:
				var pool := reachable
				if f.placement == RoomFeature.Placement.NEAR_WALL:
					var walled := _filter_near_wall(out, reachable)
					if not walled.is_empty():
						pool = walled
				if pool.is_empty():
					tile = _feature_tile(out)
				else:
					var i := rng.randi_range(0, pool.size() - 1)
					var idx := pool[i]
					tile = _tile_from_index(out.width, idx)
					reachable = _remove_index(reachable, idx)
			if tile.x >= 0 and f.scene != null:
				out.spawns.append({"feature": f.scene, "feature_data": f.data, "tile": tile})


## Room-centre tile, or the nearest reachable tile when the centre is blocked ((-1,-1) if the
## room has no reachable tile at all). Deterministic — no RNG — so features never move.
static func _feature_tile(out: RoomOutput) -> Vector2i:
	var cx := out.width >> 1
	var cy := out.height >> 1
	if out.reachability_map[cy * out.width + cx] == 1:
		return Vector2i(cx, cy)
	var best := Vector2i(-1, -1)
	var best_d := 0x7fffffffffffffff
	for y in out.height:
		for x in out.width:
			if out.reachability_map[y * out.width + x] == 1:
				var dd := (x - cx) * (x - cx) + (y - cy) * (y - cy)
				if dd < best_d:
					best_d = dd
					best = Vector2i(x, y)
	return best


## Integer cumulative-weight pick; null on an empty/zero-weight pool (consumes no draw then).
static func _weighted_pick(rng: RandomNumberGenerator, table: Array) -> Variant:
	var total := 0
	for e in table:
		total += e.weight
	if total <= 0:
		return null
	var roll := rng.randi_range(0, total - 1)
	for e in table:
		roll -= e.weight
		if roll < 0:
			return e
	return table[table.size() - 1]


## Every reachable tile at least `dist2`-clear (squared) of every opening, row-major.
static func _door_clear_candidates(out: RoomOutput, ox: PackedInt32Array, oy: PackedInt32Array,
		dist2: int) -> PackedInt32Array:
	var candidates := PackedInt32Array()
	for y in out.height:
		for x in out.width:
			if out.reachability_map[y * out.width + x] != 1:
				continue
			var clear := true
			for i in ox.size():
				var dx := ox[i] - x
				var dy := oy[i] - y
				if dx * dx + dy * dy < dist2:
					clear = false
					break
			if clear:
				candidates.append(y * out.width + x)
	return candidates


## Every reachable tile, row-major, no door-distance filter (used by features).
static func _reachable_candidates(out: RoomOutput) -> PackedInt32Array:
	var candidates := PackedInt32Array()
	for y in out.height:
		for x in out.width:
			if out.reachability_map[y * out.width + x] == 1:
				candidates.append(y * out.width + x)
	return candidates


## Subset of `candidates` that is 4-adjacent to a WALL or BLOCKER tile, order preserved.
static func _filter_near_wall(out: RoomOutput, candidates: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for idx in candidates:
		var t := _tile_from_index(out.width, idx)
		if _touches_wall(out, t.x, t.y):
			result.append(idx)
	return result


static func _touches_wall(out: RoomOutput, x: int, y: int) -> bool:
	var neighbours := [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]
	for n in neighbours:
		if n.x < 0 or n.y < 0 or n.x >= out.width or n.y >= out.height:
			continue
		var cls := out.tile_grid[n.y * out.width + n.x]
		if cls == RoomBuilder.WALL or cls == RoomBuilder.BLOCKER:
			return true
	return false


## Order-preserving filter dropping every candidate within squared distance < dist2 of `tile`.
static func _remove_within(candidates: PackedInt32Array, tile: Vector2i, width: int,
		dist2: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for idx in candidates:
		var t := _tile_from_index(width, idx)
		var dx := t.x - tile.x
		var dy := t.y - tile.y
		if dx * dx + dy * dy >= dist2:
			result.append(idx)
	return result


## Order-preserving filter keeping only candidates within squared distance ≤ max_dist2 of `centre`.
static func _filter_within(candidates: PackedInt32Array, centre: Vector2i, width: int,
		max_dist2: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	for idx in candidates:
		var t := _tile_from_index(width, idx)
		var dx := t.x - centre.x
		var dy := t.y - centre.y
		if dx * dx + dy * dy <= max_dist2:
			result.append(idx)
	return result


## Order-preserving filter dropping exactly one candidate index.
static func _remove_index(candidates: PackedInt32Array, idx_to_remove: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for idx in candidates:
		if idx != idx_to_remove:
			result.append(idx)
	return result


static func _tile_from_index(width: int, idx: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(idx % width, idx / width)
