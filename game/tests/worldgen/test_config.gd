extends Node
## Headless config-sanity test. Loads the starter GenConfig and asserts the
## content invariants plus CONFIG_HASH stability/sensitivity — including the hash DIET: runtime
## dials and presentation fields must NOT move the hash. Run:
##   godot --headless --path game res://tests/worldgen/test_config.tscn

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
	print("  room_slot_tiles=%d  biome_slots=%d  world=%dx%d biomes  chunk_tiles=%d  door_width_tiles=%d"
		% [cfg.room_slot_tiles, cfg.biome_slots, cfg.world_width_biomes, cfg.world_height_biomes(),
			cfg.chunk_tiles, cfg.door_width_tiles])
	print("  extra_connection_chance=%.2f  room_merge_chance=%.2f  doors_per_biome_border=%d"
		% [cfg.extra_connection_chance, cfg.room_merge_chance, cfg.doors_per_biome_border])
	print("  max_room_retries=%d  max_layout_retries=%d  min_reachable_floor_ratio=%.2f"
		% [cfg.max_room_retries, cfg.max_layout_retries, cfg.min_reachable_floor_ratio])
	print("  room_cache_capacity=%d  prefetch_radius_chunks=%d  gen_version=%d"
		% [cfg.room_cache_capacity, cfg.prefetch_radius_chunks, cfg.gen_version])
	print("  biomes: ", biome_ids)
	print("  room types: ", room_type_ids)

	# 1. The biome list tiles the world grid exactly (validate() is the loud gate).
	if not cfg.validate():
		fails.append("validate() rejected the shipped config")
	if cfg.biomes.size() != cfg.world_width_biomes * cfg.world_height_biomes():
		fails.append("biome count %d != %dx%d grid"
				% [cfg.biomes.size(), cfg.world_width_biomes, cfg.world_height_biomes()])

	# 2. The fallback room type exists and has no generator (empty interior by construction).
	var fallback := cfg.room_type_by_id(cfg.fallback_room_type)
	if fallback == null:
		fails.append("fallback room type '%s' missing" % cfg.fallback_room_type)
	elif fallback.generator != null:
		fails.append("fallback room type '%s' has a generator — must be empty" % cfg.fallback_room_type)
	# The starting biome must exist too (player spawn + presentation fallback).
	if cfg.biome_by_id(cfg.starting_biome) == null:
		fails.append("starting biome '%s' missing" % cfg.starting_biome)

	# 3. Per-biome free rooms >= biome-unique type count.
	var slots_per_biome := cfg.biome_slots * cfg.biome_slots
	for b in cfg.biomes:
		var unique_count := 0
		for rt in cfg.room_types:
			if rt.unique_scope == RoomTypeDef.UniqueScope.BIOME and rt.unique_allowed_biomes.has(b.id):
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

	# 5. CONFIG_HASH: stable across two independent loads, and cached (second call identical).
	var h1 := cfg.compute_hash()
	if cfg.compute_hash() != h1:
		fails.append("compute_hash not stable across calls (cache broken)")
	var cfg2: GenConfig = ResourceLoader.load(CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var h2 := cfg2.compute_hash()
	if h1 != h2:
		fails.append("compute_hash unstable across loads: %s vs %s" % [_hex(h1), _hex(h2)])
	# Deep duplicate reproduces the hash (duplicates start uncached — plain vars don't copy).
	if cfg.duplicate(true).compute_hash() != h1:
		fails.append("duplicate(true) hash mismatch")

	# 6. Hash SENSITIVITY: world-affecting fields must move the hash. Top-level probes mutate
	# a duplicate (the hash is cached on first use, so a hashed config must never be mutated);
	# nested probes mutate-and-revert on cfg — duplicate(true) SHARES the external biome/room-
	# type .tres subresources, so mutating them on a duplicate would leak into cfg — and
	# compare the uncached fold directly to bypass cfg's cache.
	var dup: GenConfig = cfg.duplicate(true)
	dup.room_slot_tiles += 1
	_expect_changed(fails, h1, dup.compute_hash(), "room_slot_tiles")
	dup = cfg.duplicate(true)
	dup.extra_connection_chance += 0.1
	_expect_changed(fails, h1, dup.compute_hash(), "extra_connection_chance")
	dup = cfg.duplicate(true)
	dup.starting_biome = &"elsewhere"
	_expect_changed(fails, h1, dup.compute_hash(), "starting_biome")
	dup = cfg.duplicate(true)
	dup.wall_extra_depth += 1
	_expect_changed(fails, h1, dup.compute_hash(), "wall_extra_depth")
	dup = cfg.duplicate(true)
	dup.corner_radius += 1
	_expect_changed(fails, h1, dup.compute_hash(), "corner_radius")

	cfg.biomes[0].open_passage_chance += 0.1
	_expect_changed(fails, h1, cfg._compute_hash_uncached(), "biome open_passage_chance")
	cfg.biomes[0].open_passage_chance -= 0.1
	cfg.room_types[0].enemy_groups_max += 1
	_expect_changed(fails, h1, cfg._compute_hash_uncached(), "room type budget")
	cfg.room_types[0].enemy_groups_max -= 1
	var scatter: RoomGenScatter = null
	for rt in cfg.room_types:
		if rt.generator is RoomGenScatter:
			scatter = rt.generator
			break
	if scatter == null:
		fails.append("no scatter generator in config to probe")
	else:
		scatter.count_per_slot += 1
		_expect_changed(fails, h1, cfg._compute_hash_uncached(), "generator field")
		scatter.count_per_slot -= 1
	if cfg._compute_hash_uncached() != h1:
		fails.append("hash did not restore after reverting nested probes")

	# 7. Hash DIET: runtime/presentation fields must NOT move the hash (tuning them can't
	# re-roll saved worlds).
	dup = cfg.duplicate(true)
	dup.chunk_tiles *= 2
	_expect_same(fails, h1, dup.compute_hash(), "chunk_tiles")
	dup = cfg.duplicate(true)
	dup.max_layout_retries += 100
	_expect_same(fails, h1, dup.compute_hash(), "max_layout_retries")
	dup = cfg.duplicate(true)
	dup.room_cache_capacity += 16
	_expect_same(fails, h1, dup.compute_hash(), "room_cache_capacity")
	dup = cfg.duplicate(true)
	dup.prefetch_radius_chunks += 1
	_expect_same(fails, h1, dup.compute_hash(), "prefetch_radius_chunks")

	var orig_color: Color = cfg.biomes[0].display_color
	cfg.biomes[0].display_color = Color.MAGENTA
	_expect_same(fails, h1, cfg._compute_hash_uncached(), "biome display_color")
	cfg.biomes[0].display_color = orig_color
	var orig_pres: BiomePresentation = cfg.biomes[0].presentation
	cfg.biomes[0].presentation = null
	_expect_same(fails, h1, cfg._compute_hash_uncached(), "biome presentation")
	cfg.biomes[0].presentation = orig_pres

	print("CONFIG_HASH = 0x%s" % _hex(h1))

	if fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for f in fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % fails.size())
		get_tree().quit(1)


func _expect_changed(fails: Array[String], h1: int, h: int, what: String) -> void:
	if h == h1:
		fails.append("hash unchanged after mutating %s" % what)


func _expect_same(fails: Array[String], h1: int, h: int, what: String) -> void:
	if h != h1:
		fails.append("hash CHANGED after mutating %s (should be outside CONFIG_HASH)" % what)


func _hex(v: int) -> String:
	var s := String.num_uint64(v, 16).to_upper()
	while s.length() < 16:
		s = "0" + s
	return s
