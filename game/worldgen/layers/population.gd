class_name Population
## Layer 4 (spec §9): enemy groups and loot for one room, as data only — no nodes, no scenes.
## Runs as pipeline step 7 with its OWN RNG seeded [world_seed, NS_POPULATION, slot_x, slot_y]
## (no attempt index): spawn IDENTITY — group count, enemy ids, group sizes, entity_ids — is
## invariant under interior retries; only positions re-sample against the final reachability
## map. Draw order is fixed (spec §4.2): groups → per group (weighted pick, size, per-entity
## tile) → loot count → per loot (weighted pick, tile). An empty table consumes no draws
## (tables are config, so the stream is stable for a given CONFIG_HASH).
extends RefCounted

const MIN_SPAWN_DIST2 := 4      # ≥ 2 tiles from other spawns
const PLACE_ATTEMPTS := 100


static func populate(out: RoomOutput, spec: RoomSpec, config: GenConfig, world_seed: int,
		openings: PackedInt32Array) -> void:
	out.spawns = []
	var rt := config.room_type_by_id(spec.type_id)
	var biome := config.biome_by_id(spec.biome_id)
	if rt == null or biome == null:
		return
	var rng := config.rng_for([world_seed, WgHash.NS_POPULATION,
			spec.origin_slot.x, spec.origin_slot.y] as Array[int])

	var ox := PackedInt32Array()
	var oy := PackedInt32Array()
	for i in openings.size():
		ox.append(openings[i] % out.width)
		@warning_ignore("integer_division")
		oy.append(openings[i] / out.width)
	var sx := PackedInt32Array()   # placed spawn positions
	var sy := PackedInt32Array()

	# Phase 1 — IDENTITY: group count, weighted picks, group sizes, loot picks. No position
	# draws happen until the whole identity list exists, so identity never depends on the
	# reachability map and survives interior retries (spec §9 preamble).
	var identities: Array = []   # of {"enemy_id": ...} / {"item_id": ...}
	var spawn_entries: Array = _entries_for(biome.spawn_tables, spec.type_id, "enemies")
	var groups := rng.randi_range(rt.enemy_groups_min, rt.enemy_groups_max)
	for _g in groups:
		var entry: SpawnTableEntry = _weighted_pick(rng, spawn_entries)
		if entry == null:
			continue
		var size := rng.randi_range(entry.group_min, entry.group_max)
		for _s in size:
			identities.append({"enemy_id": entry.enemy_id})
	var loot_entries: Array = _entries_for(biome.loot_tables, spec.type_id, "items")
	var loot_count := rng.randi_range(rt.loot_min, rt.loot_max)
	for _l in loot_count:
		var entry: LootTableEntry = _weighted_pick(rng, loot_entries)
		if entry == null:
			continue
		identities.append({"item_id": entry.item_id})

	# Phase 2 — POSITIONS: rejection-sample against this attempt's reachability map, in
	# identity order. Only these draws (and the resulting positions) may vary across retries.
	var opening_dist2 := config.spawn_min_dist_from_doors * config.spawn_min_dist_from_doors
	for ident in identities:
		var tile := _sample_tile(rng, out, ox, oy, sx, sy, opening_dist2)
		if tile.x < 0:
			continue   # 100 attempts exhausted — entity skipped (spec §9.3)
		sx.append(tile.x)
		sy.append(tile.y)
		ident["tile"] = tile
		out.spawns.append(ident)

	# Stable entity ids by list index (spec §4.5).
	for i in out.spawns.size():
		out.spawns[i]["entity_id"] = config.seed_for([world_seed, WgHash.NS_POPULATION,
				spec.origin_slot.x, spec.origin_slot.y, i] as Array[int])


## The entry list of the FIRST table matching room_type ([] if none). `field` is the entry
## array's property name — "enemies" on RoomSpawnTable, "items" on RoomLootTable.
static func _entries_for(tables: Array, room_type: StringName, field: String) -> Array:
	for t in tables:
		if t != null and t.room_type == room_type:
			return t.get(field)
	return []


## Integer cumulative-weight pick; null on an empty/zero-weight table (consumes no draw then).
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


## Rejection-sample a reachable tile ≥ spawn_min_dist_from_doors tiles from every opening and
## ≥2 from other spawns; (-1,-1) when 100 attempts exhaust (spec §9.3).
static func _sample_tile(rng: RandomNumberGenerator, out: RoomOutput,
		ox: PackedInt32Array, oy: PackedInt32Array,
		sx: PackedInt32Array, sy: PackedInt32Array, opening_dist2: int) -> Vector2i:
	for _a in PLACE_ATTEMPTS:
		var x := rng.randi_range(0, out.width - 1)
		var y := rng.randi_range(0, out.height - 1)
		if out.reachability_map[y * out.width + x] == 0:
			continue
		var ok := true
		for i in ox.size():
			var dx := ox[i] - x
			var dy := oy[i] - y
			if dx * dx + dy * dy < opening_dist2:
				ok = false
				break
		if not ok:
			continue
		for i in sx.size():
			var dx := sx[i] - x
			var dy := sy[i] - y
			if dx * dx + dy * dy < MIN_SPAWN_DIST2:
				ok = false
				break
		if ok:
			return Vector2i(x, y)
	return Vector2i(-1, -1)
