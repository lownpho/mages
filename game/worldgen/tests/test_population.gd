extends Node
## Headless tests for Layer 4 population: determinism, retry-independence of
## spawn identity, distance constraints, budgets, empty traversal rooms, and world-wide
## entity-id uniqueness. Run:
##   godot --headless --path game res://worldgen/tests/test_population.tscn

const SEEDS := 60


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://worldgen/content/gen_config.tres")

	var checked := 0
	var with_spawns := 0
	for i in SEEDS:
		if i % 20 == 0:
			print("  seed %d/%d" % [i, SEEDS])
		var seed := 49_979_687 * i + 13
		var world := WorldLayout.build(seed, config)
		var bc := Vector2i(i % config.world_width_biomes,
				(i / config.world_width_biomes) % config.world_height_biomes())
		var graph := RoomGraph.build(world, bc, config)

		var picked := {}
		for u in graph.rooms:
			if not picked.has(u.type_id):
				picked[u.type_id] = u
		for type_id in picked:
			var u: RoomSpec = picked[type_id]
			var rt := config.room_type_by_id(u.type_id)
			var out := RoomBuilder.build(u, config, seed)
			checked += 1
			if not out.spawns.is_empty():
				with_spawns += 1

			# Budget: groups*group_max bounds enemies (feature entries share the spawns array — skip them).
			var enemies := 0
			for sp in out.spawns:
				if sp.has("enemy_id"):
					enemies += 1
			var max_group := 0
			for t in config.biome_by_id(u.biome_id).spawn_tables:
				if t.room_type == u.type_id:
					for e in t.enemies:
						max_group = maxi(max_group, e.group_max)
			if enemies > rt.enemy_groups_max * max_group:
				fails.append("enemy count over budget (seed %d %s)" % [seed, u.type_id])
			if u.type_id == &"traversal" and not out.spawns.is_empty():
				fails.append("traversal room populated (seed %d)" % seed)

			# Distance constraints apply to ENEMIES only (feature entries aren't subject to the
			# door-distance / anti-stacking rules — they're placed deterministically at the centre).
			var openings := RoomBuilder._opening_tiles(u, out.width, out.height)
			for a in out.spawns.size():
				if not out.spawns[a].has("enemy_id"):
					continue
				var ta: Vector2i = out.spawns[a]["tile"]
				if out.reachability_map[ta.y * out.width + ta.x] == 0:
					fails.append("spawn on unreachable tile (seed %d %s)" % [seed, u.type_id])
				for j in openings.size():
					var dx := openings[j] % out.width - ta.x
					var dy := openings[j] / out.width - ta.y
					if dx * dx + dy * dy < config.spawn_min_dist_from_doors * config.spawn_min_dist_from_doors:
						fails.append("spawn %d tiles from opening (seed %d %s)" % [dx * dx + dy * dy, seed, u.type_id])
						break
				for b in range(a + 1, out.spawns.size()):
					if not out.spawns[b].has("enemy_id"):
						continue
					var tb: Vector2i = out.spawns[b]["tile"]
					var dx2 := tb.x - ta.x
					var dy2 := tb.y - ta.y
					if dx2 * dx2 + dy2 * dy2 < Population.MIN_SPAWN_DIST2:
						fails.append("spawns stacked (seed %d %s)" % [seed, u.type_id])
						break

			# Determinism: rebuild → identical spawns (ids, kinds, positions).
			var out2 := RoomBuilder.build(u, config, seed)
			if not _spawns_equal(out.spawns, out2.spawns, true):
				fails.append("spawns differ on rebuild (seed %d %s)" % [seed, u.type_id])

			# Retry independence: forced fallback re-rolls the interior but
			# spawn IDENTITY (order, kind, id, entity_id) must be unchanged; positions may move.
			var out3 := RoomBuilder.build(u, config, seed, true)
			if not _spawns_equal(out.spawns, out3.spawns, false):
				fails.append("spawn identity changed under retries (seed %d %s)" % [seed, u.type_id])

			if not fails.is_empty():
				break
		if not fails.is_empty():
			break
	print("population: %d rooms checked (%d with spawns) over %d seeds" % [checked, with_spawns, SEEDS])
	if with_spawns == 0:
		fails.append("no room ever spawned anything — tables broken?")

	# Entity ids unique across a whole biome (all units, one seed per biome cell).
	var world := WorldLayout.build(31337, config)
	var seen := {}
	for by in config.world_height_biomes():
		for bx in config.world_width_biomes:
			var graph := RoomGraph.build(world, Vector2i(bx, by), config)
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


## Compare spawn lists; `with_positions` false compares identity only (kind, id, entity_id).
func _spawns_equal(a: Array, b: Array, with_positions: bool) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].get("enemy_id", &"") != b[i].get("enemy_id", &""):
			return false
		if a[i].get("entity_id", 0) != b[i].get("entity_id", 0):
			return false
		if with_positions and a[i].get("tile") != b[i].get("tile"):
			return false
	return true
