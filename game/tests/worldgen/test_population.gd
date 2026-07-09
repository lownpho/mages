extends Node
## Headless tests for Layer 4 population: determinism, guaranteed placement (candidate-set
## sampling never silently drops an entity while candidates remain), distance constraints,
## budgets, feature lists, empty traversal rooms, and world-wide entity-id uniqueness. Run:
##   godot --headless --path game res://tests/worldgen/test_population.tscn

const SEEDS := 60


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://world_content/gen_config.tres")

	var checked := 0
	var with_spawns := 0
	var with_features := 0
	for i in SEEDS:
		if i % 20 == 0:
			print("  seed %d/%d" % [i, SEEDS])
		var seed_v := 49_979_687 * i + 13
		var world := WorldLayout.build(seed_v, config)
		var placement: WorldSpec.BiomePlacement = world.placements[i % world.placements.size()]
		var graph := RoomGraph.build(world, placement.id, config)

		var picked := {}
		for u in graph.rooms:
			if not picked.has(u.type_id):
				picked[u.type_id] = u
		for type_id in picked:
			var u: RoomSpec = picked[type_id]
			var rt := config.room_type_by_id(u.type_id)
			var out := RoomBuilder.build(u, config, seed_v)
			checked += 1
			if not out.spawns.is_empty():
				with_spawns += 1

			# Budget: groups*group_max bounds enemies (feature entries share the spawns array — skip them).
			var enemies := 0
			var features := 0
			for sp in out.spawns:
				if sp.has("enemy_id"):
					enemies += 1
				elif sp.has("feature"):
					features += 1
			with_features += 1 if features > 0 else 0
			var max_group := 0
			for e in rt.enemies:
				max_group = maxi(max_group, e.group_max)
			var groups_cap := rt.enemy_groups_max
			if rt.scale_groups_with_size:
				groups_cap *= u.size_slots.x * u.size_slots.y
			if enemies > groups_cap * max_group:
				fails.append("enemy count over budget (seed %d %s)" % [seed_v, u.type_id])
			if rt.enemies.is_empty() and enemies > 0:
				fails.append("empty-pool room '%s' populated (seed %d)" % [u.type_id, seed_v])

			# Feature lists: per RoomFeature, count within [count_min, count_max] (null scenes
			# excluded); every feature tile reachable.
			var expected_min := 0
			var expected_max := 0
			for f in rt.features:
				if f != null and f.scene != null:
					expected_min += f.count_min
					expected_max += f.count_max
			if features < expected_min or features > expected_max:
				fails.append("feature count %d outside [%d, %d] (seed %d %s)"
						% [features, expected_min, expected_max, seed_v, u.type_id])
			for sp in out.spawns:
				if sp.has("feature"):
					var ft: Vector2i = sp["tile"]
					if out.reachability_map[ft.y * out.width + ft.x] == 0:
						fails.append("feature on unreachable tile (seed %d %s)" % [seed_v, u.type_id])

			# Every spawned enemy must come from the room type's OWN pool.
			for sp in out.spawns:
				if not sp.has("enemy_id"):
					continue
				var explained := false
				for e in rt.enemies:
					if e.enemy_id == sp["enemy_id"]:
						explained = true
				if not explained:
					fails.append("spawn '%s' not in room type's pool (seed %d %s)"
							% [sp["enemy_id"], seed_v, u.type_id])

			# GUARANTEED placement: with a non-empty pool, a positive budget, and any candidate
			# tile at all, at least one enemy must be placed — candidate-set sampling cannot
			# come up empty the way rejection sampling could.
			if not rt.enemies.is_empty() and groups_cap > 0 and rt.enemy_groups_min > 0 \
					and enemies == 0 and _has_candidate(out, u, config):
				fails.append("no enemy placed despite candidates (seed %d %s)" % [seed_v, u.type_id])

			# Distance constraints apply to ENEMIES only.
			var openings := RoomBuilder._opening_tiles(u, out.width, out.height)
			for a in out.spawns.size():
				if not out.spawns[a].has("enemy_id"):
					continue
				var ta: Vector2i = out.spawns[a]["tile"]
				if out.reachability_map[ta.y * out.width + ta.x] == 0:
					fails.append("spawn on unreachable tile (seed %d %s)" % [seed_v, u.type_id])
				for j in openings.size():
					var dx := openings[j] % out.width - ta.x
					@warning_ignore("integer_division")
					var dy := openings[j] / out.width - ta.y
					if dx * dx + dy * dy < config.spawn_min_dist_from_doors * config.spawn_min_dist_from_doors:
						fails.append("spawn %d tiles² from opening (seed %d %s)" % [dx * dx + dy * dy, seed_v, u.type_id])
						break
				for b in range(a + 1, out.spawns.size()):
					if not out.spawns[b].has("enemy_id"):
						continue
					var tb: Vector2i = out.spawns[b]["tile"]
					var dx2 := tb.x - ta.x
					var dy2 := tb.y - ta.y
					if dx2 * dx2 + dy2 * dy2 < Population.MIN_SPAWN_DIST2:
						fails.append("spawns stacked (seed %d %s)" % [seed_v, u.type_id])
						break

			# Determinism: rebuild → identical spawns (ids, kinds, positions).
			var out2 := RoomBuilder.build(u, config, seed_v)
			if not _spawns_equal(out.spawns, out2.spawns):
				fails.append("spawns differ on rebuild (seed %d %s)" % [seed_v, u.type_id])

			if not fails.is_empty():
				break
		if not fails.is_empty():
			break
	print("population: %d rooms checked (%d with spawns, %d with features) over %d seeds"
			% [checked, with_spawns, with_features, SEEDS])
	if with_spawns == 0:
		fails.append("no room ever spawned anything — pools broken?")
	if with_features == 0:
		fails.append("no room ever placed a feature — feature lists broken?")

	# Content lint: a room type with an enemy budget needs a non-empty pool (and vice versa),
	# or its rooms silently spawn nothing / its pool is dead weight.
	for rt in config.room_types:
		if rt.enemy_groups_max > 0 and rt.enemies.is_empty() and rt.unique_scope == RoomTypeDef.UniqueScope.NONE:
			fails.append("room type '%s' has an enemy budget but an empty pool" % rt.id)
		if rt.enemy_groups_max == 0 and not rt.enemies.is_empty():
			fails.append("room type '%s' has a pool but a zero budget" % rt.id)

	# Entity ids unique across the whole world (all rooms of every placed biome, one seed).
	var world := WorldLayout.build(31337, config)
	var seen := {}
	for p in world.placements:
		var graph := RoomGraph.build(world, p.id, config)
		for u in graph.rooms:
			var out := RoomBuilder.build(u, config, 31337)
			for sp in out.spawns:
				var eid: int = sp["entity_id"]
				if seen.has(eid):
					fails.append("entity_id collision: %d" % eid)
				seen[eid] = true
	print("entity ids: %d unique across the whole world" % seen.size())

	if fails.is_empty():
		print("ALL PASS")
	else:
		for f in fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % fails.size())
	get_tree().quit(0 if fails.is_empty() else 1)


## True when the room has at least one valid enemy candidate tile (reachable + far enough from
## every opening) — mirrors Population's candidate rule.
func _has_candidate(out: RoomOutput, u: RoomSpec, config: GenConfig) -> bool:
	var openings := RoomBuilder._opening_tiles(u, out.width, out.height)
	var d2 := config.spawn_min_dist_from_doors * config.spawn_min_dist_from_doors
	for y in out.height:
		for x in out.width:
			if out.reachability_map[y * out.width + x] == 0:
				continue
			var ok := true
			for j in openings.size():
				var dx := openings[j] % out.width - x
				@warning_ignore("integer_division")
				var dy := openings[j] / out.width - y
				if dx * dx + dy * dy < d2:
					ok = false
					break
			if ok:
				return true
	return false


## Compare spawn lists fully (kind, id, entity_id, position).
func _spawns_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].get("enemy_id", &"") != b[i].get("enemy_id", &""):
			return false
		if a[i].get("entity_id", 0) != b[i].get("entity_id", 0):
			return false
		if a[i].get("tile") != b[i].get("tile"):
			return false
	return true
