extends Node
## Headless tests for Layer 3 with all structure generators + decoration. Covers every
## room type × leaf shape across seeds. The pipeline is single-attempt + repair now, so the
## invariants are HARD: every opening reachable, EVERY walkable tile reachable (repair seals or
## connects every pocket), floor ratio met, PROTECTED star intact, void sides sealed,
## byte-identical rebuilds. Plus a per-generator stats table (rooms, mean reachable-floor
## ratio, mean build time).
## Run: godot --headless --path game res://tests/worldgen/test_generators.tscn

const SEEDS := 100


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://world_content/gen_config.tres")

	# gen_id -> [rooms, ratio_sum, usec, determinism_checks]
	var stats := {}
	var built := 0
	for i in SEEDS:
		if i % 20 == 0:
			print("  seed %d/%d (%d rooms)" % [i, SEEDS, built])
		var seed_v := 32_452_843 * i + 7
		var world := WorldLayout.build(seed_v, config)

		# One room per (type, shape) combo per biome; the world-unique shrine host is always
		# included via its own graph.
		var units: Array = []
		var picked := {}
		for p in world.placements:
			var graph := RoomGraph.build(world, p.id, config)
			for u in graph.rooms:
				var key := "%s|%dx%d" % [u.type_id, u.size_slots.x, u.size_slots.y]
				if not picked.has(key):
					picked[key] = true
					units.append(u)

		for u in units:
			var rt := config.room_type_by_id(u.type_id)
			var gen_id := _gen_name(rt)
			if not stats.has(gen_id):
				stats[gen_id] = [0, 0.0, 0, 0]
			var t0 := Time.get_ticks_usec()
			var out := RoomBuilder.build(u, config, seed_v)
			var s: Array = stats[gen_id]
			s[2] += Time.get_ticks_usec() - t0
			s[0] += 1
			built += 1
			var total := out.width * out.height
			var ratio := out.reachability_map.count(1) / float(total)
			s[1] += ratio
			if ratio < config.min_reachable_floor_ratio:
				fails.append("floor ratio %.2f below min (seed %d %s)" % [ratio, seed_v, u.type_id])

			# HARD post-repair invariant: no unreachable walkable tile anywhere.
			for j in total:
				var cls := out.tile_grid[j]
				if (cls == RoomBuilder.FLOOR or cls == RoomBuilder.DECOR_FLOOR) \
						and out.reachability_map[j] == 0:
					fails.append("unreachable walkable tile at %d (seed %d %s %s)"
							% [j, seed_v, u.type_id, u.origin_slot])
					break

			var openings := RoomBuilder._opening_tiles(u, out.width, out.height)
			for j in openings.size():
				if out.reachability_map[openings[j]] == 0:
					fails.append("opening unreachable (seed %d %s unit %s)" % [seed_v, u.type_id, u.origin_slot])
					break
				if out.protected_map[openings[j]] == 0:
					fails.append("opening not PROTECTED (seed %d %s)" % [seed_v, u.type_id])
					break
			if not openings.is_empty() and not _star_connected(out, openings):
				fails.append("PROTECTED star broken (seed %d %s)" % [seed_v, u.type_id])
			_check_void_sides(out, u, fails, seed_v)

			# Determinism per generator, sampled.
			if s[0] % 10 == 1:
				s[3] += 1
				var out2 := RoomBuilder.build(u, config, seed_v)
				if out2.tile_grid != out.tile_grid or out2.reachability_map != out.reachability_map:
					fails.append("rebuild not byte-identical (seed %d %s)" % [seed_v, u.type_id])

			if not fails.is_empty():
				break
		if not fails.is_empty():
			break

	print("generator          rooms  mean_ratio  mean_ms  det_checks")
	for gen_id in ["(none)", "RoomGenScatter", "RoomGenCave", "RoomGenArena"]:
		if not stats.has(gen_id):
			fails.append("generator '%s' never exercised" % gen_id)
			continue
		var s: Array = stats[gen_id]
		print("%-16s %6d  %10.2f  %7.2f  %10d"
				% [gen_id, s[0], s[1] / s[0], s[2] / 1000.0 / s[0], s[3]])

	if fails.is_empty():
		print("ALL PASS")
	else:
		for f in fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % fails.size())
	get_tree().quit(0 if fails.is_empty() else 1)


## Stats key for a room type's generator: its class name, or "(none)" for empty rooms.
func _gen_name(rt: RoomTypeDef) -> String:
	if rt == null or rt.generator == null:
		return "(none)"
	return String(rt.generator.get_script().get_global_name())


## BFS over PROTECTED tiles only, from the room center; true iff every opening is reached.
func _star_connected(out: RoomOutput, openings: PackedInt32Array) -> bool:
	var w := out.width
	var start := (out.height >> 1) * w + (w >> 1)
	if out.protected_map[start] == 0:
		return false
	var seen := PackedByteArray()
	seen.resize(out.protected_map.size())
	var stack := PackedInt32Array()
	stack.resize(out.protected_map.size())
	var sp := 0
	stack[sp] = start
	sp += 1
	seen[start] = 1
	var size := seen.size()
	var prot := out.protected_map
	while sp > 0:
		sp -= 1
		var idx := stack[sp]
		var x := idx % w
		if x > 0 and seen[idx - 1] == 0 and prot[idx - 1] == 1:
			seen[idx - 1] = 1
			stack[sp] = idx - 1
			sp += 1
		if x < w - 1 and seen[idx + 1] == 0 and prot[idx + 1] == 1:
			seen[idx + 1] = 1
			stack[sp] = idx + 1
			sp += 1
		if idx >= w and seen[idx - w] == 0 and prot[idx - w] == 1:
			seen[idx - w] = 1
			stack[sp] = idx - w
			sp += 1
		if idx + w < size and seen[idx + w] == 0 and prot[idx + w] == 1:
			seen[idx + w] = 1
			stack[sp] = idx + w
			sp += 1
	for j in openings.size():
		if seen[openings[j]] == 0:
			return false
	return true


## Void sides (RoomSpec.void_sides — world edge or unclaimed neighbouring cell along at least
## one slot) must keep a walled perimeter row/column everywhere EXCEPT protected opening tiles:
## a room straddling two macro-cells can be void along part of a side and legitimately carry an
## external door toward a real biome on the rest, so openings are exempt — but nothing else
## (erosion, generators, repair) may breach the ring.
func _check_void_sides(out: RoomOutput, u: RoomSpec, fails: Array[String], seed_v: int) -> void:
	var w := out.width
	var h := out.height
	for side in [WorldSpec.SIDE_NORTH, WorldSpec.SIDE_EAST, WorldSpec.SIDE_SOUTH, WorldSpec.SIDE_WEST]:
		if (u.void_sides & (1 << side)) == 0:
			continue
		var ok := true
		match side:
			WorldSpec.SIDE_NORTH:
				for x in w:
					ok = ok and (out.tile_grid[x] == RoomBuilder.WALL or out.protected_map[x] == 1)
			WorldSpec.SIDE_SOUTH:
				for x in w:
					var idx := (h - 1) * w + x
					ok = ok and (out.tile_grid[idx] == RoomBuilder.WALL or out.protected_map[idx] == 1)
			WorldSpec.SIDE_WEST:
				for y in h:
					var idx := y * w
					ok = ok and (out.tile_grid[idx] == RoomBuilder.WALL or out.protected_map[idx] == 1)
			_:
				for y in h:
					var idx := y * w + w - 1
					ok = ok and (out.tile_grid[idx] == RoomBuilder.WALL or out.protected_map[idx] == 1)
		if not ok:
			fails.append("void side breached outside an opening (seed %d unit %s side %d)"
					% [seed_v, u.origin_slot, side])
