extends Node
## Benchmark for ticket 01 (worldgen-rewrite): headless, per-stage timings of the CURRENT
## generator — today's overworld and one mycelium dungeon floor, then the same pipeline scaled up
## (larger regions, more biomes). Report-only: prints median/p95/max per stage, does not assert.
##
## Run:
##   godot --headless --path game res://tests/worldgen/bench_generation_cost.tscn
##
## Findings drawn from one run of this script live at
## .scratch/worldgen-rewrite/research/01-generation-cost-baseline.md (see that file for the method,
## the numbers, and what they mean for ticket 07's per-frame budget).
##
## Stages measured, each via the same static entry points the real game/tests call:
##   - world layout   : WorldLayout.build()                    (layers/world_layout.gd)
##   - one biome graph: RoomGraph.build()  fresh, no cache      (layers/room_graph.gd)
##   - room build      : RoomBuilder.build()  interior+population combined (layers/room_builder.gd)
##   - population      : Population.populate() re-run standalone on the built room, isolating its
##                        own cost (RoomBuilder.build calls it as its last step — see build():~120)
##   - doors           : DoorLinks.build()  whole-world (layers/door_links.gd)
##   - signs           : SignLinks.build()  whole-world, sharing the doors call's graph cache, same
##                        as WorldStreamer.build_world()'s single _room_graphs instance
##   - chunk assembly  : WorldStreamer.assemble_chunk()  cold (room cache cleared) vs warm
##                        (cached), same op test_streaming.gd times for "chunk assembly (cached)"
##
## Scaling knobs are applied to an in-memory duplicate of the loaded config only — nothing here
## touches committed content (world_content/*.tres stays untouched on disk).

const WORLD_SEEDS := 24    ## whole-world stage samples (layout, one graph, doors, signs)
const ROOM_SAMPLES := 80   ## per-room stage samples (room build, population)
const CHUNK_SAMPLES := 60  ## per-chunk stage samples (cold, warm)


func _ready() -> void:
	print("=== ticket 01: generation cost baseline ===")
	print("Godot %s, --headless, one process on the dev machine (not a web export)."
			% Engine.get_version_info().string)
	print("Figures are median / p95 / max over N independent samples, milliseconds.\n")

	var t0 := Time.get_ticks_usec()
	var overworld: GenConfig = load("res://world_content/gen_config.tres")
	var cold_load_us := Time.get_ticks_usec() - t0
	print("-- cold resource load (first .tres parse this process; amortised once per run) --")
	print("gen_config.tres load          : %.3f ms" % (cold_load_us / 1000.0))

	var t1 := Time.get_ticks_usec()
	overworld.compute_hash()
	print("CONFIG_HASH fold (first call) : %.3f ms  (cached for every seed_for() after)"
			% ((Time.get_ticks_usec() - t1) / 1000.0))

	var t2 := Time.get_ticks_usec()
	var mycelium: GenConfig = load("res://world_content/mycelium_gen_config.tres")
	print("mycelium_gen_config.tres load  : %.3f ms" % ((Time.get_ticks_usec() - t2) / 1000.0))
	var floor1: GenConfig = DungeonFloors.config_for(mycelium, 1)
	floor1.compute_hash()

	print("\n=== overworld (today): %d biomes, biome_slots=%d, world_width_cells=%d, room_slot_tiles=%d, chunk_tiles=%d ==="
			% [overworld.biomes.size(), overworld.biome_slots, overworld.world_width_cells,
			overworld.room_slot_tiles, overworld.chunk_tiles])
	_bench_config(overworld)

	print("\n=== mycelium floor 1 (dungeon): %d biome(s), biome_slots=%d, world_width_cells=%d ==="
			% [floor1.biomes.size(), floor1.biome_slots, floor1.world_width_cells])
	_bench_config(floor1)

	print("\n=== scaling: larger regions (biome_slots up), same %d biomes ===" % overworld.biomes.size())
	for mult in [2, 4]:
		var slots: int = overworld.biome_slots * mult
		var c := _scaled_region_config(overworld, slots)
		print("\n-- region x%d: biome_slots=%d (region area x%d) --" % [mult, slots, mult * mult])
		_bench_config(c)

	print("\n=== scaling: more biomes (synthetic duplicates of the authored set), biome_slots=%d ==="
			% overworld.biome_slots)
	for mult in [2, 4]:
		var c := _scaled_biome_count_config(overworld, mult)
		print("\n-- biomes x%d: %d biomes total --" % [mult, c.biomes.size()])
		_bench_config(c)

	print("\n=== chunk assembly / blit (Layer 5), cold (room cache cleared) vs warm (cached) ===")
	_bench_chunks("overworld baseline", overworld)
	_bench_chunks("mycelium floor 1", floor1)
	_bench_chunks("region x4", _scaled_region_config(overworld, overworld.biome_slots * 4))

	print("\n=== DONE ===")
	get_tree().quit(0)


## World layout, one fresh biome graph, room build + population, doors, signs — for one config.
func _bench_config(config: GenConfig) -> void:
	var layout_us: Array = []
	var graph_us: Array = []
	var doors_us: Array = []
	var signs_us: Array = []
	var room_counts: Array = []
	var first_biome: StringName = config.biomes[0].id

	var room_specs: Array = []       # every RoomSpec from world #0, for the room-build stage below
	var room_bench_seed := 0
	var footprint := ""

	for i in WORLD_SEEDS:
		var seed_v := 1_000_003 * i + 17

		var t0 := Time.get_ticks_usec()
		var spec := WorldLayout.build(seed_v, config)
		layout_us.append(Time.get_ticks_usec() - t0)
		if spec == null:
			push_error("bench: layout failed at seed %d (config bug, see validate())" % seed_v)
			continue

		var t1 := Time.get_ticks_usec()
		RoomGraph.build(spec, first_biome, config)   # fresh — no cache, mirrors test_streaming's L2
		graph_us.append(Time.get_ticks_usec() - t1)

		# Doors first (pays for every biome's graph, like WorldStreamer's shared _room_graphs),
		# signs second (hits that same cache) — the real read-through order build_world() uses.
		var graphs := RoomGraph.new()
		var t2 := Time.get_ticks_usec()
		DoorLinks.build(spec, config, seed_v, graphs)
		doors_us.append(Time.get_ticks_usec() - t2)
		var t3 := Time.get_ticks_usec()
		SignLinks.build(spec, config, seed_v, graphs)
		signs_us.append(Time.get_ticks_usec() - t3)

		# Room count + specs for the room-build stage: read back from `graphs`, now fully warm
		# from the doors call above — these are cache hits, not fresh builds.
		var total_rooms := 0
		for p in spec.placements:
			var g: BiomeGraph = graphs.get_biome_graph(spec, p.id, config)
			total_rooms += g.rooms.size()
			if i == 0:
				room_specs.append_array(g.rooms)
		room_counts.append(total_rooms)
		if i == 0:
			room_bench_seed = seed_v
			var wtiles := Vector2i(spec.grid_w, spec.grid_h) * config.biome_slots * config.room_slot_tiles
			footprint = "world %dx%d macro-cells, %dx%d tiles, ~%d chunks (chunk_tiles=%d)" % [
					spec.grid_w, spec.grid_h, wtiles.x, wtiles.y,
					maxi(1, wtiles.x / config.chunk_tiles) * maxi(1, wtiles.y / config.chunk_tiles),
					config.chunk_tiles]

	var room_us: Array = []
	var pop_us: Array = []
	for i in ROOM_SAMPLES:
		if room_specs.is_empty():
			break
		var spec: RoomSpec = room_specs[i % room_specs.size()]
		var t0 := Time.get_ticks_usec()
		var out := RoomBuilder.build(spec, config, room_bench_seed)
		room_us.append(Time.get_ticks_usec() - t0)

		# Population isolated: re-run it standalone on the finished room (it only overwrites
		# out.spawns — safe to call twice) to split its cost out of the combined figure above.
		var openings := RoomBuilder._opening_tiles(spec, out.width, out.height)
		var t1 := Time.get_ticks_usec()
		Population.populate(out, spec, config, room_bench_seed, openings)
		pop_us.append(Time.get_ticks_usec() - t1)

	print(footprint)
	print("rooms/world (median)          : %d" % _median_int(room_counts))
	print("world layout                  : %s" % _fmt(_stats(layout_us)))
	print("one biome graph (fresh)        : %s" % _fmt(_stats(graph_us)))
	print("room build (interior+populate): %s" % _fmt(_stats(room_us)))
	print("  population (isolated re-run): %s" % _fmt(_stats(pop_us)))
	print("doors  (DoorLinks, whole-world): %s" % _fmt(_stats(doors_us)))
	print("signs  (SignLinks, whole-world): %s" % _fmt(_stats(signs_us)))


func _bench_chunks(label: String, config: GenConfig) -> void:
	var streamer := WorldStreamer.new()
	streamer.config = config
	streamer.build_world(918_273_645)
	if streamer.world_spec == null:
		print("%s: skipped (invalid config)" % label)
		streamer.free()
		return

	var wtiles := Vector2i(streamer.world_spec.grid_w, streamer.world_spec.grid_h) \
			* config.biome_slots * config.room_slot_tiles
	var wchunks := Vector2i(maxi(1, wtiles.x / config.chunk_tiles), maxi(1, wtiles.y / config.chunk_tiles))
	@warning_ignore("integer_division")
	var mid := Vector2i(wchunks.x / 2, wchunks.y / 2)

	# Warm the world-level, once-per-world structures (door/sign links) BEFORE timing, so the
	# "cold" loop below measures only room (re)generation + blit — not the one-time link build,
	# which is already reported separately under doors/signs above.
	streamer.door_links()
	streamer.sign_links()

	var cold_us: Array = []
	for i in CHUNK_SAMPLES:
		streamer.clear_room_cache()
		var t0 := Time.get_ticks_usec()
		var c := streamer.assemble_chunk(mid.x, mid.y)
		cold_us.append(Time.get_ticks_usec() - t0)
		c.free()

	streamer.assemble_chunk(mid.x, mid.y).free()   # warm the cache back up
	var warm_us: Array = []
	for i in CHUNK_SAMPLES:
		var t0 := Time.get_ticks_usec()
		var c := streamer.assemble_chunk(mid.x, mid.y)
		warm_us.append(Time.get_ticks_usec() - t0)
		c.free()

	print("%s: chunk_tiles=%d, world %dx%d chunks" % [label, config.chunk_tiles, wchunks.x, wchunks.y])
	print("  cold (rooms uncached, world links warm): %s" % _fmt(_stats(cold_us)))
	print("  warm (rooms cached)                    : %s" % _fmt(_stats(warm_us)))
	streamer.free()


## In-memory only: same biomes, bigger regions. Larger biome_slots only relaxes validate()'s
## demand-area check (region grows), so any config that validates today still validates scaled up.
func _scaled_region_config(base: GenConfig, biome_slots: int) -> GenConfig:
	var c: GenConfig = base.duplicate(false)
	c.biome_slots = biome_slots
	if not c.validate():
		push_error("bench: scaled region config (biome_slots=%d) fails validate()" % biome_slots)
	return c


## In-memory only: the authored biome set duplicated (mult - 1) extra times, each copy id-suffixed
## and rewired to its own room types (also suffixed), so the packer and every per-biome layer see
## genuinely separate biomes rather than one biome shared across "copies". World-unique room types
## are left un-duplicated (still homed only in the original biomes) — duplicating a "world-unique"
## would misrepresent what the tag means, and this is a load-testing knob, not authored content.
## Shallow duplicate()s throughout: only scalar identity fields (id/biome/fallback/spawn room type)
## change, so sharing sub-resources (enemies, features, generator, presentation) by reference with
## the original is safe and avoids needlessly cloning art resources.
func _scaled_biome_count_config(base: GenConfig, mult: int) -> GenConfig:
	var c: GenConfig = base.duplicate(false)
	var biomes: Array[BiomeDef] = base.biomes.duplicate()
	var room_types: Array[RoomTypeDef] = base.room_types.duplicate()
	for copy_i in range(1, mult):
		var suffix := "_x%d" % copy_i
		for orig_b in base.biomes:
			var b2: BiomeDef = orig_b.duplicate(false)
			b2.id = StringName(String(orig_b.id) + suffix)
			if orig_b.fallback_room_type != &"":
				b2.fallback_room_type = StringName(String(orig_b.fallback_room_type) + suffix)
			if orig_b.spawn_room_type != &"":
				b2.spawn_room_type = StringName(String(orig_b.spawn_room_type) + suffix)
			biomes.append(b2)
		for orig_rt in base.room_types:
			if orig_rt.unique_scope != RoomTypeDef.UniqueScope.NONE:
				continue
			var rt2: RoomTypeDef = orig_rt.duplicate(false)
			rt2.id = StringName(String(orig_rt.id) + suffix)
			rt2.biome = StringName(String(orig_rt.biome) + suffix)
			room_types.append(rt2)
	c.biomes = biomes
	c.room_types = room_types
	if not c.validate():
		push_error("bench: scaled biome-count config (x%d) fails validate()" % mult)
	return c


func _stats(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {"median": 0.0, "p95": 0.0, "max": 0, "n": 0}
	var s: Array = samples.duplicate()
	s.sort()
	var n := s.size()
	var median: float
	if n % 2 == 1:
		median = s[n / 2]
	else:
		median = (s[n / 2 - 1] + s[n / 2]) / 2.0
	var p95_idx := int(ceil(0.95 * n)) - 1
	p95_idx = clampi(p95_idx, 0, n - 1)
	return {"median": median, "p95": s[p95_idx], "max": s[n - 1], "n": n}


func _fmt(s: Dictionary) -> String:
	if s.n == 0:
		return "(no samples)"
	return "median %8.3f ms  p95 %8.3f ms  max %8.3f ms  (n=%d)" \
			% [s.median / 1000.0, s.p95 / 1000.0, s.max / 1000.0, s.n]


func _median_int(a: Array) -> int:
	if a.is_empty():
		return 0
	var s: Array = a.duplicate()
	s.sort()
	return s[s.size() / 2]
