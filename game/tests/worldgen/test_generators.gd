extends Node
## Headless tests for Layer 3 with all structure generators + decoration. Covers every
## room type × merge shape across seeds:
## validation within max_room_retries, opening reachability, PROTECTED star, world-edge
## sealing, determinism per generator, fallback ladder, and a per-generator stats table
## (rooms, retry rate, mean reachable-floor ratio, mean build time — budget 10 ms).
## Run: godot --headless --path game res://tests/worldgen/test_generators.tscn

const SEEDS := 100


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://worldgen/content/gen_config.tres")
	var max_x := config.world_width_biomes * config.biome_slots
	var max_y := config.world_height_biomes() * config.biome_slots

	# gen_id -> [rooms, retried, fallbacks, ratio_sum, usec, determinism_checks]
	var stats := {}
	var built := 0
	for i in SEEDS:
		if i % 20 == 0:
			print("  seed %d/%d (%d rooms)" % [i, SEEDS, built])
		var seed := 32_452_843 * i + 7
		var world := WorldLayout.build(seed, config)
		var bc := Vector2i(i % config.world_width_biomes,
				(i / config.world_width_biomes) % config.world_height_biomes())
		var graph := RoomGraph.build(world, bc, config)

		# One unit per (type, shape) combo in this biome; plus the shrine's host unit
		# (world-unique — it usually lives in another biome).
		var picked := {}
		for u in graph.rooms:
			var key := "%s|%dx%d" % [u.type_id, u.size_slots.x, u.size_slots.y]
			if not picked.has(key):
				picked[key] = u
		var units: Array = []
		for key in ["traversal", "field", "cave_pocket", "arena", "shrine"]:
			for shape in ["1x1", "2x1", "1x2", "2x2"]:
				if picked.has("%s|%s" % [key, shape]):
					units.append(picked["%s|%s" % [key, shape]])
		var ur: WorldSpec.UniqueRoom = world.unique_rooms[0]
		if ur.biome_coord != bc:
			var sg := RoomGraph.build(world, ur.biome_coord, config)
			units.append(sg.room_at(ur.local_slot))

		for u in units:
			var rt := config.room_type_by_id(u.type_id)
			var gen_id := _gen_name(rt)
			if not stats.has(gen_id):
				stats[gen_id] = [0, 0, 0, 0.0, 0, 0]
			var t0 := Time.get_ticks_usec()
			var out := RoomBuilder.build(u, config, seed)
			var s: Array = stats[gen_id]
			s[4] += Time.get_ticks_usec() - t0
			s[0] += 1
			built += 1
			if out.attempt_used > 0:
				s[1] += 1
			if out.attempt_used >= config.max_room_retries:
				s[2] += 1
			var total := out.width * out.height
			var ratio := out.reachability_map.count(1) / float(total)
			s[3] += ratio
			if ratio < config.min_reachable_floor_ratio:
				fails.append("floor ratio %.2f below min (seed %d %s)" % [ratio, seed, u.type_id])

			var openings := RoomBuilder._opening_tiles(u, out.width, out.height)
			for j in openings.size():
				if out.reachability_map[openings[j]] == 0:
					fails.append("opening unreachable (seed %d %s unit %s)" % [seed, u.type_id, u.origin_slot])
					break
				if out.protected_map[openings[j]] == 0:
					fails.append("opening not PROTECTED (seed %d %s)" % [seed, u.type_id])
					break
			if not openings.is_empty() and not _star_connected(out, openings):
				fails.append("PROTECTED star broken (seed %d %s)" % [seed, u.type_id])
			_check_world_edges(out, u, max_x, max_y, fails, seed)

			# Determinism per generator, sampled.
			if s[0] % 10 == 1:
				s[5] += 1
				var out2 := RoomBuilder.build(u, config, seed)
				if out2.tile_grid != out.tile_grid or out2.reachability_map != out.reachability_map:
					fails.append("rebuild not byte-identical (seed %d %s)" % [seed, u.type_id])

			if not fails.is_empty():
				break
		if not fails.is_empty():
			break

	print("generator          rooms  retry%%  fallback  mean_ratio  mean_ms  det_checks")
	var total_fallbacks := 0
	for gen_id in ["(none)", "RoomGenScatter", "RoomGenCave", "RoomGenArena"]:
		if not stats.has(gen_id):
			fails.append("generator '%s' never exercised" % gen_id)
			continue
		var s: Array = stats[gen_id]
		total_fallbacks += s[2]
		print("%-16s %6d  %5.1f  %8d  %10.2f  %7.2f  %10d"
				% [gen_id, s[0], 100.0 * s[1] / s[0], s[2], s[3] / s[0], s[4] / 1000.0 / s[0], s[5]])
	# ≥ 99.9% of rooms validate within max_room_retries (i.e. no fallback).
	if built > 0 and total_fallbacks / float(built) > 0.001:
		fails.append("fallback rate too high: %d/%d" % [total_fallbacks, built])

	# Forced fallback (test-only) must validate for every room type.
	var world := WorldLayout.build(424242, config)
	for bx in config.world_width_biomes:
		for by in config.world_height_biomes():
			var graph := RoomGraph.build(world, Vector2i(bx, by), config)
			var done := {}
			for u in graph.rooms:
				if done.has(u.type_id):
					continue
				done[u.type_id] = true
				var out := RoomBuilder.build(u, config, 424242, true)
				var openings := RoomBuilder._opening_tiles(u, out.width, out.height)
				for j in openings.size():
					if out.reachability_map[openings[j]] == 0:
						fails.append("fallback opening unreachable (%s)" % u.type_id)
						break
	print("forced fallback validated for all room types")

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


## Assert world-edge sides are fully walled with no passages.
func _check_world_edges(out: RoomOutput, u: RoomSpec,
		max_x: int, max_y: int, fails: Array[String], seed: int) -> void:
	var w := out.width
	var h := out.height
	var edge_sides: Array[int] = []
	if u.origin_slot.y == 0:
		edge_sides.append(WorldSpec.SIDE_NORTH)
	if u.origin_slot.x == 0:
		edge_sides.append(WorldSpec.SIDE_WEST)
	if u.origin_slot.x + u.size_slots.x == max_x:
		edge_sides.append(WorldSpec.SIDE_EAST)
	if u.origin_slot.y + u.size_slots.y == max_y:
		edge_sides.append(WorldSpec.SIDE_SOUTH)
	for side in edge_sides:
		for p in u.passages:
			if p.side == side:
				fails.append("passage on world-edge side (seed %d unit %s)" % [seed, u.origin_slot])
		var ok := true
		match side:
			WorldSpec.SIDE_NORTH:
				for x in w:
					ok = ok and out.tile_grid[x] == RoomBuilder.WALL
			WorldSpec.SIDE_SOUTH:
				for x in w:
					ok = ok and out.tile_grid[(h - 1) * w + x] == RoomBuilder.WALL
			WorldSpec.SIDE_WEST:
				for y in h:
					ok = ok and out.tile_grid[y * w] == RoomBuilder.WALL
			WorldSpec.SIDE_EAST:
				for y in h:
					ok = ok and out.tile_grid[y * w + w - 1] == RoomBuilder.WALL
		if not ok:
			fails.append("world-edge side not fully walled (seed %d unit %s side %d)"
					% [seed, u.origin_slot, side])
