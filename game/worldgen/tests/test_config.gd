extends Node
## Headless config-sanity test for Task 2 (spec T5, §12). Loads the starter GenConfig and
## asserts the content invariants plus CONFIG_HASH stability/sensitivity. Run:
##   godot --headless --path game res://worldgen/tests/test_config.tscn

const CONFIG_PATH := "res://worldgen/content/gen_config.tres"


func _ready() -> void:
	var fails: Array[String] = []

	var cfg: GenConfig = ResourceLoader.load(CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if cfg == null:
		print("FAILED: 1")
		print("  FAIL: could not load ", CONFIG_PATH)
		get_tree().quit(1)
		return

	# --- summary ---
	var biome_ids: Array[StringName] = []
	for b in cfg.biomes:
		biome_ids.append(b.id)
	var room_type_ids: Array[StringName] = []
	for rt in cfg.room_types:
		room_type_ids.append(rt.id)
	print("=== GenConfig summary ===")
	print("  ROOM_SLOT_SIZE=%d  BIOME_SIZE_SLOTS=%d  WORLD_SIZE_BIOMES=%s  CHUNK_SIZE=%d  DOOR_WIDTH=%d"
		% [cfg.ROOM_SLOT_SIZE, cfg.BIOME_SIZE_SLOTS, str(cfg.WORLD_SIZE_BIOMES), cfg.CHUNK_SIZE, cfg.DOOR_WIDTH])
	print("  P_LOOP=%.2f  P_MERGE=%.2f  BORDER_CROSSINGS=%d" % [cfg.P_LOOP, cfg.P_MERGE, cfg.BORDER_CROSSINGS])
	print("  MAX_ROOM_RETRIES=%d  MAX_LAYOUT_RETRIES=%d  MIN_FLOOR_RATIO=%.2f"
		% [cfg.MAX_ROOM_RETRIES, cfg.MAX_LAYOUT_RETRIES, cfg.MIN_FLOOR_RATIO])
	print("  ROOM_CACHE_CAPACITY=%d  PREFETCH_RADIUS=%d  gen_version=%d"
		% [cfg.ROOM_CACHE_CAPACITY, cfg.PREFETCH_RADIUS, cfg.gen_version])
	print("  biomes: ", biome_ids)
	print("  room types: ", room_type_ids)

	# 1. Biome count matches the world grid (4 == 2*2).
	var expected_biomes := cfg.WORLD_SIZE_BIOMES.x * cfg.WORLD_SIZE_BIOMES.y
	if cfg.biomes.size() != expected_biomes:
		fails.append("biome count %d != grid %d" % [cfg.biomes.size(), expected_biomes])

	# 2. Reserved `traversal` room type present with generator `empty`.
	var trav := cfg.room_type_by_id(&"traversal")
	if trav == null:
		fails.append("traversal room type missing")
	elif trav.generator_id != &"empty":
		fails.append("traversal generator is '%s', expected 'empty'" % trav.generator_id)

	# 3. Per-biome free units >= biome-unique type count (81 slots vs BIOME-scoped types here).
	var slots_per_biome := cfg.BIOME_SIZE_SLOTS * cfg.BIOME_SIZE_SLOTS
	for b in cfg.biomes:
		var unique_count := 0
		for rt in cfg.room_types:
			if rt.unique_scope == RoomTypeDef.UniqueScope.BIOME and rt.allowed_biomes.has(b.id):
				unique_count += 1
		if slots_per_biome < unique_count:
			fails.append("biome %s: %d slots < %d biome-unique types" % [b.id, slots_per_biome, unique_count])

	# 4. Adjacency rule ids reference existing biomes.
	if cfg.adjacency == null:
		fails.append("adjacency rules missing")
	else:
		for r in cfg.adjacency.required + cfg.adjacency.forbidden:
			if cfg.biome_by_id(r.biome_a) == null:
				fails.append("adjacency references unknown biome '%s'" % r.biome_a)
			if cfg.biome_by_id(r.biome_b) == null:
				fails.append("adjacency references unknown biome '%s'" % r.biome_b)

	# 5. CONFIG_HASH: stable across two independent loads.
	var h1 := cfg.compute_hash()
	var cfg2: GenConfig = ResourceLoader.load(CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var h2 := cfg2.compute_hash()
	if h1 != h2:
		fails.append("compute_hash unstable across loads: %s vs %s" % [_hex(h1), _hex(h2)])
	# Deep duplicate reproduces the hash.
	var dup: GenConfig = cfg.duplicate(true)
	if dup.compute_hash() != h1:
		fails.append("duplicate(true) hash mismatch: %s" % _hex(dup.compute_hash()))
	# Mutating a constant changes the hash.
	dup.ROOM_SLOT_SIZE += 1
	if dup.compute_hash() == h1:
		fails.append("hash unchanged after mutating a constant")
	# Mutating a nested biome field changes the hash (folding recurses into biomes).
	var orig_open := cfg.biomes[0].openness
	cfg.biomes[0].openness = orig_open + 0.1
	if cfg.compute_hash() == h1:
		fails.append("hash unchanged after mutating a nested biome field")
	cfg.biomes[0].openness = orig_open
	if cfg.compute_hash() != h1:
		fails.append("hash did not restore after reverting nested field")

	# 6. prepare() precomputes integer thresholds.
	cfg.prepare()
	if cfg.threshold_loop != WgHash.threshold(cfg.P_LOOP):
		fails.append("threshold_loop wrong after prepare()")
	if cfg.threshold_merge != WgHash.threshold(cfg.P_MERGE):
		fails.append("threshold_merge wrong after prepare()")
	for b in cfg.biomes:
		if b.openness_threshold != WgHash.threshold(b.openness):
			fails.append("biome %s openness_threshold wrong after prepare()" % b.id)

	print("CONFIG_HASH = 0x%s" % _hex(h1))

	if fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for f in fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % fails.size())
		get_tree().quit(1)


func _hex(v: int) -> String:
	var s := String.num_uint64(v, 16).to_upper()
	while s.length() < 16:
		s = "0" + s
	return s
