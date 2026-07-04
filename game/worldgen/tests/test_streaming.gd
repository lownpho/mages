extends Node
## Headless tests for Layer 5 chunk streaming + presentation. Runs as a scene
## (it instantiates WorldStreamer/WgChunk nodes). Asserts:
##   - Chunk determinism: the same chunk assembled twice (caches cleared between) has byte-identical
##     RENDERED cell data (source id + atlas coords) on every layer.
##   - Eviction safety: a chunk whose rooms were evicted from the LRU re-assembles
##     identically; the LRU never exceeds room_cache_capacity.
##   - Performance: L2 biome-graph build,
##     L3+L4 room build, and chunk assembly from CACHED rooms, over ≥ 200 samples each.
## Run: godot --headless --path game res://worldgen/tests/test_streaming.tscn

const SAMPLES := 200


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://worldgen/content/gen_config.tres")
	var seed := 918_273_645

	var streamer := WorldStreamer.new()
	streamer.config = config
	streamer.build_world(seed)
	if streamer.world_spec == null:
		print("FAILED: 1")
		print("  FAIL: world layout returned null")
		get_tree().quit(1)
		return

	# --- Chunk determinism ----------------------------------------------------------------------
	print("== chunk determinism ==")
	# In-world chunks covering both biomes (world is 2 chunks wide × 4 tall: glade y0-1, deepwood y2-3).
	for coord in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 3)]:
		streamer.clear_room_cache()
		var a := streamer.assemble_chunk(coord.x, coord.y)
		var sa := _serialize(a)
		a.free()
		streamer.clear_room_cache()
		var b := streamer.assemble_chunk(coord.x, coord.y)
		var sb := _serialize(b)
		b.free()
		if sa != sb:
			fails.append("chunk %s not deterministic across rebuilds" % coord)
		elif sa.is_empty():
			fails.append("chunk %s rendered no cells (presentation missing?)" % coord)
	print("  checked 3 chunks, cleared cache between rebuilds")

	# --- Eviction safety ------------------------------------------------------------------------
	print("== eviction safety ==")
	var warm := streamer.assemble_chunk(0, 0)
	var s1 := _serialize(warm)
	warm.free()

	# Force real LRU eviction: request many OTHER distinct rooms until the cache overflows.
	var all_units := _all_units(streamer, config)
	for spec in all_units:
		streamer.get_room_output(spec)
	if streamer.room_cache_size() > config.room_cache_capacity:
		fails.append("room cache exceeded capacity: %d > %d"
				% [streamer.room_cache_size(), config.room_cache_capacity])

	var re := streamer.assemble_chunk(0, 0)   # its rooms were evicted → regenerated
	var s2 := _serialize(re)
	re.free()
	if s1 != s2:
		fails.append("chunk (0,0) differs after its rooms were evicted")
	print("  cache size %d/%d after touching %d rooms; post-eviction chunk identical"
			% [streamer.room_cache_size(), config.room_cache_capacity, all_units.size()])

	# --- Performance (report only) --------------------------------------------------------------
	print("== performance (%d samples each; budgets: L2 5ms / L3 10ms / assembly 1ms) ==" % SAMPLES)
	var bw := config.world_width_biomes
	var bh := config.world_height_biomes()

	var l2_us := 0
	for i in SAMPLES:
		var bc := Vector2i(i % bw, (i / bw) % bh)
		var t0 := Time.get_ticks_usec()
		RoomGraph.build(streamer.world_spec, bc, config)   # fresh, no cache
		l2_us += Time.get_ticks_usec() - t0

	var l3_us := 0
	for i in SAMPLES:
		var spec: RoomSpec = all_units[i % all_units.size()]
		var t0 := Time.get_ticks_usec()
		RoomBuilder.build(spec, config, seed)
		l3_us += Time.get_ticks_usec() - t0

	# Chunk assembly from CACHED rooms: warm chunk (2,2)'s rooms, then re-assemble repeatedly.
	streamer.assemble_chunk(0, 3).free()
	var asm_us := 0
	for _i in SAMPLES:
		var t0 := Time.get_ticks_usec()
		var c := streamer.assemble_chunk(0, 3)
		asm_us += Time.get_ticks_usec() - t0
		c.free()

	print("operation                     mean_ms  budget")
	print("L2 biome graph (fresh)        %7.3f  5.000" % [l2_us / 1000.0 / SAMPLES])
	print("L3+L4 room build              %7.3f  10.000" % [l3_us / 1000.0 / SAMPLES])
	print("chunk assembly (cached rooms) %7.3f  1.000" % [asm_us / 1000.0 / SAMPLES])

	streamer.free()

	if fails.is_empty():
		print("ALL PASS")
	else:
		for f in fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % fails.size())
	get_tree().quit(0 if fails.is_empty() else 1)


## Every room unit across the whole world, as flat RoomSpec list (canonical order per biome).
func _all_units(streamer: WorldStreamer, config: GenConfig) -> Array:
	var out: Array = []
	for by in config.world_height_biomes():
		for bx in config.world_width_biomes:
			var g := RoomGraph.build(streamer.world_spec, Vector2i(bx, by), config)
			for u in g.rooms:
				out.append(u)
	return out


## Real rendered cell data of a chunk, as a sorted String — compares source id + atlas coords on
## every layer, so it catches any presentation divergence. Layers
## are per-biome (`<biome>_floor`/`_wall`/`_blocker`/`_decor`), so iterate all TileMapLayer children.
func _serialize(chunk: WgChunk) -> String:
	var parts: Array[String] = []
	for child in chunk.get_children():
		if not (child is TileMapLayer):
			continue
		var layer: TileMapLayer = child
		var rows: Array[String] = []
		for cell in layer.get_used_cells():
			var a := layer.get_cell_atlas_coords(cell)
			rows.append("%d,%d:%d:%d,%d" % [cell.x, cell.y, layer.get_cell_source_id(cell), a.x, a.y])
		rows.sort()
		parts.append(String(layer.name) + "{" + ";".join(rows) + "}")
	parts.sort()
	return "|".join(parts)
